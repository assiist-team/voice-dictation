# Swift Voice Dictation

A native Swift package for microphone capture, Apple Speech transcription,
voice-activity detection, audio chunking, WebSocket delivery, and WAV export on
iOS and macOS.

The package provides the capture and transport primitives used by a dictation
interface. It deliberately leaves any remote transcription service and product UI
to the integrating application.

## What is included

- `AVAudioEngine` microphone capture with pause, resume, interruption, and route-change handling
- partial and final transcription callbacks backed by Apple's Speech framework
- energy-based voice-activity detection
- configurable audio chunking with timestamps and sequence metadata
- optional WebSocket delivery to an application-supplied endpoint
- in-memory audio storage and WAV export
- lightweight high-pass filtering and gain normalization
- latency and processing metrics callbacks

## Installation

Add the package with Swift Package Manager:

```swift
dependencies: [
    .package(
        url: "https://github.com/nine4-team/swift-voice-dictation.git",
        branch: "main"
    )
]
```

Then add `SwiftDictation` as a dependency of your application target.

## Basic usage

```swift
import SwiftDictation

let config = AudioCaptureConfig(
    sampleRate: 16_000,
    channels: 1,
    vadSensitivity: 0.5,
    frameDurationMs: 20,
    persistRawAudio: false,
    inputRoutePolicy: .builtInPreferred
)

let capture = AudioCaptureSDK(config: config)

capture.onPartialTranscript = { text in
    print("Partial: \(text)")
}

capture.onFinalTranscript = { text in
    print("Final: \(text)")
}

capture.onError = { error in
    print("Capture error: \(error)")
}

let permission = try await capture.requestPermissions()
guard permission == .granted else { return }

try capture.startCapture()

// Later:
try capture.stopCapture()
```

Apps must include microphone and speech-recognition usage descriptions in their
platform configuration. The example iOS target demonstrates the required setup.

## Optional streaming

The SDK can send audio chunks to an endpoint supplied by the integrating app:

```swift
let target = StreamTarget(
    url: URL(string: "wss://example.com/audio")!,
    headers: ["Authorization": "Bearer <token>"]
)

try capture.startStream(to: target)
```

WebSocket transport is implemented. The `grpc` protocol option is reserved but not
implemented.

## Verification

```bash
swift test
```

The package currently has 15 passing unit tests covering configuration, state
transitions, VAD, chunking, WAV export, and transcript callback behavior. Microphone,
permission, route-change, and Apple Speech behavior still require device or simulator
testing.

## Requirements

- iOS 14 or later
- macOS 11 or later
- Swift 5.9 or later
- Xcode 15 or later

## License

MIT. See [LICENSE](LICENSE).
