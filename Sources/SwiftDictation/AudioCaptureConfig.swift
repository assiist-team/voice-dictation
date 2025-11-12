import Foundation
import AVFoundation

/// Configuration for audio capture behavior
public struct AudioCaptureConfig {
    /// Sample rate in Hz (default: 16000 for ASR)
    public var sampleRate: Double
    
    /// Number of audio channels (default: 1 for mono)
    public var channels: Int
    
    /// VAD sensitivity (0.0 to 1.0, higher = more sensitive)
    public var vadSensitivity: Float
    
    /// Noise suppression level (0.0 to 1.0, higher = more aggressive)
    public var noiseSuppressionLevel: Float
    
    /// Chunk duration in milliseconds (default: 1000ms)
    public var chunkDurationMs: Int
    
    /// Enable hardware encoding if available
    public var enableHardwareEncode: Bool
    
    /// Prefer Bluetooth devices (AirPods, etc.)
    public var bluetoothPreferred: Bool
    
    /// Enable automatic gain control
    public var enableAGC: Bool
    
    /// High-pass filter cutoff frequency in Hz (0 to disable)
    public var highPassFilterCutoff: Double
    
    public init(
        sampleRate: Double = 16000,
        channels: Int = 1,
        vadSensitivity: Float = 0.5,
        noiseSuppressionLevel: Float = 0.5,
        chunkDurationMs: Int = 1000,
        enableHardwareEncode: Bool = false,
        bluetoothPreferred: Bool = true,
        enableAGC: Bool = true,
        highPassFilterCutoff: Double = 80.0
    ) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.vadSensitivity = vadSensitivity
        self.noiseSuppressionLevel = noiseSuppressionLevel
        self.chunkDurationMs = chunkDurationMs
        self.enableHardwareEncode = enableHardwareEncode
        self.bluetoothPreferred = bluetoothPreferred
        self.enableAGC = enableAGC
        self.highPassFilterCutoff = highPassFilterCutoff
    }
}

/// Capture mode for different use cases
public enum CaptureMode {
    case continuous
    case voiceActivated
    case manual
}

/// Audio format for export
public enum AudioFormat {
    case pcm16
    case wav
    case m4a
}

/// Permission status for microphone access
public enum PermissionStatus {
    case granted
    case denied
    case notDetermined
}

/// VAD (Voice Activity Detection) state
public enum VADState {
    case speech
    case silence
    case unknown
}

/// Stream target configuration
public struct StreamTarget {
    public var url: URL
    public var headers: [String: String]
    public var protocolType: StreamProtocol
    
    public enum StreamProtocol {
        case websocket
        case grpc
    }
    
    public init(url: URL, headers: [String: String] = [:], protocolType: StreamProtocol = .websocket) {
        self.url = url
        self.headers = headers
        self.protocolType = protocolType
    }
}

/// Audio frame data
public struct AudioFrame {
    public var data: Data
    public var timestamp: TimeInterval
    public var sampleRate: Double
    public var channels: Int
    
    public init(data: Data, timestamp: TimeInterval, sampleRate: Double, channels: Int) {
        self.data = data
        self.timestamp = timestamp
        self.sampleRate = sampleRate
        self.channels = channels
    }
}

/// Chunk metadata for streaming
public struct ChunkMetadata {
    public var sequenceId: Int
    public var startTimestamp: TimeInterval
    public var endTimestamp: TimeInterval
    public var sampleRate: Double
    public var deviceId: String
    public var micPosition: String?
    public var confidenceHint: Float?
    
    public init(
        sequenceId: Int,
        startTimestamp: TimeInterval,
        endTimestamp: TimeInterval,
        sampleRate: Double,
        deviceId: String,
        micPosition: String? = nil,
        confidenceHint: Float? = nil
    ) {
        self.sequenceId = sequenceId
        self.startTimestamp = startTimestamp
        self.endTimestamp = endTimestamp
        self.sampleRate = sampleRate
        self.deviceId = deviceId
        self.micPosition = micPosition
        self.confidenceHint = confidenceHint
    }
}

/// Export result
public struct ExportResult {
    public var url: URL
    public var duration: TimeInterval
    public var format: AudioFormat
    
    public init(url: URL, duration: TimeInterval, format: AudioFormat) {
        self.url = url
        self.duration = duration
        self.format = format
    }
}

