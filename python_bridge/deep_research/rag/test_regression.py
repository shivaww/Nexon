"""Regression test for embedder hang on sequential requests."""

from __future__ import annotations

import asyncio
import time
from deep_research.rag.embedder import LlamaCppEmbedder


async def run_regression_test() -> None:
    print("\n--- Running Embedder Hang Regression Test ---")
    embedder = LlamaCppEmbedder()
    
    if not embedder.model_path or not embedder.model_path.is_file():
        print("Skipping regression test: local embedding model not found.")
        return

    print(f"Using discovered model: {embedder.model_path}")
    
    try:
        # Request 1
        print("Sending request 1...")
        t0 = time.time()
        res1 = await embedder.embed_texts(["This is the first test text."])
        print(f"Request 1 succeeded in {time.time() - t0:.2f}s")
        assert len(res1) == 1
        assert len(res1[0]) > 0

        # Request 2
        print("Sending request 2...")
        t0 = time.time()
        res2 = await embedder.embed_texts(["This is the second test text."])
        print(f"Request 2 succeeded in {time.time() - t0:.2f}s")
        assert len(res2) == 1
        assert len(res2[0]) > 0

        # Request 3
        print("Sending request 3...")
        t0 = time.time()
        res3 = await embedder.embed_texts(["This is the third test text."])
        print(f"Request 3 succeeded in {time.time() - t0:.2f}s")
        assert len(res3) == 1
        assert len(res3[0]) > 0
        
        print("PASS: Regression test completed successfully without hanging!")
        
    finally:
        print("Shutting down embedder...")
        embedder.close()


if __name__ == "__main__":
    asyncio.run(run_regression_test())
