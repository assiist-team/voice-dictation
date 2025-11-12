import Foundation
import AVFoundation

/// Audio preprocessing pipeline
internal class AudioPreprocessor {
    private let config: AudioCaptureConfig
    private var highPassFilter: AVAudioUnitEQ?
    private var agcNode: AVAudioUnitTimePitch?
    
    init(config: AudioCaptureConfig) {
        self.config = config
    }
    
    func setup(audioEngine: AVAudioEngine) throws {
        // High-pass filter
        if config.highPassFilterCutoff > 0 {
            let highPass = AVAudioUnitEQ(numberOfBands: 1)
            let filterParams = highPass.bands[0]
            filterParams.filterType = .highPass
            filterParams.frequency = Float(config.highPassFilterCutoff)
            filterParams.bypass = false
            self.highPassFilter = highPass
            audioEngine.attach(highPass)
            
            if let inputNode = audioEngine.inputNode {
                audioEngine.connect(inputNode, to: highPass, format: nil)
            }
        }
        
        // AGC (Automatic Gain Control) - simplified using time pitch unit
        // Note: For production, consider using AVAudioUnitVarispeed or custom AGC
        if config.enableAGC {
            // AVAudioUnit doesn't have built-in AGC, so we'll handle this in processing
        }
    }
    
    func process(buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        // Apply noise suppression (simplified - in production use RNNoise or AVAudioUnitEffect)
        // For now, we'll apply basic filtering
        
        // AGC processing
        if config.enableAGC {
            applyAGC(to: buffer)
        }
        
        return buffer
    }
    
    private func applyAGC(to buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.int16ChannelData else { return }
        
        let frameLength = Int(buffer.frameLength)
        var maxAmplitude: Int16 = 0
        
        // Find peak amplitude
        for i in 0..<frameLength {
            let sample = abs(channelData.pointee[i])
            if sample > maxAmplitude {
                maxAmplitude = sample
            }
        }
        
        // Apply gain if needed (target ~80% of max)
        if maxAmplitude > 0 && maxAmplitude < 26214 { // ~80% of Int16.max
            let targetLevel: Int16 = 26214
            let gain = Float(targetLevel) / Float(maxAmplitude)
            let clampedGain = min(gain, 2.0) // Cap at 2x
            
            for i in 0..<frameLength {
                let sample = channelData.pointee[i]
                channelData.pointee[i] = Int16(Float(sample) * clampedGain)
            }
        }
    }
}

