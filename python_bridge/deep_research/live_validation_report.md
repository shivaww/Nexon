# End-to-End Live Validation Report

## Raw Results Table

| Query # | Query | Chunks Returned | Previews | Iterations | Escalated | Latency (s) | RAM Start / End (MB) |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | What is the critical temperature of YBCO? | 6 | Document: https://physics.test/high_temp_superconductors | Section: Section 1
Content: [Section: Sec... | Document: https://physics.test/superconductivity_basics | Section: Section 1
Content: [Section: Sect... | Document: https://physics.test/pnictides_cuprates_noisy | Section: Section 1
Content: [Section: Sect... | 1 | False | 0.152 | 46.5 / 49.4 |
| 2 | Compare the critical temperatures and discovery details of mercury and YBCO superconductivity. | 3 | Document: https://physics.test/high_temp_superconductors | Section: Section 1
Content: [Section: Sec... | Document: https://physics.test/pnictides_cuprates_noisy | Section: Section 1
Content: [Section: Sect... | Document: https://physics.test/mercury_history | Section: Section 1
Content: [Section: Section 1] In... | 1 | False | 0.119 | 49.4 / 49.8 |
| 3 | How do they cool Josephson junctions? | 5 | Document: https://quantum.test/superconducting_qubits | Section: Section 1
Content: [Section: Sectio... | Document: https://quantum.test/dilution_refrigerators | Section: Section 1
Content: [Section: Sectio... | Document: https://physics.test/josephson_junctions | Section: Section 1
Content: [Section: Section 1... | 2 | False | 0.206 | 49.8 / 50.3 |
| 4 | Who won the Nobel Prize in Physics in 2023 and what was it for? | 6 | Document: https://physics.test/high_temp_superconductors | Section: Section 1
Content: [Section: Sec... | Document: https://physics.test/josephson_junctions | Section: Section 1
Content: [Section: Section 1... | Document: https://physics.test/mercury_history | Section: Section 1
Content: [Section: Section 1] In... | 3 | False | 0.397 | 50.3 / 49.3 |
| 5 | What is the phenomenon where Cooper pairs traverse an insulating junction? | 6 | Document: https://physics.test/josephson_junctions | Section: Section 1
Content: [Section: Section 1... | Document: https://physics.test/superconductivity_basics | Section: Section 1
Content: [Section: Sect... | Document: https://quantum.test/superconducting_qubits | Section: Section 1
Content: [Section: Sectio... | 1 | False | 0.115 | 49.3 / 49.6 |

## System Performance
- **Ingestion Latency**: 20.45s
- **Ingestion RAM Start / Peak**: 50.7 MB / 22.4 MB
- **Embedding Server PID**: 23166 (reused successfully across all stages)