import asyncio

import pytest

from deep_research.orchestrator import DeepResearchOrchestrator
from deep_research.schemas import IngestResult


class FakeLightRAG:
    def __init__(self) -> None:
        self.active = 0
        self.peak = 0
        self.calls: list[tuple[str, str, str, str]] = []

    async def ingest(self, stage_id: str, query_id: str, source_url: str, text: str) -> IngestResult:
        self.active += 1
        self.peak = max(self.peak, self.active)
        self.calls.append((stage_id, query_id, source_url, text))
        await asyncio.sleep(0.02)
        self.active -= 1
        return IngestResult(new_chunks_added=1, novelty_ratio=1.0, total_chunks_stage=1)


@pytest.mark.asyncio
async def test_parallel_ingests_are_serialized_and_keep_payloads(tmp_path, monkeypatch) -> None:
    monkeypatch.setenv("DR_INGEST_CONCURRENCY", "1")
    orchestrator = DeepResearchOrchestrator(data_dir=tmp_path)
    fake = FakeLightRAG()
    orchestrator.lightrag = fake
    payloads = [
        ("stage_parallel", f"query_{index}", f"https://example.test/{index}", f"text {index}")
        for index in range(5)
    ]

    results = await asyncio.gather(
        *(orchestrator.ingest(*payload) for payload in payloads)
    )

    assert fake.peak == 1
    assert set(fake.calls) == set(payloads)
    assert all(result["new_chunks_added"] == 1 for result in results)


@pytest.mark.asyncio
async def test_ingest_rejects_missing_payload_fields(tmp_path) -> None:
    orchestrator = DeepResearchOrchestrator(data_dir=tmp_path)

    with pytest.raises(ValueError, match="stage_id, query_id, source_url, and text are required"):
        await orchestrator.ingest("stage", "", "https://example.test", "text")
