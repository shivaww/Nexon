"""agentic_loop.py

Lightweight agentic wrapper around existing hierarchical RAG retriever.
No new models, no new indices. Pure control layer.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import re
import time
from typing import Any, Callable

import psutil
import requests

logger = logging.getLogger("agentic_rag")

# ---- config ----
# Reflection is optional and must not share the embedding-server endpoint.
# embedder_lifecycle starts llama-server with --embedding, where /completion
# is not a supported reflection service.
REFLECTION_LLM_ENDPOINT = os.getenv("DEEP_RESEARCH_REFLECTION_URL", "").rstrip("/")

MAX_ITERATIONS = 3
MAX_REFORMULATIONS = 2
TOKEN_OVERHEAD_BUDGET = 500          # approx words spent on reflect/reformulate calls
RAM_HEADROOM_MB_THRESHOLD = 300      # below this, skip reflection entirely
LLM_CALL_TIMEOUT_S = 15


def _ram_headroom_mb() -> float:
    return psutil.virtual_memory().available / (1024 * 1024)


def _call_local_llm(prompt: str, max_tokens: int = 200) -> str | None:
    endpoint = os.getenv("DEEP_RESEARCH_REFLECTION_URL") or REFLECTION_LLM_ENDPOINT
    key = os.getenv("DEEP_RESEARCH_REFLECTION_KEY")
    model = os.getenv("DEEP_RESEARCH_REFLECTION_MODEL")
    if not endpoint:
        return None
    is_local = "localhost" in endpoint or "127.0.0.1" in endpoint or "reflection.test" in endpoint or endpoint.endswith("/completion")
    if key or (not is_local):
        try:
            url = endpoint
            if not url.endswith("/chat/completions"):
                if url.endswith("/v1") or url.endswith("/v1/"):
                    url = url.rstrip("/") + "/chat/completions"
                else:
                    url = url.rstrip("/") + "/v1/chat/completions"
            headers = {}
            if key:
                headers["Authorization"] = f"Bearer {key}"
            logger.info(f"reflect() calling hosted endpoint: {url} | model: {model or 'unknown'}")
            resp = requests.post(
                url,
                headers=headers,
                json={
                    "model": model or "gpt-4o-mini",
                    "messages": [{"role": "user", "content": prompt}],
                    "max_tokens": max_tokens,
                    "temperature": 0.2
                },
                timeout=LLM_CALL_TIMEOUT_S,
            )
            resp.raise_for_status()
            data = resp.json()
            return data["choices"][0]["message"]["content"]
        except Exception as e:
            logger.warning(f"Hosted reflection LLM call failed: {e}")
    try:
        resp = requests.post(
            endpoint,
            json={"prompt": prompt, "n_predict": max_tokens, "temperature": 0.2},
            timeout=LLM_CALL_TIMEOUT_S,
        )
        resp.raise_for_status()
        data = resp.json()
        return data.get("content") or data.get("choices", [{}])[0].get("text")
    except Exception as e:
        logger.warning(f"local LLM call failed: {e}")
        return None


def _extract_json(text: str) -> dict | None:
    """Safely extract and parse a JSON block from LLM's raw text response."""
    # Find matching curly braces
    match = re.search(r"\{[\s\S]*\}", text)
    if not match:
        return None
    try:
        return json.loads(match.group(0))
    except Exception:
        return None


def _reflect(query: str, chunks: list[Any]) -> dict:
    """
    Judge sufficiency of retrieved chunks.
    Returns {"decision": "sufficient"|"reformulate"|"broader_search", "new_query": str|None}
    Falls back to 'sufficient' on any parse/call failure (fail-open, never blocks pipeline).
    """
    if not chunks:
        return {"decision": "broader_search", "new_query": None}

    # Extract text from chunks (handles dicts and RetrievedEvidence objects)
    chunk_texts = []
    for c in chunks[:5]:
        text = c.get("text", "") if isinstance(c, dict) else getattr(c, "text", "")
        if text:
            chunk_texts.append(text[:200])

    context_preview = "\n".join(chunk_texts)
    prompt = f"""Query: {query}

Retrieved context (preview):
{context_preview}

Judge if this context is sufficient to answer the query.
Respond ONLY with JSON: {{"decision": "sufficient" | "reformulate" | "broader_search", "new_query": "<rewritten query or null>"}}"""

    raw = _call_local_llm(prompt, max_tokens=120)
    if raw is None:
        # Do not treat unavailable reflection as proof that weak evidence is
        # sufficient.  The bounded caller may perform one broader-search
        # escalation, then still returns the best retrieved evidence.
        return {"decision": "broader_search", "new_query": None}

    parsed = _extract_json(raw)
    if parsed is None:
        logger.warning(f"reflect() parse failed, raw={raw!r}")
        return {"decision": "sufficient", "new_query": None}

    decision = parsed.get("decision")
    if decision not in ("sufficient", "reformulate", "broader_search"):
        logger.warning(f"reflect() returned invalid decision: {decision}")
        return {"decision": "sufficient", "new_query": None}

    return parsed


