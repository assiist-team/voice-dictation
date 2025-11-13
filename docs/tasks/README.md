### SwiftDictation — Work Chunks (Junior‑friendly task breakdown)

This folder contains self‑contained task docs that chunk the remaining work for V1 (and an optional V2 streaming track). Each doc is actionable, with scope, acceptance criteria, steps, and testing guidance.

Start from 01 and proceed in order unless you’re unblocked on a parallel item.

- 01 — Native Speech dictation convenience and callbacks  
  See: `01-native-speech-dictation.md`
- 02 — Interruptions and permission recovery on iOS  
  See: `02-interruptions-permissions.md`
- 03 — Raw audio persistence and export utilities  
  See: `03-persistence-export.md`
- 04 — Metrics and telemetry (capture→emit latency, underruns, CPU)  
  See: `04-metrics-telemetry.md`
- 05 — Unit/integration tests and device QA  
  See: `05-testing-qa.md`
- 06 — Documentation finalization and migration notes  
  See: `06-docs-finalization.md`
- 07 — BYO Streaming V2 (optional) adapter + token proxy spec  
  See: `07-byo-streaming-v2.md`

Conventions:
- Prefer clear names and concise code over cleverness.
- Write tests alongside changes when feasible.
- Keep public API changes reflected in `docs/API.md` in the same PR.


