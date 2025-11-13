### 01 — Native Speech dictation convenience and callbacks

Outcome:
- Users get live partial transcripts while recording and a final transcript upon commit. The SDK exposes `onPartialTranscript` and `onFinalTranscript` callbacks and a simple block-based dictation flow compatible with the V1 UI.

Scope:
- Wire Apple’s Speech framework (`SFSpeechRecognizer`) into the existing capture path.
- Emit partial and final text through the existing public callbacks.
- Provide a minimal public method to finalize the current block (commit) and cancel behavior to discard uncommitted audio.
- Update the SwiftUI example to demonstrate pause/resume, commit, and cancel semantics.

Acceptance criteria:
- Starting capture produces partial transcripts while speaking.
- Calling commit finalizes the current block and emits a final transcript via `onFinalTranscript`.
- Cancel discards the current block and emits no final transcript.
- Pause/resume continues the same block until commit.
- No double taps on the engine; recognition request/task lifecycle is correctly managed.

Key files:
- `Sources/SwiftDictation/AudioCaptureSDK.swift`
- `Sources/SwiftDictation/AudioCaptureEngine.swift` (tap already installed)
- Add new helper: `Sources/SwiftDictation/NativeSpeechRecognizer.swift`
- `Examples/iOS/VoiceDictationView.swift`

Public API additions:
- Add one method to `AudioCaptureSDK`:
  - `public func commitCurrentBlock() throws`
    - Finalizes the current recognition request and emits `onFinalTranscript`.
- Optional (nice-to-have): `public func cancelCurrentBlock() throws` to discard current block.
  - If not added as public, ensure the example can invoke an equivalent behavior.

Implementation steps:
1) Create `NativeSpeechRecognizer`
   - Responsibilities:
     - Manage `SFSpeechRecognizer`, `SFSpeechAudioBufferRecognitionRequest`, and `SFSpeechRecognitionTask`.
     - Provide `startBlock()`, `append(_ buffer: AVAudioPCMBuffer)`, `commitBlock()`, `cancelBlock()`.
     - Expose closures: `onPartial: (String) -> Void`, `onFinal: (String) -> Void`, `onError: (Error) -> Void`.
   - Configure request:
     - `requiresOnDeviceRecognition` best-effort; set if available and appropriate.
     - `shouldReportPartialResults = true`.
   - On task handler:
     - When `result.isFinal == false`: call `onPartial`.
     - When final: call `onFinal` with the best transcription and finish.

2) Integrate with `AudioCaptureSDK`
   - Hold an instance `private var speech: NativeSpeechRecognizer?`.
   - On `startCapture`, create/prepare `speech` and call `startBlock()`.
   - In `handleAudioBuffer`, after preprocessing, append the buffer to `speech.append(buffer)` (only when a dictation block is active).
   - Bridge closures to public SDK callbacks:
     - `speech.onPartial = { [weak self] text in self?.onPartialTranscript?(text) }`
     - `speech.onFinal = { [weak self] text in self?.onFinalTranscript?(text) }`
     - `speech.onError = { [weak self] error in self?.onError?(error) }`

3) Implement commit and cancel
   - `commitCurrentBlock()` calls `speech.commitBlock()`; then immediately `speech.startBlock()` to be ready for the next block if capture continues.
   - `cancelCurrentBlock()` calls `speech.cancelBlock()`; then `speech.startBlock()` if capture continues.
   - Ensure these calls are legal in both paused and active states. If paused, resume logic remains separate (`resumeCapture()`).

4) Permissions
   - Extend `requestPermissions()` to also request `SFSpeechRecognizer` authorization on iOS:
     - Call `SFSpeechRecognizer.requestAuthorization` and map to `PermissionStatus`.
   - Keep microphone permission flow unchanged.

5) Example app update
   - `VoiceDictationView.swift`:
     - Start/pause/resume wire to SDK methods.
     - “Check/Commit” button invokes `commitCurrentBlock()`.
     - “Cancel” button invokes `cancelCurrentBlock()` (or equivalent).
     - Show live transcript using `onPartialTranscript`, then append final on `onFinalTranscript`.

Testing guide:
- Manual:
  - Speak a sentence; observe partial updates then press “Commit”; final text appears once and partials reset.
  - Press “Cancel” after speaking; no final text is appended.
  - Pause/resume mid-sentence; partials continue; commit still yields a single final output.
- Integration:
  - Inject a fake `NativeSpeechRecognizer` in tests to validate callback sequencing without hitting Apple APIs.
- Performance:
  - Verify no extra allocations or concurrent taps; no memory growth when repeatedly committing blocks.

Gotchas:
- `SFSpeechRecognizer` callbacks may not be on the main thread; dispatch UI updates accordingly.
- Avoid multiple `SFSpeechRecognitionTask` instances for the same block; cancel before starting a new one.
- If the audio engine restarts, ensure the recognition request is also recreated.

Definition of Done:
- Public callbacks produce live partial and final transcripts.
- Example app demonstrates the full V1 flow (start/pause/resume/commit/cancel).
- No crashes or leaked tasks on repeated commits or cancels.


