# Swift Dictation SDK — Plan (iOS‑first)

## Goal

Reusable, production-grade Swift module that delivers ultra-faithful per‑word dictation on iOS with minimal moving parts. V1 targets iOS only for speed and simplicity; macOS support may be added later if it’s low-effort.

## High-level architecture
- Capture Layer (iOS)
  - AVAudioEngine + AVAudioSession for low‑latency PCM capture and device routing. iOS‑first; macOS is a stretch goal.
- Preprocessing Layer (native, lightweight)
  - Energy‑based VAD, optional high‑pass filter and AGC. No RNNoise/WebRTC dependencies in V1.
- ASR Mode (choose one per app session)
  - Native Speech (default, simplest): iOS Speech framework (SFSpeechRecognizer) for live or post‑capture transcription.
  - BYO Streaming (optional, V2): pluggable WebSocket streaming to a provider (Deepgram/AssemblyAI/etc.).
- Encoding / Transport Layer (only for BYO Streaming)
  - Raw PCM frames over binary WebSocket; segment‑level ACKs for resumability (no gRPC in V1).
- SDK Surface
  - Synchronous & evented APIs; callbacks or AsyncSequence for frames/VAD/transcript updates; robust error/resume handling.
- Packaging
  - Swift Package Manager in V1. Consider XCFramework/CocoaPods later if needed.

## Minimal public API (example)

```swift
// Simplified example signatures
public class AudioCaptureSDK {
    public init(config: AudioCaptureConfig)
    public func requestPermissions() async throws -> PermissionStatus
    public func startCapture(mode: CaptureMode) throws
    public func pauseCapture() throws
    public func resumeCapture() throws
    public func stopCapture() throws
    // BYO Streaming (optional, V2)
    public func startStream(to target: StreamTarget) throws
    public func stopStream() throws
    public func exportRecording(format: AudioFormat, destination: URL) async throws -> ExportResult

    // Event callbacks
    public var onFrame: ((AudioFrame) -> Void)?
    public var onVADStateChange: ((VADState) -> Void)?
    public var onChunkSent: ((ChunkMetadata) -> Void)?
    public var onError: ((Error) -> Void)?

    // Dictation convenience (V1, Native Speech)
    public var onPartialTranscript: ((String) -> Void)?
    public var onFinalTranscript: ((String) -> Void)?
}
```

Config knobs:
- sampleRate, channels, vadSensitivity, highPassFilterCutoff, enableAGC
- frameDurationMs (20|40|60) for streaming frames (BYO mode)
- persistRawAudio (default false)
- inputRoutePolicy (e.g., builtInMicPreferred | bluetoothAllowed)

## Data formats & defaults
- Capture: 16‑bit PCM, mono. Default 16 kHz for BYO providers; Apple Speech can run at device/native rates internally.
- Framing (BYO Streaming): 20–60 ms frames for low latency; group frames into 0.5–1.0 s “segments” for ACK/resume bookkeeping.
- Metadata (BYO Streaming): sequenceId, startSampleIndex, endSampleIndex, sampleRate, deviceId, micPosition, confidence hints (optional).

## Preprocessing choices
- Keep it simple in V1: high‑pass filter → AGC → energy‑based VAD. Avoid heavy native deps.
- Surface VAD events to UI for "is speaking" indicator and autosave/trimming.
- Persist raw audio is opt‑in (default off). When enabled, store under Application Support with file protection and excluded from backups.

## Streaming & server integration
- V1 (default): Native Speech via SFSpeechRecognizer — no external server required. Supports partial and final transcripts.
- V2 (optional): BYO provider via secure WebSocket (TLS) with binary PCM frames and lightweight segment ACKs for resumability.
- Backend options (BYO): Deepgram or AssemblyAI recommended for ease of integration and word‑level timestamps. Keep interface pluggable.
- Auth (BYO): use a tiny token proxy to mint short‑lived provider tokens; the app connects directly to the provider WebSocket with binary audio frames.

## UX hooks (for high polish)
- Live incremental transcript with per-word confidence highlighting.
- Low-confidence word chips for one-tap correction and contextual suggestions.
- Waveform with scrub + VAD overlay; real-time waveform preview during recording.
- Background recording behaviors and persistent permission UI.
- Quick-record widget and accessible keyboard shortcuts on macOS.

## Voice Dictation — V1 UI/UX Requirements

