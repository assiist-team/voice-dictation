# SwiftDictation — Public API Reference

This document describes the public API exposed by the `SwiftDictation` SDK, how to use it, and the meaning of key technical terms used by the SDK.

## Overview

`SwiftDictation` provides low-latency audio capture, lightweight preprocessing (VAD, AGC), optional chunked streaming, local persistence utilities, and dictation convenience helpers. V1 is iOS‑first and uses Apple's Speech framework as the default ASR path (no server required). Streaming to external providers is supported as an optional V2 feature.

## Quick start example

```swift
import SwiftDictation

let config = AudioCaptureConfig()
let sdk = AudioCaptureSDK(config: config)

// Request permissions
let status = try await sdk.requestPermissions()
guard status == .granted else { /* handle */ }

// Setup callbacks
sdk.onFrame = { frame in /* handle audio frame (PCM16) */ }
sdk.onVADStateChange = { state in /* UI feedback */ }
sdk.onChunkSent = { meta in /* streaming ack */ }
sdk.onError = { error in /* handle error */ }

// Start capture
try sdk.startCapture()

// Later: stop
try sdk.stopCapture()
```

## Public types

 - `AudioCaptureConfig`
   - Configuration knobs:
     - `sampleRate: Double` — capture sample rate in Hz (default 16000 for BYO streaming; device/native accepted for Apple Speech).
     - `channels: Int` — number of channels (default 1).
     - `vadSensitivity: Float` — 0.0–1.0 (higher = more sensitive).
     - `enableAGC: Bool` — automatic gain control (default true).
     - `highPassFilterCutoff: Double` — high-pass cutoff frequency (Hz).
     - `frameDurationMs: Int` — streaming frame size in ms when using BYO Streaming (20|40|60; default 20).
     - `persistRawAudio: Bool` — persist raw mic audio locally (default false; opt‑in).
     - `inputRoutePolicy: InputRoutePolicy` — prefer built‑in mic vs allow Bluetooth (default built‑in preferred).

- `CaptureMode` — `.continuous`, `.voiceActivated`, `.manual`
- `AudioFormat` — `.pcm16`, `.wav`, `.m4a`
- `PermissionStatus` — `.granted`, `.denied`, `.notDetermined`
- `VADState` — `.speech`, `.silence`, `.unknown`
 - `StreamTarget` — `{ url: URL, headers: [String: String], protocolType?: .websocket | .grpc }` (protocolType is optional; BYO streaming is V2)
- `AudioFrame` — `{ data: Data, timestamp: TimeInterval, sampleRate: Double, channels: Int }` (PCM16)
- `ChunkMetadata` — `{ sequenceId: Int, startTimestamp: TimeInterval, endTimestamp: TimeInterval, sampleRate: Double, deviceId: String, micPosition?: String, confidenceHint?: Float }`
- `ExportResult` — `{ url: URL, duration: TimeInterval, format: AudioFormat }`
- `AudioCaptureError` — `permissionDenied`, `audioEngineStartFailed`, `streamingFailed`, `exportFailed`, etc.
 - `ExportResult` — `{ url: URL, duration: TimeInterval, format: AudioFormat }`
 - `AudioCaptureError` — `permissionDenied`, `audioEngineStartFailed`, `streamingFailed`, `exportFailed`, etc.
 - Dictation convenience callbacks:
   - `onPartialTranscript: ((String) -> Void)?` — partial/intermediate transcript updates (Native Speech).
   - `onFinalTranscript: ((String) -> Void)?` — final transcript for a committed block.

## `AudioCaptureSDK` — main entry

Constructor

```swift
public init(config: AudioCaptureConfig)
```

Permissions

```swift
public func requestPermissions() async throws -> PermissionStatus
public func checkPermissions() -> PermissionStatus
```

Capture lifecycle

```swift
public func startCapture(mode: CaptureMode = .continuous) throws
public func pauseCapture() throws
public func resumeCapture() throws
public func stopCapture() throws
```

Streaming

```swift
// BYO streaming is optional (V2). V1 apps should prefer Apple's Speech framework for transcription.
public func startStream(to target: StreamTarget) throws
public func stopStream() throws
```

Exporting

```swift
public func exportRecording(format: AudioFormat, destination: URL) async throws -> ExportResult
```

Callbacks (public vars)

