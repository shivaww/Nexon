"""3-agent (planner -> researcher -> writer) Deep Research for the TermuxForge bridge."""

from .orchestrator import DeepResearchOrchestrator
from .cleaner import TextCleaner
from .schemas import FactRecord, FindingRecord, PhaseRecord, RunCheckpoint

__all__ = [
    "DeepResearchOrchestrator",
    "TextCleaner",
    "FactRecord",
    "FindingRecord",
    "PhaseRecord",
    "RunCheckpoint",
]
