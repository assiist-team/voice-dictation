import Foundation
import AVFoundation

#if os(iOS) || os(macOS)
import Speech
#endif

/// Main SDK class for audio capture, preprocessing, and streaming
public class AudioCaptureSDK {
    private let config: AudioCaptureConfig
    private var captureEngine: AudioCaptureEngine?
    private var preprocessor: AudioPreprocessor?
    private var vad: VoiceActivityDetector?
    private var chunker: AudioChunker?
    private var streamer: AudioStreamer?
    private var storage: AudioStorage?
    
    #if os(iOS) || os(macOS)
    private var speech: NativeSpeechRecognizer?
    #endif
    
    private var isPaused = false
    private var currentSessionId: String?
    private var rawAudioData: Data = Data()
    private var processedAudioData: Data = Data()
    
    // Interruption state tracking
    #if os(iOS)
    private var isInterrupted = false
    private var wasCapturingBeforeInterruption = false
    private var notificationObservers: [NSObjectProtocol] = []
    private let notificationQueue = DispatchQueue(label: "com.swiftdictation.notifications", qos: .userInitiated)
    #endif
    
    // Event callbacks
    public var onFrame: ((AudioFrame) -> Void)?
    public var onVADStateChange: ((VADState) -> Void)?
    public var onChunkSent: ((ChunkMetadata) -> Void)?
    public var onError: ((Error) -> Void)?
    // Dictation convenience callbacks (Native Speech)
    public var onPartialTranscript: ((String) -> Void)?
    public var onFinalTranscript: ((String) -> Void)?
    // Interruption recovery callback
    public var onInterruptionRecovered: (() -> Void)?
    
    public init(config: AudioCaptureConfig) {
        self.config = config
        
        // Setup storage
        do {
            self.storage = try AudioStorage()
        } catch {
            // Log error but continue
        }
    }
    
