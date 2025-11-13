### 05 — Unit/integration tests and device QA

Outcome:
- A baseline automated test suite covers critical logic (VAD, chunking, export, lifecycle). Manual QA checklists validate behavior across devices and routes (built‑in vs Bluetooth).

Scope:
- Add/expand tests under `Tests/SwiftDictationTests/`.
- Provide fixtures and simple fakes for speech and streaming.
- Document a manual QA matrix for on-device testing.

Acceptance criteria:
- Unit tests cover: VAD thresholds, chunk boundaries, sample-rate conversion correctness, WAV header validity, lifecycle guard rails (start/pause/resume/stop errors).
- Integration tests validate: capture start→frame callbacks, chunk emission cadence, export happy path, and (with a fake speech layer) partial/final transcript callback sequencing.
- A manual QA checklist exists and is followed at least once across 2–3 iPhone models.

Key files:
- `Tests/SwiftDictationTests/AudioCaptureSDKTests.swift`
- New test helpers where needed under `Tests/SwiftDictationTests/`

Implementation steps:
1) Fixtures
   - Add small PCM16 buffers (synthetic sine wave) for deterministic tests.
   - Utility to generate N ms of PCM16 at given `sampleRate` and amplitude.

2) VAD tests
   - Feed low-energy buffers → expect `silence`.
   - Feed higher-energy buffers → expect `speech`.
   - Toggle `vadSensitivity` and verify threshold shifts.

3) Chunking tests
   - Configure `chunkDurationMs = 1000`.
   - Feed exactly 1s of samples → expect 1 chunk with correct `startTimestamp/endTimestamp` and `sequenceId = 0`.
   - Feed 2.5s → expect 2 full chunks + 1 partial on `flush()`.

4) Export tests
   - Build a short buffer; call `exportAsWAV`; validate header fields and data size.
   - Empty buffer export should throw a typed error.

5) Lifecycle tests
   - `pauseCapture` without `startCapture` → throws.
   - `resumeCapture` when not paused → throws.
   - `startCapture` twice → throws.

6) Integration (no Apple services)
   - Create a fake speech recognizer that echoes fixed partial/final strings.
   - Validate `onPartialTranscript` fires before `onFinalTranscript` after calling commit.

7) Manual QA matrix
   - Devices: at least two iPhone models (e.g., iPhone 12, iPhone 15).
   - Routes: built‑in mic, wired headset (if available), Bluetooth (AirPods).
   - Scenarios:
     - Start/pause/resume/commit/cancel sequences.
     - Interruption (incoming call) and route changes (plug/unplug, BT handoff).
     - Long session (≥10 minutes) to observe stability and memory.

Testing notes:
- Keep audio thread work minimal in tests; prefer feeding synthetic buffers directly into `AudioChunker` and VAD for determinism.
- Gate speech-dependent tests behind fakes/mocks to avoid flakiness in CI.

Definition of Done:
- Tests are green locally and in CI.
- QA checklist items are recorded with pass/fail notes for at least 2 devices.


