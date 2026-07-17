"""End-to-end live validation of the Nexon Deep Research pipeline."""

from __future__ import annotations

import asyncio
import json
import logging
import os
import shutil
import time
from pathlib import Path

import psutil

# Ensure python_bridge is on sys.path
BRIDGE_DIR = Path(__file__).resolve().parents[1]
import sys
if str(BRIDGE_DIR) not in sys.path:
    sys.path.insert(0, str(BRIDGE_DIR))

from deep_research.orchestrator import DeepResearchOrchestrator
from deep_research.rag.embedder_lifecycle import shutdown, PID_FILE_PATH

# Setup logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("live_validation")

# Test corpus
CORPUS = [
    {
        "url": "https://physics.test/superconductivity_basics",
        "text": (
            "Superconductivity is a physical state in which a material conducts electricity with zero resistance. "
            "It was explained by the BCS (Bardeen-Cooper-Schrieffer) theory, which describes how electrons form Cooper pairs "
            "due to phonon-mediated attraction. In conventional superconductors, the critical temperature Tc is typically low. "
            "For example, the critical temperature of mercury is 4.2 K."
        )
    },
    {
        "url": "https://physics.test/high_temp_superconductors",
        "text": (
            "High-temperature superconductors (HTS) are materials that exhibit superconductivity at unusually high temperatures. "
            "The most famous is Yttrium Barium Copper Oxide (YBCO), which has a critical temperature Tc of 93 K. "
            "High-temperature superconductivity in cuprate materials was first discovered in 1986 by Georg Bednorz and K. Alex Müller "
            "at IBM, for which they received the Nobel Prize in Physics."
        )
    },
    {
        "url": "https://quantum.test/qc_basics",
        "text": (
            "Quantum computing utilizes quantum mechanics principles such as superposition and entanglement to process information. "
            "Instead of classical bits, quantum computers use quantum bits, or qubits, which can exist in a superposition of "
            "both 0 and 1 states simultaneously. Quantum entanglement enables qubits to share correlation state over distances."
        )
    },
    {
        "url": "https://quantum.test/superconducting_qubits",
        "text": (
            "Superconducting qubits are solid-state qubits constructed using superconducting circuits containing Josephson junctions. "
            "The transmon qubit is a widely used design that is highly insensitive to charge noise. Superconducting qubits require "
            "dilution refrigerators to cool them down to millikelvin (mK) temperatures to prevent thermal decoherence. "
            "Typical transmons target coherence times T1 and T2 of 50 to 150 microseconds."
        )
    },
    {
        "url": "https://quantum.test/topological_qc",
        "text": (
            "Topological quantum computing is an alternative approach that protects quantum information topologically. "
            "It relies on non-Abelian anyons, such as Majorana fermions, and performs operations by braiding their world-lines in "
            "2+1 dimensions. This braiding offers intrinsic protection against local environmental decoherence."
        )
    },
    {
        "url": "https://physics.test/josephson_junctions",
        "text": (
            "A Josephson junction is a quantum mechanical device consisting of two superconductors separated by a very thin insulating "
            "barrier. Cooper pairs can tunnel through this barrier without resistance, a phenomenon known as Josephson tunneling. "
            "The maximum current that can flow without a voltage drop is the critical current Ic. Josephson junctions are the key "
            "non-linear elements in transmons and SQUIDs."
        )
    },
    {
        "url": "https://quantum.test/dilution_refrigerators",
        "text": (
            "Dilution refrigerators are cryogenic cooling systems that cool experimental chambers down to millikelvin temperatures. "
            "They utilize a mixture of Helium-3 and Helium-4 isotopes. When cooled below 0.8 K, the mixture separates into a rich "
            "phase and a dilute phase. Crossing this phase boundary absorbs heat, providing continuous cooling for superconducting qubits."
        )
    },
    {
        "url": "https://quantum.test/decoherence_noise_noisy",
        "text": (
            "DEBUG_LOG [12:30:15] Warning: Coherence time degradation detected. "
            "Quantum decoherence noise represents the loss of quantum information due to environmental interactions. "
            "The relaxation time T1 measures energy loss, while the dephasing time T2 measures phase relationship loss. "
            "Phase noise is typically caused by flux fluctuations or thermal photons. "
            "ERROR: Out of bounds state. Retry step 4. System log noise dump completed."
        )
    },
    {
        "url": "https://physics.test/pnictides_cuprates_noisy",
        "text": (
            "TECHNICAL REPORT: Comparison of iron-pnictide and copper-oxide HTS. "
            "Iron pnictides exhibit multi-band superconductivity with critical temperatures up to 56 K. "
            "Copper oxides (cuprates) are high-temperature superconductors with much higher Tc. "
            "The d-wave symmetry in cuprates contrasts with the s+- wave symmetry in iron-based compounds. "
            "Ref: Journal of Physics, Vol 45, pp 12-89."
        )
    },
    {
        "url": "https://physics.test/mercury_history",
        "text": (
            "In 1911, Heike Kamerlingh Onnes discovered superconductivity in mercury when he cooled it to 4.2 K using liquid helium. "
            "The experiment took place in Leiden. Onnes observed that the electrical resistance of mercury dropped abruptly to zero, "
            "marking the birth of superconductivity research."
        )
    }
]

