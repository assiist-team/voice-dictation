import Foundation
import AVFoundation

/// Internal audio capture engine using AVAudioEngine
internal class AudioCaptureEngine {
    private let config: AudioCaptureConfig
    private(set) var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var isCapturing = false
    private let processingQueue = DispatchQueue(label: "com.swiftdictation.audio.processing", qos: .userInitiated)
    
    var onAudioBuffer: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?
    
    init(config: AudioCaptureConfig) {
        self.config = config
    }
    
    func setup() throws {
        let audioEngine = AVAudioEngine()
        self.audioEngine = audioEngine
        
        inputNode = audioEngine.inputNode
        guard let inputNode = inputNode else {
            throw AudioCaptureError.audioSessionConfigurationFailed
        }
        
        // Configure audio session (iOS only)
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: [])
        
        // Prefer Bluetooth if configured
        if config.bluetoothPreferred {
            try audioSession.setPreferredInput(audioSession.availableInputs?.first { input in
                input.portType == .bluetoothHFP || input.portType == .bluetoothA2DP
            })
        }
        
        // Set sample rate
        try audioSession.setPreferredSampleRate(config.sampleRate)
        try audioSession.setActive(true)
        #endif
        
        // Get the actual input format
        let inputFormat = inputNode.inputFormat(forBus: 0)
        
        // Create target format (mono, 16kHz)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: config.sampleRate,
            channels: AVAudioChannelCount(config.channels),
            interleaved: false
        ) else {
            throw AudioCaptureError.invalidConfiguration
        }
        
        self.audioFormat = targetFormat
        
        // Install tap - use converter if format conversion needed
        if inputFormat.sampleRate != config.sampleRate || inputFormat.channelCount != AVAudioChannelCount(config.channels) {
            // Create converter for format conversion
            guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
                throw AudioCaptureError.invalidConfiguration
            }
            self.converter = converter
            
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
                guard let self = self, let converter = self.converter else { return }
                
                let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: buffer.frameLength)!
                var error: NSError?
                let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }
                
                if status == .haveData {
                    self.processingQueue.async {
                        self.onAudioBuffer?(outputBuffer, time)
                    }
                }
            }
        } else {
            // Direct tap - no conversion needed
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
                guard let self = self else { return }
                self.processingQueue.async {
                    self.onAudioBuffer?(buffer, time)
                }
            }
        }
    }
    
    func start() throws {
        guard let audioEngine = audioEngine else {
            throw AudioCaptureError.audioSessionConfigurationFailed
        }
        
        guard !isCapturing else {
            throw AudioCaptureError.captureAlreadyInProgress
        }
        
        do {
            try audioEngine.start()
            isCapturing = true
        } catch {
            throw AudioCaptureError.audioEngineStartFailed(error)
        }
    }
    
    func stop() throws {
        guard let audioEngine = audioEngine else { return }
        
        guard isCapturing else {
            throw AudioCaptureError.captureNotInProgress
        }
        
        inputNode?.removeTap(onBus: 0)
        audioEngine.stop()
        isCapturing = false
        
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            // Log but don't throw - stopping is more important
        }
        #endif
    }
    
    func pause() {
        audioEngine?.pause()
    }
    
    func resume() throws {
        guard let audioEngine = audioEngine else {
            throw AudioCaptureError.audioSessionConfigurationFailed
        }
        
        do {
            try audioEngine.start()
        } catch {
            throw AudioCaptureError.audioEngineStartFailed(error)
        }
    }
}

