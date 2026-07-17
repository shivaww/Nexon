"""Unit tests for agentic_loop.py wrapper layer."""

from __future__ import annotations

import asyncio
from unittest.mock import MagicMock, patch

from .agentic_loop import agentic_retrieve


def test_ram_threshold_degradation() -> None:
    """Verify that when RAM headroom is below threshold, reflection is skipped entirely."""
    print("\n--- Running RAM Threshold Degradation Test ---")
    mock_chunks = [{"text": "Found relevant document chunk.", "source": "ex.test"}]

    # Mock retrieve function
    mock_retrieve = MagicMock(return_value=mock_chunks)

    # Set virtual memory available to less than 300MB (e.g. 100MB)
    with patch("psutil.virtual_memory") as mock_mem:
        mock_mem.return_value.available = 100 * 1024 * 1024  # 100MB

        # Call agentic_retrieve
        loop = asyncio.new_event_loop()
        res = loop.run_until_complete(agentic_retrieve(
            "test query",
            existing_retrieve_fn=mock_retrieve
        ))
        loop.close()

        # Verify result
        assert res["chunks"] == mock_chunks
        assert res["iterations_used"] == 1
        assert res["escalated"] is False

        # Verify that retrieve was called, but no LLM was used (because of RAM headroom bypass)
        mock_retrieve.assert_called_once_with("test query")
        print("PASS: Gracefully degraded when RAM headroom was low.")


def test_llm_failure_degradation() -> None:
    """Verify that when local LLM fails or times out, the retrieve loop fails open and returns chunks."""
    print("\n--- Running LLM Failure/Timeout Degradation Test ---")
    mock_chunks = [{"text": "Some evidence.", "source": "ex.test"}]
    mock_retrieve = MagicMock(return_value=mock_chunks)

    # Mock LLM call to return None (failure or timeout)
    with patch("psutil.virtual_memory") as mock_mem, \
         patch("deep_research.rag.agentic_loop.REFLECTION_LLM_ENDPOINT", "http://reflection.test/completion"), \
         patch("requests.post", side_effect=Exception("Timeout")):
        mock_mem.return_value.available = 1024 * 1024 * 1024  # 1GB (plenty of RAM)

        loop = asyncio.new_event_loop()
        res = loop.run_until_complete(agentic_retrieve(
            "test query",
            existing_retrieve_fn=mock_retrieve
        ))
        loop.close()

        # Verify result is still returned successfully
        assert res["chunks"] == mock_chunks
        assert res["iterations_used"] == 1
        assert res["escalated"] is False
        print("PASS: Gracefully degraded (failed open) when local LLM failed.")


def test_query_reformulation() -> None:
    """Verify that query reformulation is triggered when LLM requests it."""
    print("\n--- Running Query Reformulation Test ---")
    mock_chunks = [{"text": "Some evidence.", "source": "ex.test"}]
    mock_retrieve = MagicMock(return_value=mock_chunks)

    # Mock LLM responses:
    # First reflect: reformulate with new query "better query"
    # Second reflect: sufficient
    mock_responses = [
        # First reflection response
        '{"decision": "reformulate", "new_query": "better query"}',
        # Second reflection response
        '{"decision": "sufficient", "new_query": null}'
    ]
    response_idx = 0

    def mock_llm_post(*args, **kwargs):
        nonlocal response_idx
        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_resp.json.return_value = {"content": mock_responses[response_idx]}
        response_idx += 1
        return mock_resp

    with patch("psutil.virtual_memory") as mock_mem, \
         patch("deep_research.rag.agentic_loop.REFLECTION_LLM_ENDPOINT", "http://reflection.test/completion"), \
         patch("requests.post", side_effect=mock_llm_post):
        mock_mem.return_value.available = 1024 * 1024 * 1024

        loop = asyncio.new_event_loop()
        res = loop.run_until_complete(agentic_retrieve(
            "initial query",
            existing_retrieve_fn=mock_retrieve
        ))
        loop.close()

        # Verify that retrieve was called with both queries
        assert mock_retrieve.call_count == 2
        mock_retrieve.assert_any_call("initial query")
        mock_retrieve.assert_any_call("better query")

        assert res["chunks"] == mock_chunks
        assert res["iterations_used"] == 2
        print("PASS: Query reformulation correctly parsed and re-executed.")


def test_broader_search_escalation() -> None:
    """Verify that broader search escalation triggers web search and ingestion."""
    print("\n--- Running Broader Search Escalation Test ---")
    mock_chunks = [{"text": "Initial evidence.", "source": "ex.test"}]
    escalated_chunks = [{"text": "Escalated evidence.", "source": "tavily.com"}]

    mock_retrieve = MagicMock(side_effect=[mock_chunks, escalated_chunks])
    mock_ingest = MagicMock()
    mock_search = MagicMock(return_value=[{"url": "tavily.com", "text": "Escalated evidence."}])

    # Reflect response: broader_search
    reflect_response = '{"decision": "broader_search", "new_query": null}'

    def mock_llm_post(*args, **kwargs):
        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_resp.json.return_value = {"content": reflect_response}
        return mock_resp

    with patch("psutil.virtual_memory") as mock_mem, \
         patch("deep_research.rag.agentic_loop.REFLECTION_LLM_ENDPOINT", "http://reflection.test/completion"), \
         patch("requests.post", side_effect=mock_llm_post):
        mock_mem.return_value.available = 1024 * 1024 * 1024

        loop = asyncio.new_event_loop()
        res = loop.run_until_complete(agentic_retrieve(
            "missing topic query",
            existing_retrieve_fn=mock_retrieve,
            existing_ingest_fn=mock_ingest,
            tavily_search_fn=mock_search
        ))
        loop.close()

        # Verify that Tavily search was called
        mock_search.assert_called_once_with("missing topic query")

        # Verify that ingestion was called with web results
        mock_ingest.assert_called_once_with([{"url": "tavily.com", "text": "Escalated evidence."}])

        # Verify that retrieval was re-executed and returned the escalated chunks
        assert res["chunks"] == escalated_chunks
        assert res["escalated"] is True
        print("PASS: Broader search escalation successfully queried web and ingested content.")


if __name__ == "__main__":
    test_ram_threshold_degradation()
    test_llm_failure_degradation()
    test_query_reformulation()
    test_broader_search_escalation()
    print("\nAll Agentic Loop tests passed successfully.")