- `public var onFrame: ((AudioFrame) -> Void)?` — receives each processed frame as raw PCM16 `Data`.
- `public var onVADStateChange: ((VADState) -> Void)?` — voice activity detection updates.
- `public var onChunkSent: ((ChunkMetadata) -> Void)?` — chunk ACK metadata when streamed.
- `public var onError: ((Error) -> Void)?` — fatal/non-fatal error reporting.
 - `public var onFrame: ((AudioFrame) -> Void)?` — receives each processed frame as raw PCM16 `Data`.
 - `public var onVADStateChange: ((VADState) -> Void)?` — voice activity detection updates.
 - `public var onChunkSent: ((ChunkMetadata) -> Void)?` — chunk ACK metadata when streamed.
 - `public var onError: ((Error) -> Void)?` — fatal/non-fatal error reporting.
 - `public var onPartialTranscript: ((String) -> Void)?` — incremental partial transcripts (Native Speech).
 - `public var onFinalTranscript: ((String) -> Void)?` — final transcript output (Native Speech).

**Threading note:** callbacks may be invoked on background threads. Dispatch to the main thread for UI updates.

## Behavior & guarantees

- `startCapture` throws `AudioCaptureError.permissionDenied` when microphone permission is not granted.
- The SDK captures 16-bit PCM and attempts to convert inputs to the requested `sampleRate` and channel count.
 - The SDK captures 16-bit PCM and will convert inputs to the configured `sampleRate`/channels where possible.
 - Native Speech (V1): `onPartialTranscript` and `onFinalTranscript` provide incremental and final results via Apple's `SFSpeechRecognizer`. No external server required.
 - BYO Streaming (V2): frames are emitted at `frameDurationMs` cadence (20–60 ms) as binary WebSocket frames; frames are grouped into 0.5–1.0 s segments for ACK/resume bookkeeping. JSON control messages may be used for session metadata; avoid base64-in-JSON for audio payloads (it adds ~33% overhead).
 - Raw audio persistence is opt‑in via `persistRawAudio` (default false). When enabled, audio is stored in app Application Support with file protection and excluded from backups.
 - `exportRecording(.wav, destination:)` will write a valid WAV file with a standard header. `m4a` support may be unavailable on early versions and can return `AudioCaptureError.exportFailed`.

## Error handling

- Prefer observing `onError` for non-throwing runtime issues (stream interruptions, transient failures).
- Public methods throw `AudioCaptureError` for incorrect usage or fatal errors (e.g., starting capture twice, audio engine start failures).

## Integration tips

- For best ASR accuracy in noisy environments, enable noise suppression and AGC; consider RNNoise integration for heavier noise scenarios.
- Use `onVADStateChange` to gate UI updates (recording indicator) and to avoid sending silence to the backend.
- Persist raw audio locally for later reprocessing and model improvements.
- Keep chunk sizes between 800ms and 2000ms for a good latency/overhead balance.
 - For V1 (recommended): use Apple Speech (`SFSpeechRecognizer`) for transcription — simplest and zero backend maintenance.
 - Use `onVADStateChange` to gate UI updates (recording indicator) and to avoid sending silence to the backend.
 - Persist raw audio is opt‑in; only enable when you need later reprocessing or debugging.
 - For BYO Streaming (V2): prefer binary WebSocket frames (raw PCM) and small frame cadence (20–60 ms). Group frames into ~0.5–1.0 s segments for ACK/resume bookkeeping.

## Glossary (technical terms)

- **VAD (Voice Activity Detection):** algorithm that determines whether a segment contains speech or silence. Useful for lowering bandwidth and avoiding false triggers.

- **RNNoise:** a lightweight recurrent neural net-based noise suppression library originally from Xiph/WebRTC. Provides robust noise reduction with moderate CPU cost.

- **AGC (Automatic Gain Control):** adjusts signal amplitude to keep recorded levels in an optimal range; reduces clipping/very low amplitude issues.

- **Chunking:** splitting continuous audio into discrete segments (`chunkDurationMs`) with timestamps and sequence IDs for incremental streaming.

- **PCM16:** Pulse-code modulation at 16 bits per sample. This is the raw audio format the SDK uses for highest compatibility with ASR services.

- **Resampling / format conversion:** converting input audio sample rate and channel count to the configured output format.

## Example: streaming payload (JSON)

```json
// BYO streaming V2: prefer binary WebSocket frames for audio payloads.
// Example control message (JSON) for segment metadata; audio itself should be sent as a binary frame.
{
  "sequenceId": 12,
  "startSampleIndex": 123456789,
  "endSampleIndex": 123456789 + 16000,
  "sampleRate": 16000,
  "deviceId": "device-uuid",
  "segmentDurationMs": 1000
}
```

## Contact & contribution

If you need changes to the API, proposed renames, or additional convenience helpers (e.g., Swift async streams for frames), open an issue or a PR in the repository.
