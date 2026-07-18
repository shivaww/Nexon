# Deep Research — Test Layout

Regression and validation tests for the Hierarchical RAG deep-research pipeline.

## How to run

Run from the repository root (`termux_forge/`) so that `python_bridge` is
importable as a package.

```bash
# RAG-layer unit tests (use package-relative imports; run as modules)
python3 -m python_bridge.deep_research.rag.test_lifecycle
python3 -m python_bridge.deep_research.rag.test_agentic_loop
python3 -m python_bridge.deep_research.rag.test_regression
python3 -m python_bridge.deep_research.rag.test_numpy_storage

# Top-level validation / smoke tests (self-contained via sys.path setup)
python3 python_bridge/deep_research/tests/test_smoke.py
python3 python_bridge/deep_research/tests/test_lightrag_rag.py
python3 python_bridge/deep_research/tests/test_robust_pdf.py
python3 python_bridge/deep_research/tests/test_circuit_breakers.py
python3 python_bridge/deep_research/tests/test_live_validation.py
python3 python_bridge/deep_research/tests/evaluator.py

# Flutter / Dart test
flutter test test/circuit_breakers_test.dart
```

## What each covers

| Test | Covers |
|------|--------|
| `rag/test_lifecycle.py` | `ServerLifecycleManager` concurrent-spawn safety and SIGKILL recovery |
| `rag/test_agentic_loop.py` | `agentic_loop` wrapper: RAM threshold, reformulate, broader-search escalation |
| `rag/test_regression.py` | embedder does not hang on sequential requests (request 2+) |
| `rag/test_numpy_storage.py` | plain sqlite3 BLOB + numpy cosine storage engine and migration compatibility |
| `tests/test_smoke.py` | dependency-free `DeepResearchOrchestrator` smoke test |
| `tests/test_lightrag_rag.py` | 5-behavior Hierarchical RAG plan: factual / section / multi-doc / re-ingest / weak-evidence |
| `tests/test_robust_pdf.py` | image-only / scanned PDF robustness via the bridge |
| `tests/test_circuit_breakers.py` | asserts circuit-breaker fixes present in `lib/main.dart` |
| `tests/test_live_validation.py` | end-to-end live pipeline validation |
| `tests/evaluator.py` | automated evaluation / regression harness |
| `test/circuit_breakers_test.dart` | Flutter circuit-breaker logic (normalize + malformed-tag detection) |
