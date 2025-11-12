import Foundation
import AVFoundation

/// Simple VAD implementation using energy-based detection
internal class VoiceActivityDetector {
    private let sensitivity: Float
    private let sampleRate: Double
    private var energyHistory: [Float] = []
    private let historySize = 10
    private var silenceThreshold: Float = 0.01
    
    init(sensitivity: Float, sampleRate: Double) {
        self.sensitivity = sensitivity
        self.sampleRate = sampleRate
        // Adjust threshold based on sensitivity (0.0-1.0)
        // Higher sensitivity = lower threshold (more likely to detect speech)
        self.silenceThreshold = 0.05 * (1.0 - sensitivity)
    }
    
    func process(buffer: AVAudioPCMBuffer) -> VADState {
        guard let channelData = buffer.int16ChannelData else {
            return .unknown
        }
        
        let frameLength = Int(buffer.frameLength)
        var sum: Int64 = 0
        
        // Calculate RMS energy
        for i in 0..<frameLength {
            let sample = Int64(channelData.pointee[i])
            sum += sample * sample
        }
        
        let rms = sqrt(Float(sum) / Float(frameLength)) / 32768.0
        
        // Update energy history
        energyHistory.append(rms)
        if energyHistory.count > historySize {
            energyHistory.removeFirst()
        }
        
        // Calculate average energy
        let avgEnergy = energyHistory.reduce(0, +) / Float(energyHistory.count)
        
        // Simple threshold-based detection
        if rms > silenceThreshold || avgEnergy > silenceThreshold * 0.7 {
            return .speech
        } else {
            return .silence
        }
    }
    
    func reset() {
        energyHistory.removeAll()
    }
}

