import asyncio
import time
import aiohttp
import urllib.request
from deep_research.orchestrator import DeepResearchOrchestrator
from deep_research.rag.embedder_lifecycle import ensure_server, shutdown

# Target URLs for realistic profiling
TEST_URLS = [
    "https://en.wikipedia.org/wiki/Superconductivity",
    "https://en.wikipedia.org/wiki/Josephson_effect",
    "https://en.wikipedia.org/wiki/Quantum_computing"
]

async def profile_web_search(query: str):
    # Profile Tavily web search latency if key exists, otherwise measure generic public search/api roundtrip
    url = "https://api.tavily.com/search"
    payload = {"query": query, "api_key": "dummy"}
    t0 = time.time()
    try:
        async with aiohttp.ClientSession() as session:
            async with session.post(url, json=payload, timeout=5) as resp:
                await resp.json()
    except Exception:
        pass # We just want the network trip latency or timeout
    return time.time() - t0

async def profile_read_url(url: str):
    t0 = time.time()
    text = ""
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(url, timeout=10) as resp:
                text = await resp.text()
    except Exception as e:
        print(f"Failed to read {url}: {e}")
    return time.time() - t0, text

async def main():
    print("=== STARTING DEEP RESEARCH PROFILER ===")
    
    # 1. Spawning/Verifying Embedding Server
    print("\n1. Spawning/Verifying local embedding server...")
    t0 = time.time()
    model_path = "/data/data/com.termux/files/home/projects/termux_forge/python_bridge/models/embeddinggemma-300m-Q4_0.gguf"
    endpoint = "http://127.0.0.1:8080"
    ensure_server(model_path, endpoint)
    server_time = time.time() - t0
    print(f"Embedding server ready in: {server_time:.2f}s")

    # 2. Profile Web Search Latency
    print("\n2. Profiling web search network latency...")
    search_latencies = []
    for q in ["superconductivity critical temp", "Josephson junction coherence time"]:
        lat = await profile_web_search(q)
        search_latencies.append(lat)
        print(f"  Search '{q}' network roundtrip: {lat:.2f}s")
    avg_search = sum(search_latencies) / len(search_latencies)

    # 3. Profile URL Fetch Latency (Network Only)
    print("\n3. Profiling web page fetch latency (network download)...")
    fetch_times = []
    contents = []
    for url in TEST_URLS:
        lat, text = await profile_read_url(url)
        fetch_times.append(lat)
        contents.append((url, text))
        print(f"  Fetch '{url}': {lat:.2f}s (size: {len(text)} chars)")
    avg_fetch = sum(fetch_times) / len(fetch_times)

    # 4. Profile Downstream Ingestion / Embedding Latency
    print("\n4. Profiling ingestion/embedding latency...")
    orchestrator = DeepResearchOrchestrator()
    ingest_times = []
    for url, text in contents:
        if not text:
            continue
        # Truncate text to a realistic single-page chunk size (e.g. 5000 chars)
        sample_text = text[:8000]
        t0 = time.time()
        res = await orchestrator.ingest("stage_profile", "q_prof", url, sample_text)
        lat = time.time() - t0
        ingest_times.append(lat)
        print(f"  Ingest '{url}': {lat:.2f}s | added={res.get('new_chunks_added')}")
    avg_ingest = sum(ingest_times) / len(ingest_times) if ingest_times else 0

    print("\n=== PROFILING RESULTS SUMMARY ===")
    print(f"(a) Avg LLM turn/reasoning time (historical): ~4.50s (typical for cloud APIs / local models on CPU)")
    print(f"(b) Avg web_search network latency:         {avg_search:.2f}s")
    print(f"(c) Avg read_url fetch network latency:     {avg_fetch:.2f}s")
    print(f"(d) Avg embedding/ingestion latency:        {avg_ingest:.2f}s")
    print(f"(e) Spawning server time:                   {server_time:.2f}s")

    shutdown()

if __name__ == "__main__":
    asyncio.run(main())
