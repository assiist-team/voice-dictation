# SwiftDictation — Public API Reference

This document describes the public API exposed by the `SwiftDictation` SDK, how to use it, and the meaning of key technical terms used by the SDK.

## Overview

`SwiftDictation` provides low-latency audio capture, preprocessing (VAD, AGC, optional RNNoise), chunked streaming, local persistence, and export utilities for iOS and macOS. The API is synchronous where appropriate and uses async/await for permission and export flows.

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
    - `sampleRate: Double` — capture sample rate in Hz (default 16000).
    - `channels: Int` — number of channels (default 1).
    - `vadSensitivity: Float` — 0.0–1.0 (higher = more sensitive).
    - `noiseSuppressionLevel: Float` — 0.0–1.0 for built-in suppression.
    - `chunkDurationMs: Int` — duration of streaming chunks in ms.
    - `enableHardwareEncode: Bool` — allow hardware encoders when available.
    - `bluetoothPreferred: Bool` — prefer Bluetooth inputs if present.
    - `enableAGC: Bool` — automatic gain control.
    - `highPassFilterCutoff: Double` — high-pass cutoff frequency (Hz).

- `CaptureMode` — `.continuous`, `.voiceActivated`, `.manual`
- `AudioFormat` — `.pcm16`, `.wav`, `.m4a`
- `PermissionStatus` — `.granted`, `.denied`, `.notDetermined`
- `VADState` — `.speech`, `.silence`, `.unknown`
- `StreamTarget` — `{ url: URL, headers: [String: String], protocolType: .websocket | .grpc }`
- `AudioFrame` — `{ data: Data, timestamp: TimeInterval, sampleRate: Double, channels: Int }` (PCM16)
- `ChunkMetadata` — `{ sequenceId: Int, startTimestamp: TimeInterval, endTimestamp: TimeInterval, sampleRate: Double, deviceId: String, micPosition?: String, confidenceHint?: Float }`
- `ExportResult` — `{ url: URL, duration: TimeInterval, format: AudioFormat }`
- `AudioCaptureError` — `permissionDenied`, `audioEngineStartFailed`, `streamingFailed`, `exportFailed`, etc.

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

**Threading note:** callbacks may be invoked on background threads. Dispatch to the main thread for UI updates.

## Behavior & guarantees

- `startCapture` throws `AudioCaptureError.permissionDenied` when microphone permission is not granted.
- The SDK captures 16-bit PCM and attempts to convert inputs to the requested `sampleRate` and channel count.
- Chunking uses device-monotonic timestamps and sequence IDs; `chunkDurationMs` defines the target chunk size.
- `startStream` opens a WebSocket (or gRPC when implemented); audio chunks are base64-encoded in messages with accompanying `ChunkMetadata`.
- Raw audio is persisted locally by default so recordings can be reprocessed.
- `exportRecording(.wav, destination:)` will write a valid WAV file with a standard header. `m4a` support may be unavailable on early versions and can return `AudioCaptureError.exportFailed`.

## Error handling

- Prefer observing `onError` for non-throwing runtime issues (stream interruptions, transient failures).
- Public methods throw `AudioCaptureError` for incorrect usage or fatal errors (e.g., starting capture twice, audio engine start failures).

## Integration tips

- For best ASR accuracy in noisy environments, enable noise suppression and AGC; consider RNNoise integration for heavier noise scenarios.
- Use `onVADStateChange` to gate UI updates (recording indicator) and to avoid sending silence to the backend.
- Persist raw audio locally for later reprocessing and model improvements.
- Keep chunk sizes between 800ms and 2000ms for a good latency/overhead balance.

## Glossary (technical terms)

- **VAD (Voice Activity Detection):** algorithm that determines whether a segment contains speech or silence. Useful for lowering bandwidth and avoiding false triggers.

- **RNNoise:** a lightweight recurrent neural net-based noise suppression library originally from Xiph/WebRTC. Provides robust noise reduction with moderate CPU cost.

- **AGC (Automatic Gain Control):** adjusts signal amplitude to keep recorded levels in an optimal range; reduces clipping/very low amplitude issues.

- **Chunking:** splitting continuous audio into discrete segments (`chunkDurationMs`) with timestamps and sequence IDs for incremental streaming.

- **PCM16:** Pulse-code modulation at 16 bits per sample. This is the raw audio format the SDK uses for highest compatibility with ASR services.

- **Resampling / format conversion:** converting input audio sample rate and channel count to the configured output format.

## Example: streaming payload (JSON)

```json
{
  "sequenceId": 12,
  "startTimestamp": 123456789.123,
  "endTimestamp": 123456789.923,
  "sampleRate": 16000,
  "deviceId": "device-uuid",
  "audioData": "<base64-encoded PCM16 chunk>"
}
```

## Contact & contribution

If you need changes to the API, proposed renames, or additional convenience helpers (e.g., Swift async streams for frames), open an issue or a PR in the repository.
