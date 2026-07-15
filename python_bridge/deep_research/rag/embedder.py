"""llama.cpp embedding client with a local command fallback."""

from __future__ import annotations

import asyncio
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
from typing import Any

import aiohttp


class LlamaCppEmbedder:
    """Use an existing llama-server `/embedding` endpoint or llama-embedding."""

    def __init__(self, endpoint: str | None = None, model_path: str | None = None) -> None:
        self.endpoint = (endpoint or os.getenv("DEEP_RESEARCH_EMBEDDING_URL") or "http://127.0.0.1:8080").rstrip("/")
        self.model_path = Path(model_path).expanduser() if model_path else self._discover_model()

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
        try:
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    f"{self.endpoint}/embedding", json={"content": texts}, timeout=aiohttp.ClientTimeout(total=30)
                ) as response:
                    if response.status < 300:
                        return self._parse_response(await response.json())
        except (aiohttp.ClientError, asyncio.TimeoutError, ValueError):
            pass
        if self.model_path is None:
            raise RuntimeError(
                "Embedding model unavailable. Start llama-server with --embedding or set "
                "DEEP_RESEARCH_EMBEDDING_MODEL to embeddinggemma-300m-Q4_0.gguf."
            )
        return await asyncio.gather(*(asyncio.to_thread(self._embed_local, text) for text in texts))

    @staticmethod
    def _parse_response(payload: Any) -> list[list[float]]:
        items = payload.get("data", payload) if isinstance(payload, dict) else payload
        if isinstance(items, dict):
            items = [items]
        vectors = [item.get("embedding", item) if isinstance(item, dict) else item for item in items]
        if not vectors or not all(isinstance(vector, list) for vector in vectors):
            raise ValueError("llama-server returned no embeddings")
        return [[float(value) for value in vector] for vector in vectors]

    def _embed_local(self, text: str) -> list[float]:
        binary = shutil.which("llama-embedding")
        if not binary:
            raise RuntimeError("llama-embedding binary is not installed")
        result = subprocess.run(
            [binary, "-m", str(self.model_path), "--embd-output-format", "json", "-p", text],
            capture_output=True, text=True, check=False, timeout=120,
        )
        if result.returncode:
            raise RuntimeError(result.stderr.strip() or "llama-embedding failed")
        match = re.search(r"\[[\s\S]*\]", result.stdout)
        if not match:
            raise RuntimeError("llama-embedding returned no JSON vector")
        vectors = self._parse_response(json.loads(match.group(0)))
        if len(vectors) != 1:
            raise RuntimeError("llama-embedding returned an unexpected vector count")
        return vectors[0]