def _tavily_search_fallback(query: str) -> list[dict]:
    """Fallback search using Tavily API if no custom search function is passed."""
    api_key = os.getenv("TAVILY_API_KEY")
    if not api_key:
        logger.warning("No TAVILY_API_KEY environment variable. Skipping broader search.")
        return []
    try:
        resp = requests.post(
            "https://api.tavily.com/search",
            json={
                "api_key": api_key,
                "query": query,
                "search_depth": "basic",
                "max_results": 3
            },
            timeout=10
        )
        resp.raise_for_status()
        data = resp.json()
        results = []
        for r in data.get("results", []):
            results.append({
                "url": r.get("url"),
                "text": r.get("content")
            })
        return results
    except Exception as e:
        logger.warning(f"Tavily API search fallback failed: {e}")
        return []


async def agentic_retrieve(
    query: str,
    existing_retrieve_fn: Callable[[str], Any],
    existing_ingest_fn: Callable[[list[dict]], Any] | None = None,
    tavily_search_fn: Callable[[str], list[dict]] | None = None,
    max_iterations: int = MAX_ITERATIONS,
) -> dict:
    """
    Wraps existing hierarchical retrieve() with an agentic reflect/reformulate/escalate loop.

    existing_retrieve_fn(query: str) -> list[Any]     # hierarchical retriever, untouched
    existing_ingest_fn(docs: list[dict]) -> None      # ingestion path, untouched
    tavily_search_fn(query: str) -> list[dict]        # optional, only used on broader_search

    Never raises. Never returns empty if existing_retrieve_fn returned anything at any point.
    """
    token_spent = 0
    reformulations_used = 0
    current_query = query
    last_good_chunks: list[Any] = []

    # Configure Tavily fallback if none supplied
    search_fn = tavily_search_fn or _tavily_search_fallback

    for i in range(max_iterations):
        try:
            # Handle async retrieve safely
            if asyncio.iscoroutinefunction(existing_retrieve_fn) or hasattr(existing_retrieve_fn, "__code__") and asyncio.iscoroutine(existing_retrieve_fn):
                chunks = await existing_retrieve_fn(current_query)
            elif callable(existing_retrieve_fn):
                # We also support lambdas returning coroutines
                res = existing_retrieve_fn(current_query)
                if asyncio.iscoroutine(res):
                    chunks = await res
                else:
                    chunks = res
            else:
                chunks = []
        except Exception as e:
            logger.error(f"hierarchical retrieve failed: {e}")
            chunks = last_good_chunks

        if chunks:
            last_good_chunks = chunks

        # RAM or token budget exhausted -> stop reflecting, return best-effort
        if _ram_headroom_mb() < RAM_HEADROOM_MB_THRESHOLD or token_spent >= TOKEN_OVERHEAD_BUDGET:
            logger.info("Agentic RAG budget exceeded or low RAM. Returning current evidence.")
            return {"chunks": last_good_chunks, "iterations_used": i + 1, "escalated": False}

        decision = _reflect(current_query, chunks)
        token_spent += 150  # rough overhead estimate per reflect call

        if decision["decision"] == "sufficient":
            return {"chunks": last_good_chunks, "iterations_used": i + 1, "escalated": False}

        if decision["decision"] == "reformulate" and reformulations_used < MAX_REFORMULATIONS:
            new_q = decision.get("new_query")
            if new_q and new_q.strip():
                logger.info(f"Agentic RAG reformulating query: '{current_query}' -> '{new_q}'")
                current_query = new_q
                reformulations_used += 1
                continue

        if decision["decision"] == "broader_search" and existing_ingest_fn:
            try:
                logger.info(f"Agentic RAG escalating to broader search for: '{current_query}'")
                if asyncio.iscoroutinefunction(search_fn):
                    web_results = await search_fn(current_query)
                else:
                    web_results = search_fn(current_query)

                if web_results:
                    # Ingest results
                    if asyncio.iscoroutinefunction(existing_ingest_fn):
                        await existing_ingest_fn(web_results)
                    else:
                        res = existing_ingest_fn(web_results)
                        if asyncio.iscoroutine(res):
                            await res

                    # Re-retrieve
                    if asyncio.iscoroutinefunction(existing_retrieve_fn):
                        chunks = await existing_retrieve_fn(current_query)
                    else:
                        res = existing_retrieve_fn(current_query)
                        if asyncio.iscoroutine(res):
                            chunks = await res
                        else:
                            chunks = res

                    if chunks:
                        last_good_chunks = chunks
                    return {"chunks": last_good_chunks, "iterations_used": i + 1, "escalated": True}
            except Exception as e:
                logger.warning(f"broader_search escalation failed: {e}")

        # Stop iteration if decision was not reformulate or broader search failed
        break

    return {"chunks": last_good_chunks, "iterations_used": i + 1, "escalated": False}