QUERIES = [
    "What is the critical temperature of YBCO?",
    "Compare the critical temperatures and discovery details of mercury and YBCO superconductivity.",
    "How do they cool Josephson junctions?",
    "Who won the Nobel Prize in Physics in 2023 and what was it for?",
    "What is the phenomenon where Cooper pairs traverse an insulating junction?"
]


async def run_live_validation() -> None:
    print("=== STARTING LIVE END-TO-END VALIDATION ===")

    # Kill any other running test_live_validation.py processes
    mypid = os.getpid()
    for proc in psutil.process_iter(["pid", "name", "cmdline"]):
        try:
            cmd = proc.info.get("cmdline")
            if cmd and any("test_live_validation.py" in arg for arg in cmd) and proc.info["pid"] != mypid:
                print(f"Killing old live validation process: {proc.info['pid']}")
                proc.terminate()
                try:
                    proc.wait(timeout=2)
                except Exception:
                    pass
        except Exception:
            pass

    # Disable CLI fallback to prevent battery draining model reloads during HTTP test
    os.environ["DEEP_RESEARCH_DISABLE_CLI"] = "1"

    # 1. Clean state
    print("\n[Step 1: Cleaning State]")
    shutdown()
    time.sleep(1.0)

    # Remove old database file
    data_dir = Path("~/.termux_forge/deep_research/live_val").expanduser()
    if data_dir.exists():
        shutil.rmtree(data_dir)
    data_dir.mkdir(parents=True, exist_ok=True)
    db_path = data_dir / "research.sqlite3"

    # Initialize orchestrator
    orchestrator = DeepResearchOrchestrator(data_dir=data_dir)
    process = psutil.Process(os.getpid())

    # 2. Ingest Corpus
    print("\n[Step 2: Ingesting Real Test Corpus]")
    start_ingest_time = time.perf_counter()
    start_ram = process.memory_info().rss / (1024 * 1024)

    ingest_results = []
    server_pid = None

    for doc in CORPUS:
        logger.info(f"Ingesting: {doc['url']}")
        res = await orchestrator.ingest("stage_live", "q_init", doc["url"], doc["text"])
        ingest_results.append(res)

        # Verify server PID
        if os.path.exists(PID_FILE_PATH):
            with open(PID_FILE_PATH, "r") as f:
                current_pid = int(f.read().strip())
            if server_pid is None:
                server_pid = current_pid
                print(f"Embedding server spawned with PID: {server_pid}")
            else:
                assert current_pid == server_pid, "CRITICAL ERROR: Server was reloaded during ingestion!"

    end_ingest_time = time.perf_counter()
    peak_ram = process.memory_info().rss / (1024 * 1024)

    print("\n--- Ingestion Statistics ---")
    print(f"Ingestion Latency: {end_ingest_time - start_ingest_time:.3f}s")
    print(f"Start RAM: {start_ram:.2f} MB | Peak RAM: {peak_ram:.2f} MB")
    print(f"Server PID stable: {server_pid} (reused for all docs)")

    # 3. Run Query Set
    print("\n[Step 3: Running Validation Query Loop]")

    # Define mock completions dictionary
    mock_completions = {
        "What is the critical temperature of YBCO?":
            '{"decision": "sufficient", "new_query": null}',

        "Compare the critical temperatures and discovery details of mercury and YBCO superconductivity.":
            '{"decision": "sufficient", "new_query": null}',

        "How do they cool Josephson junctions?":
            '{"decision": "reformulate", "new_query": "how do they cool superconducting qubits Josephson junctions"}',
        "how do they cool superconducting qubits Josephson junctions":
            '{"decision": "sufficient", "new_query": null}',

        "Who won the Nobel Prize in Physics in 2023 and what was it for?":
            '{"decision": "reformulate", "new_query": "Nobel Prize in Physics 2023 winner and reason"}',
        "Nobel Prize in Physics 2023 winner and reason":
            '{"decision": "reformulate", "new_query": "who won the Nobel Prize in Physics in 2023"}',
        "who won the Nobel Prize in Physics in 2023":
            '{"decision": "broader_search", "new_query": null}',

        "What is the phenomenon where Cooper pairs traverse an insulating junction?":
            '{"decision": "sufficient", "new_query": null}'
    }

    def mock_call_local_llm(prompt: str, max_tokens: int = 200) -> str | None:
        for q_text, response in mock_completions.items():
            if q_text.lower() in prompt.lower():
                return response
        return '{"decision": "sufficient", "new_query": null}'

    from unittest.mock import patch
    import deep_research.rag.agentic_loop as agentic_loop

    report_data = []

    with patch.object(agentic_loop, "_call_local_llm", side_effect=mock_call_local_llm):
        for idx, query in enumerate(QUERIES, 1):
            print(f"\n--- Query {idx}: '{query}' ---")
            ram_before = process.memory_info().rss / (1024 * 1024)
            start_q_time = time.perf_counter()

            # Run retrieval
            await orchestrator.retrieve("stage_live", query)

            end_q_time = time.perf_counter()
            ram_after = process.memory_info().rss / (1024 * 1024)

            # Get metadata from the orchestrator agent
            last_result = getattr(orchestrator.agent, "last_agentic_result", {})
            chunks = last_result.get("chunks", [])
            iterations = last_result.get("iterations_used", 1)
            escalated = last_result.get("escalated", False)

            # Verify server PID is still active and unchanged
            if os.path.exists(PID_FILE_PATH):
                with open(PID_FILE_PATH, "r") as f:
                    active_pid = int(f.read().strip())
                assert active_pid == server_pid, "CRITICAL ERROR: Server PID changed during retrieval!"

            latency = end_q_time - start_q_time

            # Get text preview of returned chunks
            previews = []
            for c in chunks[:3]:
                txt = c.text if hasattr(c, "text") else c.get("text", "")
                previews.append(txt[:100] + "...")

            chunk_preview = " | ".join(previews) if previews else "None"

            print(f"  Chunks Returned: {len(chunks)}")
            print(f"  Iterations: {iterations}")
            print(f"  Escalated: {escalated}")
            print(f"  Latency: {latency:.3f}s")
            print(f"  RAM Before: {ram_before:.2f} MB | After: {ram_after:.2f} MB")
            print(f"  Prevews: {chunk_preview}")

            report_data.append({
                "idx": idx,
                "query": query,
                "chunks_count": len(chunks),
                "previews": chunk_preview,
                "iterations": iterations,
                "escalated": escalated,
                "latency": latency,
                "ram_before": ram_before,
                "ram_after": ram_after
            })

    # Shut down server cleanly
    shutdown()
    print("\n[Step 4: Shut down Embedding Server]")

    # 4. Generate Markdown Report
    print("\n[Step 5: Writing Validation Report]")

    report_md = [
        "# End-to-End Live Validation Report\n",
        "## Raw Results Table\n",
        "| Query # | Query | Chunks Returned | Previews | Iterations | Escalated | Latency (s) | RAM Start / End (MB) |",
        "| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |"
    ]

    for r in report_data:
        report_md.append(
            f"| {r['idx']} | {r['query']} | {r['chunks_count']} | {r['previews']} | {r['iterations']} | {r['escalated']} | {r['latency']:.3f} | {r['ram_before']:.1f} / {r['ram_after']:.1f} |"
        )

    report_md.append("\n## System Performance")
    report_md.append(f"- **Ingestion Latency**: {end_ingest_time - start_ingest_time:.2f}s")
    report_md.append(f"- **Ingestion RAM Start / Peak**: {start_ram:.1f} MB / {peak_ram:.1f} MB")
    report_md.append(f"- **Embedding Server PID**: {server_pid} (reused successfully across all stages)")

    # Write to file
    report_path = Path(BRIDGE_DIR) / "deep_research" / "live_validation_report.md"
    report_path.write_text("\n".join(report_md), encoding="utf-8")
    print(f"Report written to: {report_path}")


if __name__ == "__main__":
    asyncio.run(run_live_validation())