- **Purpose**
  - Provide an inline dictation experience attached to a text input where users can record, pause/resume, and commit spoken text in blocks that are appended to the input.

- **Primary user flows**
  - **Start recording**: Tap the mic to begin; UI shows live waveform, timer, cancel, and confirm controls.
  - **Pause / Resume recording**: Stop (pause) and later resume; resumed audio appends to the current block so a single message is built in blocks.
  - **Commit / Process**: Tap the checkmark to finalize the block and send audio for processing; show a spinner while processing and append the resulting transcript to the input on success.
  - **Cancel**: Discard the current uncommitted audio segment and return to idle.

- **Visual / control layout**
  - Idle: a large circular mic button aligned to the input.
  - Listening: horizontal control row with cancel (left), realistic animated waveform (middle), timer + check/processing (right).
  - Waveform: smooth, responsive animation that visually reflects speaking amplitude; reserve stable layout space when controller absent.

- **State model (user-facing)**
  - Idle, Listening (recording), Paused (soft stop before commit), Processing (spinner), Error/Interrupted.

- **Behaviors & expectations**
  - Appending text: processed transcripts for committed blocks append to existing input (not replace).
  - Pause semantics: stopping is a soft pause; confirm finishes the block and triggers transcription.
  - Cancel semantics: discards only the current uncommitted audio.
  - Processing feedback: disable conflicting controls while processing; show clear success/failure states.

- **Edge cases & constraints**
  - Handle permission loss and device interruptions with clear errors and retry options.
  - Warn or cap very long recordings; debounce rapid toggles to avoid race conditions.
  - Offline: queue committed blocks for retry or show offline warning.

- **Priorities for V1**
  - High: start/stop/resume append behavior; live waveform; cancel and confirm; timer and spinner; accessibility targets/labels.
  - Medium: interrupted device handling; graceful waveform fallback.
  - Low: per-block trimming, advanced editing, noise gating.

- **Acceptance criteria**
  - Mic tap starts recording with live waveform and timer.
  - Pause/resume constructs a single appended block.
  - Cancel discards uncommitted audio.
  - Checkmark finalizes block, shows spinner, then appends final text.
  - Controls disabled during processing; spinner visible.

## Packaging & reuse
- V1: Publish via Swift Package Manager (SPM). Provide a SwiftUI sample app.
- Later: Consider `XCFramework` and CocoaPods if integrators require them.
- If macOS proves low‑effort, add a slice behind a separate target.

## Testing & QA
- Unit tests: VAD thresholds, frame alignment, sample-rate conversion.
- Integration tests:
  - Native Speech: capture → transcript happy path and interruptions.
  - BYO Streaming: capture → frames → provider mock with binary frames + ACKs.
- Field tests: iPhone device matrix, noisy environments; validate Bluetooth routing behavior and accuracy trade‑offs.

## Implementation status (implementation checklist)
Below is the current implementation state and a checklist of remaining work (checked = done).

- [x] Finalize initial API surface and error model (see `docs/API.md`).
- [x] Prototype AVAudioEngine capture with energy‑based VAD and basic preprocessing.
- [x] SwiftUI sample app demonstrating the V1 dictation UI.

### Remaining work

- [ ] V1 Native Speech: add `onPartialTranscript`/`onFinalTranscript` and dictation convenience wrapper.
- [ ] Background/interruption handling and permission recovery on iOS.
- [ ] Opt‑in raw audio persistence with secure storage; export utilities.
- [ ] Metrics/telemetry: capture→emit latency, buffer underruns, CPU usage.
- [ ] Unit/integration tests per above; device matrix QA (built‑in vs Bluetooth).
- [ ] Documentation: finalize API docs and migration notes from POC to V1.
- [ ] V2 (optional): BYO Streaming transport with binary WebSocket frames and segment ACKs; provider adapter (Deepgram or AssemblyAI); lightweight token proxy.

Notes:
- The repository currently contains a functioning SDK core: AVAudioEngine capture, basic preprocessing (AGC, high‑pass), energy‑based VAD, chunking, optional WebSocket streaming (kept for BYO mode), local storage, and a SwiftUI example app demonstrating the V1 dictation UI.
- `docs/API.md` contains the public API reference; the Native Speech dictation convenience will be added alongside the existing surface.

---

_Created for the StoryBuild / AuthorityFlow project. This document prioritizes the simplest path to a great iOS dictation MVP, with optional streaming added later._  


