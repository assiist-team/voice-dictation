import Foundation

/// Errors that can occur during audio capture
public enum AudioCaptureError: LocalizedError, Equatable {
    case permissionDenied
    case permissionNotDetermined
    case audioSessionConfigurationFailed
    case audioEngineStartFailed(Error)
    case audioEngineStopFailed(Error)
    case invalidConfiguration
    case captureAlreadyInProgress
    case captureNotInProgress
    case streamingFailed(Error)
    case exportFailed(Error)
    case invalidAudioFormat
    case deviceInterrupted
    
    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission was denied"
        case .permissionNotDetermined:
            return "Microphone permission has not been determined"
        case .audioSessionConfigurationFailed:
            return "Failed to configure audio session"
        case .audioEngineStartFailed(let error):
            return "Failed to start audio engine: \(error.localizedDescription)"
        case .audioEngineStopFailed(let error):
            return "Failed to stop audio engine: \(error.localizedDescription)"
        case .invalidConfiguration:
            return "Invalid audio capture configuration"
        case .captureAlreadyInProgress:
            return "Audio capture is already in progress"
        case .captureNotInProgress:
            return "Audio capture is not in progress"
        case .streamingFailed(let error):
            return "Streaming failed: \(error.localizedDescription)"
        case .exportFailed(let error):
            return "Export failed: \(error.localizedDescription)"
        case .invalidAudioFormat:
            return "Invalid audio format"
        case .deviceInterrupted:
            return "Audio capture was interrupted by device"
        }
    }

    // Manual Equatable implementation because some cases carry `Error`
    public static func == (lhs: AudioCaptureError, rhs: AudioCaptureError) -> Bool {
        switch (lhs, rhs) {
        case (.permissionDenied, .permissionDenied): return true
        case (.permissionNotDetermined, .permissionNotDetermined): return true
        case (.audioSessionConfigurationFailed, .audioSessionConfigurationFailed): return true
        case (.audioEngineStartFailed(let a), .audioEngineStartFailed(let b)):
            let na = a as NSError
            let nb = b as NSError
            return na.domain == nb.domain && na.code == nb.code
        case (.audioEngineStopFailed(let a), .audioEngineStopFailed(let b)):
            let na = a as NSError
            let nb = b as NSError
            return na.domain == nb.domain && na.code == nb.code
        case (.invalidConfiguration, .invalidConfiguration): return true
        case (.captureAlreadyInProgress, .captureAlreadyInProgress): return true
        case (.captureNotInProgress, .captureNotInProgress): return true
        case (.streamingFailed(let a), .streamingFailed(let b)):
            let na = a as NSError
            let nb = b as NSError
            return na.domain == nb.domain && na.code == nb.code
        case (.exportFailed(let a), .exportFailed(let b)):
            let na = a as NSError
            let nb = b as NSError
            return na.domain == nb.domain && na.code == nb.code
        case (.invalidAudioFormat, .invalidAudioFormat): return true
        case (.deviceInterrupted, .deviceInterrupted): return true
        default: return false
        }
    }
}

