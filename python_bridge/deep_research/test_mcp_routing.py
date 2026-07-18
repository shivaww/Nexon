import asyncio
import os
import sys
from pathlib import Path

BRIDGE_DIR = Path(__file__).resolve().parents[1]
if str(BRIDGE_DIR) not in sys.path:
    sys.path.insert(0, str(BRIDGE_DIR))

from termux_forge_bridge import TermuxForgeBridge

async def main():
    os.environ["DEEP_RESEARCH_DISABLE_CLI"] = "1"
    os.environ["TAVILY_API_KEY"] = os.getenv("TAVILY_API_KEY", "dummy_key")
    
    bridge = TermuxForgeBridge()
    
    print("Testing web_search method on bridge...")
    res = await bridge._web_search(query="superconductivity critical temperature")
    if "error" in res:
        print(f"web_search failed gracefully (expected if API key missing): {res['error']}")
    else:
        assert "results" in res
        assert isinstance(res["results"], list)
        for r in res["results"]:
            assert "title" in r
            assert "url" in r
            assert "snippet" in r
        print("web_search returned results in expected shape.")

    print("\nTesting read_url method on bridge with HTML page...")
    res2 = await bridge._read_url(url="https://example.com", stage_id="stage_mcp_test", query_id="query_mcp_test")
    if "error" in res2:
        print(f"read_url HTML failed: {res2['error']}")
    else:
        assert res2["parse_format"] == "html"
        assert "new_chunks_added" in res2
        assert "stage" in res2
        assert res2["stage"] == "stage_mcp_test"
        assert "content" in res2
        print("read_url HTML returned results in expected shape.")

    print("\nTesting read_url method on bridge with PDF file...")
    res3 = await bridge._read_url(url="https://arxiv.org/pdf/2403.00001.pdf", stage_id="stage_mcp_test", query_id="query_mcp_test")
    if "error" in res3:
        print(f"read_url PDF failed gracefully: {res3['error']}")
    else:
        assert res3["parse_format"] == "pdf"
        assert "new_chunks_added" in res3
        assert "content" in res3
        print("read_url PDF returned results in expected shape.")

    from deep_research.rag.embedder_lifecycle import shutdown as life_shutdown
    life_shutdown()

if __name__ == "__main__":
    asyncio.run(main())
