### 06 — Documentation finalization and migration notes

Outcome:
- Public docs accurately reflect the SDK’s V1 API, behaviors, and configuration. Migration notes clearly state what changed from POC → V1.

Scope:
- Reconcile `README.md` and `docs/API.md` with the current codebase and upcoming Native Speech additions.
- Remove duplicated and inconsistent sections in `docs/API.md`.
- Add a short migration guide describing breaking or notable changes.

Acceptance criteria:
- `docs/API.md` lists all public types and methods once, with accurate signatures and descriptions.
- `README.md` usage and configuration examples compile against the current API.
- Dictation callbacks and commit/cancel semantics are documented.
- Storage path and export behavior are documented (Application Support, backup exclusion, WAV support).

Implementation steps:
1) API reference cleanup
   - Deduplicate repeated callback listings in `docs/API.md` (e.g., `onFrame`, `onVADStateChange`, `onChunkSent`, `onError` appear twice).
   - Ensure `AudioCaptureConfig` options match the code:
     - Present fields: `sampleRate`, `channels`, `vadSensitivity`, `noiseSuppressionLevel`, `chunkDurationMs`, `enableHardwareEncode`, `bluetoothPreferred`, `enableAGC`, `highPassFilterCutoff`, `frameDurationMs`, `persistRawAudio`, `inputRoutePolicy`.
     - Remove/annotate any options that don’t exist or differ in naming.
   - Add dictation entries:
     - Callbacks: `onPartialTranscript`, `onFinalTranscript`.
     - Methods: `commitCurrentBlock()` and (if added) `cancelCurrentBlock()`.
   - Note threading: callbacks may arrive off the main thread.

2) README alignment
   - Update “Basic Usage” to reflect current `AudioCaptureConfig` initializer and defaults.
   - Clarify V1 recommendation: Apple Speech for ASR; BYO streaming as V2 optional.
   - Add a short snippet demonstrating commit/cancel with `VoiceDictationView`.

3) Storage and export docs
   - Document Application Support storage path with backup exclusion and (iOS) file protection.
   - Document export behavior and supported formats (`.wav` supported, `.m4a` not yet).

4) Migration notes (POC → V1)
   - Sample checklist:
     - Storage path moved from Documents → Application Support; files may relocate.
     - BYO streaming: prefer binary WebSocket frames in V2; current basic implementation uses JSON + base64 as a placeholder.
     - Dictation flow added with commit/cancel semantics and partial/final callbacks.
     - Interruption handling added; apps should observe `onError(.deviceInterrupted)` and allow automatic resume.

5) Cross-linking
   - From `docs/swift_dictation_plan.md` “Remaining work,” link to the chunk docs under `docs/tasks/`.
   - From `README.md`, link to `docs/API.md` and the example app.

Review checklist:
- All Swift snippets compile.
- No duplicate sections remain in API docs.
- Terminology (PCM16, VAD, chunking) consistent across README/API.

Definition of Done:
- Docs are current, consistent, and minimal yet complete for V1 consumers.
- A concise migration section exists and is linked from the README.


