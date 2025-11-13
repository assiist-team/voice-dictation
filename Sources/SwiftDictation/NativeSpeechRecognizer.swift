import Foundation
import AVFoundation
import Speech

#if os(iOS) || os(macOS)

/// Manages Apple's Speech framework for on-device speech recognition
internal class NativeSpeechRecognizer: NSObject {
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioFormat: AVAudioFormat
    private let processingQueue = DispatchQueue(label: "com.swiftdictation.speech", qos: .userInitiated)
    
    // Callbacks
    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?
    var onError: ((Error) -> Void)?
    
    private var isBlockActive = false
    
    init(audioFormat: AVAudioFormat) {
        self.audioFormat = audioFormat
        super.init()
        
        // Initialize speech recognizer with default locale
        #if os(iOS)
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
        #elseif os(macOS)
        self.speechRecognizer = SFSpeechRecognizer()
        #endif
        
        // Configure recognizer
        speechRecognizer?.delegate = self
    }
    
    /// Start a new recognition block
    func startBlock() throws {
        guard let speechRecognizer = speechRecognizer else {
            throw AudioCaptureError.invalidConfiguration
        }
        
        guard speechRecognizer.isAvailable else {
            throw AudioCaptureError.invalidConfiguration
        }
        
        // Cancel any existing task
        cancelBlock()
        
        // Create new recognition request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        
        // Best-effort on-device recognition if available
        if #available(iOS 13.0, macOS 10.15, *) {
            request.requiresOnDeviceRecognition = speechRecognizer.supportsOnDeviceRecognition
        }
        
        self.recognitionRequest = request
        
        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            
            if let error = error {
                // Check if it's a cancellation (not a real error)
                let nsError = error as NSError
                if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                    // Cancellation - ignore
                    return
                }
                
                self.processingQueue.async {
                    self.onError?(error)
                }
                return
            }
            
            guard let result = result else { return }
            
            let transcript = result.bestTranscription.formattedString
            
            if result.isFinal {
                // Final result
                self.processingQueue.async {
                    self.onFinal?(transcript)
                }
            } else {
                // Partial result
                self.processingQueue.async {
                    self.onPartial?(transcript)
                }
            }
        }
        
        isBlockActive = true
    }
    
    /// Append audio buffer to the current recognition request
    func append(_ buffer: AVAudioPCMBuffer) {
        guard let request = recognitionRequest, isBlockActive else { return }
        
        // Append buffer to the request
        request.append(buffer)
    }
    
    /// Commit the current block (finalize recognition)
    func commitBlock() {
        guard let request = recognitionRequest, isBlockActive else { return }
        
        // End audio input - this will trigger final result
        request.endAudio()
        
        // Reset state
        isBlockActive = false
        recognitionRequest = nil
        recognitionTask = nil
    }
    
    /// Cancel the current block (discard recognition)
    func cancelBlock() {
        recognitionTask?.cancel()
        recognitionRequest?.endAudio()
        
        isBlockActive = false
        recognitionRequest = nil
        recognitionTask = nil
    }
    
    /// Check if speech recognition is available
    var isAvailable: Bool {
        return speechRecognizer?.isAvailable ?? false
    }
}

extension NativeSpeechRecognizer: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if !available {
            processingQueue.async {
                self.onError?(AudioCaptureError.invalidConfiguration)
            }
        }
    }
}

#endif

