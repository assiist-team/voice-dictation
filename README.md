# Swift Audio Capture SDK

A production-grade Swift module for ultra-faithful per-word audio capture, preprocessing, VAD, chunked streaming, and export APIs.

## Features

- **Low-latency audio capture** using AVAudioEngine with hardware-backed buffers
- **Voice Activity Detection (VAD)** with tunable sensitivity
- **Audio preprocessing** including noise suppression, AGC, and high-pass filtering
- **Chunked streaming** via WebSocket with timestamps and ACKs
- **Local storage** of raw and processed audio for reprocessing
- **Cross-platform** support for iOS and macOS

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/swift_dictation.git", from: "1.0.0")
]
```

### CocoaPods

```ruby
pod 'SwiftDictation', '~> 1.0.0'
```

## Usage

### Basic Usage

```swift
import SwiftDictation

// Create configuration
let config = AudioCaptureConfig(
    sampleRate: 16000,
    channels: 1,
    vadSensitivity: 0.5,
    noiseSuppressionLevel: 0.5,
    frameDurationMs: 20,
    persistRawAudio: false,
    inputRoutePolicy: .builtInPreferred
)

// Initialize SDK
let sdk = AudioCaptureSDK(config: config)

// Request permissions
let status = try await sdk.requestPermissions()
guard status == .granted else {
    // Handle permission denial
    return
}

// Setup callbacks
sdk.onFrame = { frame in
    // Handle audio frame
}

sdk.onVADStateChange = { state in
    // Handle VAD state changes
}

sdk.onError = { error in
    // Handle errors
}

// Start capture
try sdk.startCapture()

// Start streaming (optional, V2 - BYO provider). For V1 use Apple Speech and dictation callbacks.
// Example (only needed if you implement BYO streaming):
// let target = StreamTarget(
//     url: URL(string: "wss://your-server.com/stream")!,
//     headers: ["Authorization": "Bearer token"]
// )
// try sdk.startStream(to: target)

// Stop capture
try sdk.stopCapture()
```

### Voice Dictation UI (SwiftUI)

```swift
import SwiftUI
import SwiftDictation

struct ContentView: View {
    @State private var text: String = ""
    
    var body: some View {
        VStack {
            TextEditor(text: $text)
            VoiceDictationView(text: $text)
        }
    }
}
```

> Note: Cross-platform plugin work was experimental and has been removed from this repository. Use the core Swift SDK (`SwiftDictation`) for iOS/macOS integration.

## Configuration Options

- `sampleRate`: Audio sample rate in Hz (default: 16000)
- `channels`: Number of audio channels (default: 1 for mono)
- `vadSensitivity`: VAD sensitivity 0.0-1.0 (default: 0.5)
- `noiseSuppressionLevel`: Noise suppression level 0.0-1.0 (default: 0.5)
- `chunkDurationMs`: Chunk duration for streaming in milliseconds (default: 1000)
- `enableHardwareEncode`: Enable hardware encoding if available (default: false)
- `bluetoothPreferred`: Prefer Bluetooth devices (default: true)
- `enableAGC`: Enable automatic gain control (default: true)
- `highPassFilterCutoff`: High-pass filter cutoff frequency in Hz (default: 80.0)

## Architecture

- **Capture Layer**: AVAudioEngine for low-latency PCM capture
- **Preprocessing Layer**: VAD, noise suppression, AGC, filtering
- **Transport Layer**: Chunked streaming via WebSocket/gRPC
- **Storage Layer**: Local secure storage of raw and processed audio

## Requirements

- iOS 14.0+ / macOS 11.0+
- Swift 5.9+
- Xcode 15.0+

## License

MIT License - see LICENSE file for details

