"""llama.cpp embedding client with persistent SQLite caching and delegated lifecycle management."""

from __future__ import annotations

import asyncio
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
from typing import Any

import aiohttp

from .embedder_lifecycle import ensure_server, touch, shutdown


class LlamaCppEmbedder:
    """Use an existing llama-server, automatically spawn one in the background, or fallback to CLI/remote."""

    def __init__(
        self,
        endpoint: str | None = None,
        model_path: str | None = None,
        store: Any | None = None,
    ) -> None:
        self.endpoint = (endpoint or os.getenv("DEEP_RESEARCH_EMBEDDING_URL") or "http://127.0.0.1:8080").rstrip("/")
        self.model_path = Path(model_path).expanduser() if model_path else self._discover_model()
        self.store = store

        # Resolve model name for caching purposes
        self.model_name = os.getenv("DEEP_RESEARCH_EMBEDDING_MODEL_NAME") or (
            self.model_path.name if self.model_path else "embeddinggemma-300m"
        )
        self.cli_embedding_concurrency = max(
            1,
            int(os.getenv("DR_CLI_EMBED_CONCURRENCY", "1")),
        )
        self._cache: dict[str, list[float]] = {}
        self.subprocess_calls = 0  # Metric tracker for eval loops

    @staticmethod
    def _discover_model() -> Path | None:
        configured = os.getenv("DEEP_RESEARCH_EMBEDDING_MODEL")
        candidates = [Path(configured).expanduser()] if configured else []

        # Check relative to projects folder (python_bridge/models/)
        pkg_dir = Path(__file__).resolve().parents[2]
        candidates.append(pkg_dir / "models" / "embeddinggemma-300m-Q4_0.gguf")

        home = Path.home()
        candidates.extend([
            home / "embeddinggemma-300m-Q4_0.gguf",
            home / "models" / "embeddinggemma-300m-Q4_0.gguf",
            home / "downloads" / "embeddinggemma-300m-Q4_0.gguf",
            home / "storage" / "downloads" / "embeddinggemma-300m-Q4_0.gguf",
        ])
        return next((path for path in candidates if path.is_file()), None)

    async def embed_texts(self, texts: list[str]) -> list[list[float]]:
        if not texts:
            return []

        embeddings_map: dict[str, list[float]] = {}
        to_embed: list[str] = []
        pending_texts: set[str] = set()

        # 1. Resolve from cache layer
        for t in texts:
            # In-memory lookup
            if t in self._cache:
                embeddings_map[t] = self._cache[t]
                continue

            # SQLite persistent lookup
            if self.store is not None:
                content_hash = hashlib.sha256(t.encode("utf-8")).hexdigest()
                cached = self.store.get_cached_embedding(content_hash, self.model_name)
                if cached is not None:
                    self._cache[t] = cached
                    embeddings_map[t] = cached
                    continue

            # A single ingestion batch can contain repeated section/chunk
            # representations.  Keep one pending request; the result is
            # mapped back to every matching input below.
            if t not in pending_texts:
                to_embed.append(t)
                pending_texts.add(t)

        # 2. Run fallback embedding pipeline for non-cached items
        if to_embed:
            # Delegate server verification/startup to the robust lifecycle manager
            if self.model_path:
                await asyncio.to_thread(ensure_server, str(self.model_path), self.endpoint)

            new_embeddings = None
            fallback_errors: list[str] = []

            # Fallback 1: Local HTTP embedding server
            try:
                new_embeddings = await self._embed_http(to_embed)
            except Exception as e:
                fallback_errors.append(f"HTTP server failed: {str(e)[:100]}")

            # Fallback 2: Local CLI subprocess (runs llama-embedding as fallback)
            if new_embeddings is None and os.getenv("DEEP_RESEARCH_DISABLE_CLI") != "1":
                try:
                    new_embeddings = await self._embed_cli_batched(to_embed)
                except Exception as e:
                    fallback_errors.append(f"CLI subprocess failed: {str(e)[:100]}")

            # Fallback 3: Remote provider API (Gemini or OpenAI)
            if new_embeddings is None:
                try:
                    new_embeddings = await self._embed_remote(to_embed)
                except Exception as e:
                    fallback_errors.append(f"Remote provider failed: {str(e)[:100]}")

            # Verify that we received embeddings
            if new_embeddings is None:
                errors_summary = " | ".join(fallback_errors)
                raise RuntimeError(
                    f"All embedding fallbacks failed. Errors: {errors_summary}. "
                    "Verify embedding server status or API key configurations."
                )

            # Store in caches
            for text, vector in zip(to_embed, new_embeddings):
                self._cache[text] = vector
                if self.store is not None:
                    content_hash = hashlib.sha256(text.encode("utf-8")).hexdigest()
                    self.store.save_cached_embedding(
                        content_hash,
                        self.model_name,
                        len(text),
                        vector,
                        {"source": "ingest_run"},
                    )
                embeddings_map[text] = vector

        return [embeddings_map[t] for t in texts]

    # ── Embedding Request Primitives ──────────────────────────────────

    async def _embed_http(self, texts: list[str]) -> list[list[float]]:
        async with aiohttp.ClientSession() as session:
            async with session.post(
                f"{self.endpoint}/embedding",
                json={"content": texts},
                headers={"Connection": "close"},
                timeout=aiohttp.ClientTimeout(total=30)
            ) as response:
                if response.status >= 300:
                    raise ValueError(f"HTTP server returned status {response.status}")
                # Refresh idle timer in lifecycle manager
                touch()
                return self._parse_response(await response.json())

    async def _embed_cli_batched(self, texts: list[str]) -> list[list[float]]:
        if self.model_path is None:
            raise FileNotFoundError("Local model path not found for CLI execution.")
        self.subprocess_calls += len(texts)
        gate = asyncio.Semaphore(self.cli_embedding_concurrency)

        async def embed_one(text: str) -> list[float]:
            async with gate:
                return await asyncio.to_thread(self._embed_local, text)

        return await asyncio.gather(*(embed_one(text) for text in texts))

    def _embed_local(self, text: str) -> list[float]:
        binary = shutil.which("llama-embedding")
        if not binary:
            raise RuntimeError("llama-embedding binary is not installed")

        preview = text[:60] + "..." if len(text) > 60 else text

        result = subprocess.run(
            [binary, "-m", str(self.model_path), "--embd-output-format", "json", "-p", text],
            capture_output=True, text=True, check=False, timeout=120,
        )
        if result.returncode:
            raise RuntimeError(f"llama-embedding failed for '{preview}': {result.stderr.strip()[:100]}")
        match = re.search(r"\[[\s\S]*\]", result.stdout)
        if not match:
            raise RuntimeError(f"llama-embedding returned no JSON vector for '{preview}'")
        vectors = self._parse_response(json.loads(match.group(0)))
        if len(vectors) != 1:
            raise RuntimeError(f"llama-embedding returned unexpected count for '{preview}'")
        return vectors[0]

    async def _embed_remote(self, texts: list[str]) -> list[list[float]] | None:
        """Call remote providers (Gemini or OpenAI) as a fallback."""
        gemini_key = os.getenv("GEMINI_API_KEY")
        openai_key = os.getenv("OPENAI_API_KEY")
        openai_base = os.getenv("OPENAI_BASE_URL", "https://api.openai.com/v1")

        if gemini_key:
            url = f"https://generativelanguage.googleapis.com/v1beta/models/text-embedding-004:batchEmbedContents?key={gemini_key}"
            payload = {
                "requests": [
                    {
                        "model": "models/text-embedding-004",
                        "content": {"parts": [{"text": t}]}
                    }
                    for t in texts
                ]
            }
            try:
                async with aiohttp.ClientSession() as session:
                    async with session.post(url, json=payload, timeout=aiohttp.ClientTimeout(total=30)) as resp:
                        if resp.status < 300:
                            data = await resp.json()
                            embeddings = []
                            for r in data.get("embeddings", []):
                                embeddings.append([float(val) for val in r.get("values", [])])
                            if len(embeddings) == len(texts):
                                return embeddings
            except Exception:
                pass

        if openai_key:
            url = f"{openai_base.rstrip('/')}/embeddings"
            payload = {
                "input": texts,
                "model": "text-embedding-3-small"
            }
            headers = {
                "Authorization": f"Bearer {openai_key}",
                "Content-Type": "application/json"
            }
            try:
                async with aiohttp.ClientSession() as session:
                    async with session.post(url, json=payload, headers=headers, timeout=aiohttp.ClientTimeout(total=30)) as resp:
                        if resp.status < 300:
                            data = await resp.json()
                            embeddings = []
                            sorted_data = sorted(data.get("data", []), key=lambda x: x.get("index", 0))
                            for item in sorted_data:
                                embeddings.append([float(val) for val in item.get("embedding", [])])
                            if len(embeddings) == len(texts):
                                return embeddings
            except Exception:
                pass

        return None

    @staticmethod
    def _parse_response(payload: Any) -> list[list[float]]:
        # Extract list of items
        if isinstance(payload, dict):
            if "data" in payload:
                items = payload["data"]
            else:
                items = [payload]
        else:
            items = payload

        if not isinstance(items, list):
            items = [items]

        results = []
        for item in items:
            vector = item
            if isinstance(item, dict):
                for key in ("embedding", "values", "vec"):
                    if key in item:
                        vector = item[key]
                        break

            if isinstance(vector, list):
                # Handle nested list structures from newer llama-server versions
                if len(vector) > 0 and isinstance(vector[0], list):
                    vector = vector[0]

                try:
                    float_vector = [float(v) for v in vector]
                    results.append(float_vector)
                except Exception:
                    pass

        if not results:
            raise ValueError(f"Could not parse any embedding vectors from payload: {payload}")

        return results

    def close(self) -> None:
        """Shut down the background server delegated lifecycle instance."""
        shutdown()
