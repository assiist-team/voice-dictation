import Foundation
import AVFoundation

/// Main SDK class for audio capture, preprocessing, and streaming
public class AudioCaptureSDK {
    private let config: AudioCaptureConfig
    private var captureEngine: AudioCaptureEngine?
    private var preprocessor: AudioPreprocessor?
    private var vad: VoiceActivityDetector?
    private var chunker: AudioChunker?
    private var streamer: AudioStreamer?
    private var storage: AudioStorage?
    
    private var isPaused = false
    private var currentSessionId: String?
    private var rawAudioData: Data = Data()
    private var processedAudioData: Data = Data()
    
    // Event callbacks
    public var onFrame: ((AudioFrame) -> Void)?
    public var onVADStateChange: ((VADState) -> Void)?
    public var onChunkSent: ((ChunkMetadata) -> Void)?
    public var onError: ((Error) -> Void)?
    
    public init(config: AudioCaptureConfig) {
        self.config = config
        
        // Setup storage
        do {
            self.storage = try AudioStorage()
        } catch {
            // Log error but continue
        }
    }
    
    /// Request microphone permissions
    public func requestPermissions() async throws -> PermissionStatus {
        #if os(iOS)
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                if granted {
                    continuation.resume(returning: .granted)
                } else {
                    continuation.resume(returning: .denied)
                }
            }
        }
        #elseif os(macOS)
        // macOS doesn't require explicit permission requests for microphone
        // but we should check system permissions
        return .granted
        #else
        return .notDetermined
        #endif
    }
    
    /// Check current permission status
    public func checkPermissions() -> PermissionStatus {
        #if os(iOS)
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            return .granted
        case .denied:
            return .denied
        case .undetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
        #elseif os(macOS)
        // macOS permissions are handled at system level
        return .granted
        #else
        return .notDetermined
        #endif
    }
    
    /// Start audio capture
    public func startCapture(mode: CaptureMode = .continuous) throws {
        guard checkPermissions() == .granted else {
            throw AudioCaptureError.permissionDenied
        }
        
        // Initialize components
        let engine = AudioCaptureEngine(config: config)
        try engine.setup()
        
        let preprocessor = AudioPreprocessor(config: config)
        try preprocessor.setup(audioEngine: engine.audioEngine!)
        self.preprocessor = preprocessor
        
        let vad = VoiceActivityDetector(sensitivity: config.vadSensitivity, sampleRate: config.sampleRate)
        self.vad = vad
        
        let chunker = AudioChunker(
            chunkDurationMs: config.chunkDurationMs,
            sampleRate: config.sampleRate,
            deviceId: self.deviceId
        )
        chunker.onChunkReady = { [weak self] data, metadata in
            self?.handleChunkReady(data: data, metadata: metadata)
        }
        self.chunker = chunker
        
        // Setup audio buffer callback
        engine.onAudioBuffer = { [weak self] buffer, time in
            self?.handleAudioBuffer(buffer: buffer, time: time)
        }
        
        self.captureEngine = engine
        
        // Start new session
        currentSessionId = UUID().uuidString
        rawAudioData.removeAll()
        processedAudioData.removeAll()
        isPaused = false
        
        try engine.start()
    }
    
    /// Pause capture (soft stop)
    public func pauseCapture() throws {
        guard let engine = captureEngine else {
            throw AudioCaptureError.captureNotInProgress
        }
        
        engine.pause()
        isPaused = true
    }
    
    /// Resume capture
    public func resumeCapture() throws {
        guard let engine = captureEngine else {
            throw AudioCaptureError.captureNotInProgress
        }
        
        guard isPaused else {
            throw AudioCaptureError.captureAlreadyInProgress
        }
        
        try engine.resume()
        isPaused = false
    }
    
    /// Stop capture
    public func stopCapture() throws {
        guard let engine = captureEngine else {
            throw AudioCaptureError.captureNotInProgress
        }
        
        try engine.stop()
        
        // Flush remaining chunks
        chunker?.flush()
        
        // Save raw audio
        if let sessionId = currentSessionId, let storage = storage, !rawAudioData.isEmpty {
            try? storage.saveRawAudio(rawAudioData, sessionId: sessionId)
        }
        
        captureEngine = nil
        isPaused = false
    }
    
    /// Start streaming to a target
    public func startStream(to target: StreamTarget) throws {
        guard captureEngine != nil else {
            throw AudioCaptureError.captureNotInProgress
        }
        
        let streamer = AudioStreamer(target: target)
        streamer.onChunkSent = { [weak self] metadata in
            self?.onChunkSent?(metadata)
        }
        streamer.onError = { [weak self] error in
            self?.onError?(error)
        }
        
        try streamer.start()
        self.streamer = streamer
    }
    
    /// Stop streaming
    public func stopStream() throws {
        streamer?.stop()
        streamer = nil
    }
    
    /// Export recording to a file
    public func exportRecording(format: AudioFormat, destination: URL) async throws -> ExportResult {
        guard let storage = storage else {
            throw AudioCaptureError.exportFailed(NSError(domain: "AudioCaptureSDK", code: -1))
        }
        
        let audioData = processedAudioData.isEmpty ? rawAudioData : processedAudioData
        guard !audioData.isEmpty else {
            throw AudioCaptureError.exportFailed(NSError(domain: "AudioCaptureSDK", code: -2))
        }
        
        switch format {
        case .pcm16:
            try audioData.write(to: destination)
        case .wav:
            try storage.exportAsWAV(
                audioData: audioData,
                sampleRate: config.sampleRate,
                channels: config.channels,
                destination: destination
            )
        case .m4a:
            throw AudioCaptureError.exportFailed(NSError(domain: "AudioCaptureSDK", code: -3, userInfo: [NSLocalizedDescriptionKey: "M4A export not yet implemented"]))
        }
        
        let duration = Double(audioData.count) / (config.sampleRate * 2.0) // 16-bit = 2 bytes
        
        return ExportResult(url: destination, duration: duration, format: format)
    }
    
    // MARK: - Private Methods
    
    private func handleAudioBuffer(buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        // Process audio
        let processedBuffer = preprocessor?.process(buffer: buffer) ?? buffer
        
        // Convert to Data
        guard let channelData = processedBuffer.int16ChannelData else { return }
        let frameLength = Int(processedBuffer.frameLength)
        let dataSize = frameLength * 2 // 16-bit
        let audioData = Data(bytes: channelData.pointee, count: dataSize)
        
        // Accumulate for storage
        rawAudioData.append(audioData)
        processedAudioData.append(audioData)
        
        // Create frame
        let frame = AudioFrame(
            data: audioData,
            timestamp: time.sampleTime,
            sampleRate: config.sampleRate,
            channels: config.channels
        )
        
        // Notify frame callback
        onFrame?(frame)
        
        // VAD processing
        if let vad = vad {
            let vadState = vad.process(buffer: processedBuffer)
            onVADStateChange?(vadState)
        }
        
        // Chunking
        chunker?.process(buffer: processedBuffer, timestamp: time)
    }
    
    private func handleChunkReady(data: Data, metadata: ChunkMetadata) {
        // Stream if streaming is active
        if let streamer = streamer {
            try? streamer.sendChunk(data, metadata: metadata)
        }
    }
}

#if os(iOS)
import UIKit
#endif

#if os(macOS)
import AppKit
#endif

extension AudioCaptureSDK {
    /// Get device ID (platform-specific)
    private var deviceId: String {
        #if os(iOS)
        return UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #elseif os(macOS)
        return ProcessInfo.processInfo.hostName
        #else
        return UUID().uuidString
        #endif
    }
}