    /// Request microphone and speech recognition permissions
    public func requestPermissions() async throws -> PermissionStatus {
        #if os(iOS)
        // Request microphone permission
        let micStatus = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                if granted {
                    continuation.resume(returning: .granted)
                } else {
                    continuation.resume(returning: .denied)
                }
            }
        }
        
        guard micStatus == .granted else {
            return micStatus
        }
        
        // Request speech recognition permission
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                switch status {
                case .authorized:
                    continuation.resume(returning: .granted)
                case .denied, .restricted:
                    continuation.resume(returning: .denied)
                case .notDetermined:
                    continuation.resume(returning: .notDetermined)
                @unknown default:
                    continuation.resume(returning: .notDetermined)
                }
            }
        }
        
        return speechStatus
        #elseif os(macOS)
        // macOS doesn't require explicit permission requests for microphone
        // but we should check system permissions
        // Speech recognition permission is handled at system level
        return .granted
        #else
        return .notDetermined
        #endif
    }
    
    /// Check current permission status (microphone and speech recognition)
    public func checkPermissions() -> PermissionStatus {
        #if os(iOS)
        // Check microphone permission
        let micStatus: PermissionStatus
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            micStatus = .granted
        case .denied:
            micStatus = .denied
        case .undetermined:
            micStatus = .notDetermined
        @unknown default:
            micStatus = .notDetermined
        }
        
        guard micStatus == .granted else {
            return micStatus
        }
        
        // Check speech recognition permission
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
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
        
        // Setup interruption and route change observers (iOS only)
        #if os(iOS)
        setupAudioSessionObservers()
        #endif
        
        // Initialize speech recognizer if available
        #if os(iOS) || os(macOS)
        if let audioFormat = engine.audioFormat {
            let speechRecognizer = NativeSpeechRecognizer(audioFormat: audioFormat)
            
            // Bridge callbacks
            speechRecognizer.onPartial = { [weak self] text in
                DispatchQueue.main.async {
                    self?.onPartialTranscript?(text)
                }
            }
            
            speechRecognizer.onFinal = { [weak self] text in
                DispatchQueue.main.async {
                    self?.onFinalTranscript?(text)
                }
            }
            
            speechRecognizer.onError = { [weak self] error in
                DispatchQueue.main.async {
                    self?.onError?(error)
                }
            }
            
            self.speech = speechRecognizer
            
            // Start first block
            do {
                try speechRecognizer.startBlock()
            } catch {
                // Log error but continue - speech recognition is optional
                self.onError?(error)
            }
        }
        #endif
        
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
        
        // Speech recognition continues the same block (no need to restart)
    }
    
    /// Stop capture
    public func stopCapture() throws {
        guard let engine = captureEngine else {
            throw AudioCaptureError.captureNotInProgress
        }
        
        // Remove notification observers
        #if os(iOS)
        removeAudioSessionObservers()
        #endif
        
        try engine.stop()
        
        // Flush remaining chunks
        chunker?.flush()
        
        // Save raw audio
        if config.persistRawAudio, let sessionId = currentSessionId, let storage = storage, !rawAudioData.isEmpty {
            try? storage.saveRawAudio(rawAudioData, sessionId: sessionId)
        }
        
        // Clean up speech recognizer
        #if os(iOS) || os(macOS)
        speech?.cancelBlock()
        speech = nil
        #endif
        
        captureEngine = nil
        isPaused = false
        
        #if os(iOS)
        isInterrupted = false
        wasCapturingBeforeInterruption = false
        #endif
    }
    
    /// Commit the current dictation block and emit final transcript
    public func commitCurrentBlock() throws {
        #if os(iOS) || os(macOS)
        guard let speech = speech else {
            throw AudioCaptureError.captureNotInProgress
        }
        
        speech.commitBlock()
        
        // Start a new block if capture is still active
        if captureEngine != nil && !isPaused {
            try speech.startBlock()
        }
        #else
        throw AudioCaptureError.invalidConfiguration
        #endif
    }
    
    /// Cancel the current dictation block (discard without final transcript)
    public func cancelCurrentBlock() throws {
        #if os(iOS) || os(macOS)
        guard let speech = speech else {
            throw AudioCaptureError.captureNotInProgress
        }
        
        speech.cancelBlock()
        
        // Start a new block if capture is still active
        if captureEngine != nil && !isPaused {
            try speech.startBlock()
        }
        #else
        throw AudioCaptureError.invalidConfiguration
        #endif
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
            throw AudioCaptureError.exportFailed(NSError(domain: "AudioCaptureSDK", code: -1, userInfo: [NSLocalizedDescriptionKey: "Audio storage not initialized"]))
        }
        
        let audioData = processedAudioData.isEmpty ? rawAudioData : processedAudioData
        guard !audioData.isEmpty else {
            throw AudioCaptureError.exportFailed(NSError(domain: "AudioCaptureSDK", code: -2, userInfo: [NSLocalizedDescriptionKey: "No audio data available to export"]))
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
            throw AudioCaptureError.exportFailed(NSError(domain: "AudioCaptureSDK", code: -3, userInfo: [NSLocalizedDescriptionKey: "M4A export is not yet implemented"]))
        }
        
        // Calculate duration: bytes / (sampleRate * channels * bytesPerSample)
        // 16-bit = 2 bytes per sample
        let duration = Double(audioData.count) / (config.sampleRate * Double(config.channels) * 2.0)
        
        return ExportResult(url: destination, duration: duration, format: format)
    }
    
    // MARK: - Private Methods
    
    #if os(iOS)
    /// Setup AVAudioSession notification observers
    private func setupAudioSessionObservers() {
        let audioSession = AVAudioSession.sharedInstance()
        let notificationCenter = NotificationCenter.default
        
        // Interruption notification
        let interruptionObserver = notificationCenter.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: audioSession,
            queue: nil
        ) { [weak self] notification in
            self?.handleInterruption(notification: notification)
        }
        notificationObservers.append(interruptionObserver)
        
        // Route change notification
        let routeChangeObserver = notificationCenter.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: audioSession,
            queue: nil
        ) { [weak self] notification in
            self?.handleRouteChange(notification: notification)
        }
        notificationObservers.append(routeChangeObserver)
        
        // Media services lost notification
        let mediaServicesLostObserver = notificationCenter.addObserver(
            forName: AVAudioSession.mediaServicesWereLostNotification,
            object: audioSession,
            queue: nil
        ) { [weak self] _ in
            self?.handleMediaServicesLost()
        }
        notificationObservers.append(mediaServicesLostObserver)
        
        // Media services reset notification
        let mediaServicesResetObserver = notificationCenter.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: audioSession,
            queue: nil
        ) { [weak self] _ in
            self?.handleMediaServicesReset()
        }
        notificationObservers.append(mediaServicesResetObserver)
    }
    
    /// Remove AVAudioSession notification observers
    private func removeAudioSessionObservers() {
        let notificationCenter = NotificationCenter.default
        for observer in notificationObservers {
            notificationCenter.removeObserver(observer)
        }
        notificationObservers.removeAll()
    }
    
    /// Handle audio interruption
    private func handleInterruption(notification: Notification) {
        notificationQueue.async { [weak self] in
            guard let self = self,
                  let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                return
            }
            
            switch type {
            case .began:
                self.handleInterruptionBegan()
            case .ended:
                if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    self.handleInterruptionEnded(shouldResume: options.contains(.shouldResume))
                } else {
                    self.handleInterruptionEnded(shouldResume: false)
                }
            @unknown default:
                break
            }
        }
    }
    
    /// Handle interruption began
    private func handleInterruptionBegan() {
        guard !isInterrupted else { return }
        
        isInterrupted = true
        wasCapturingBeforeInterruption = captureEngine != nil && !isPaused
        
        // Pause the engine and mark as paused
        if let engine = captureEngine, !isPaused {
            engine.pause()
            isPaused = true
        }
        
        // Surface error
        DispatchQueue.main.async { [weak self] in
            self?.onError?(AudioCaptureError.deviceInterrupted)
        }
    }
    
    /// Handle interruption ended
    private func handleInterruptionEnded(shouldResume: Bool) {
        guard isInterrupted else { return }
        
        // Reactivate audio session
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setActive(true)
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.onError?(AudioCaptureError.audioSessionConfigurationFailed)
            }
            isInterrupted = false
            wasCapturingBeforeInterruption = false
            return
        }
        
        // Resume if we were capturing before and should resume
        if shouldResume && wasCapturingBeforeInterruption {
            do {
                try resumeCapture()
                isInterrupted = false
                wasCapturingBeforeInterruption = false
                
                DispatchQueue.main.async { [weak self] in
                    self?.onInterruptionRecovered?()
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.onError?(error)
                }
            }
        } else {
            isInterrupted = false
            wasCapturingBeforeInterruption = false
        }
    }
    
    /// Handle route change
    private func handleRouteChange(notification: Notification) {
        notificationQueue.async { [weak self] in
            guard let self = self,
                  let userInfo = notification.userInfo,
                  let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
                return
            }
            
            switch reason {
            case .newDeviceAvailable, .oldDeviceUnavailable:
                self.handleRouteChangeReconfigure()
            case .categoryChange:
                // Category change might require re-setup
                if self.captureEngine != nil && !self.isPaused {
                    self.handleRouteChangeReconfigure()
                }
            default:
                break
            }
        }
    }
    
    /// Reconfigure after route change
    private func handleRouteChangeReconfigure() {
        guard let engine = captureEngine, !isPaused else { return }
        
        // Stop current engine
        do {
            try engine.stop()
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.onError?(error)
            }
            return
        }
        
        // Re-setup with new route
        do {
            let newEngine = AudioCaptureEngine(config: config)
            try newEngine.setup()
            
            // Restore callbacks
            newEngine.onAudioBuffer = { [weak self] buffer, time in
                self?.handleAudioBuffer(buffer: buffer, time: time)
            }
            
            // Re-setup preprocessor
            if let preprocessor = preprocessor {
                try preprocessor.setup(audioEngine: newEngine.audioEngine!)
            }
            
            // Restart engine
            try newEngine.start()
            
            self.captureEngine = newEngine
            
            // Restart speech recognizer if needed
            #if os(iOS) || os(macOS)
            if let audioFormat = newEngine.audioFormat {
                // Cancel existing speech recognizer if present
                speech?.cancelBlock()
                
                let speechRecognizer = NativeSpeechRecognizer(audioFormat: audioFormat)
                
                speechRecognizer.onPartial = { [weak self] text in
                    DispatchQueue.main.async {
                        self?.onPartialTranscript?(text)
                    }
                }
                
                speechRecognizer.onFinal = { [weak self] text in
                    DispatchQueue.main.async {
                        self?.onFinalTranscript?(text)
                    }
                }
                
                speechRecognizer.onError = { [weak self] error in
                    DispatchQueue.main.async {
                        self?.onError?(error)
                    }
                }
                
                self.speech = speechRecognizer
                
                do {
                    try speechRecognizer.startBlock()
                } catch {
                    self.onError?(error)
                }
            }
            #endif
            
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.onError?(error)
            }
        }
    }
    
    /// Handle media services lost
    private func handleMediaServicesLost() {
        // Treat as hard interruption - stop cleanly
        if let engine = captureEngine {
            do {
                try engine.stop()
            } catch {
                // Log but continue
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.onError?(AudioCaptureError.deviceInterrupted)
        }
        
        isInterrupted = true
        wasCapturingBeforeInterruption = captureEngine != nil && !isPaused
    }
    
    /// Handle media services reset
    private func handleMediaServicesReset() {
        // Reconfigure everything
        let wasCapturing = captureEngine != nil && !isPaused
        
        // Clean up current engine
        if let engine = captureEngine {
            do {
                try engine.stop()
            } catch {
                // Log but continue
            }
        }
        
        // Re-setup if we were capturing
        if wasCapturing {
            do {
                try startCapture()
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.onError?(error)
                }
            }
        }
        
        isInterrupted = false
        wasCapturingBeforeInterruption = false
    }
    #endif
    
    private func handleAudioBuffer(buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        // Process audio
        let processedBuffer = preprocessor?.process(buffer: buffer) ?? buffer
        
        // Append to speech recognizer if active
        #if os(iOS) || os(macOS)
        if let speech = speech {
            speech.append(processedBuffer)
        }
        #endif
        
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
            timestamp: Double(time.sampleTime) / config.sampleRate,
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

