import Foundation
import AVFoundation
@testable import SwiftDictation

/// Test fixtures and utilities for generating synthetic audio data
enum TestFixtures {
    /// Generate N milliseconds of PCM16 audio data as a sine wave
    /// - Parameters:
    ///   - durationMs: Duration in milliseconds
    ///   - sampleRate: Sample rate in Hz
    ///   - frequency: Frequency of sine wave in Hz (default: 440Hz)
    ///   - amplitude: Amplitude (0.0 to 1.0, default: 0.5)
    /// - Returns: PCM16 audio data
    static func generateSineWave(
        durationMs: Int,
        sampleRate: Double,
        frequency: Double = 440.0,
        amplitude: Float = 0.5
    ) -> Data {
        let samples = Int(sampleRate * Double(durationMs) / 1000.0)
        var data = Data()
        data.reserveCapacity(samples * 2) // 16-bit = 2 bytes per sample
        
        let amplitudeInt16 = Int16(amplitude * 32767.0)
        let phaseIncrement = 2.0 * Double.pi * frequency / sampleRate
        
        for i in 0..<samples {
            let phase = phaseIncrement * Double(i)
            let sample = Int16(sin(phase) * Double(amplitudeInt16))
            withUnsafeBytes(of: sample.littleEndian) {
                data.append(contentsOf: $0)
            }
        }
        
        return data
    }
    
    /// Generate silence (zero samples) for N milliseconds
    /// - Parameters:
    ///   - durationMs: Duration in milliseconds
    ///   - sampleRate: Sample rate in Hz
    /// - Returns: PCM16 audio data filled with zeros
    static func generateSilence(durationMs: Int, sampleRate: Double) -> Data {
        let samples = Int(sampleRate * Double(durationMs) / 1000.0)
        return Data(count: samples * 2) // 16-bit = 2 bytes per sample
    }
    
    /// Generate high-energy audio (full amplitude sine wave)
    /// - Parameters:
    ///   - durationMs: Duration in milliseconds
    ///   - sampleRate: Sample rate in Hz
    /// - Returns: PCM16 audio data with high energy
    static func generateHighEnergyAudio(durationMs: Int, sampleRate: Double) -> Data {
        return generateSineWave(durationMs: durationMs, sampleRate: sampleRate, amplitude: 1.0)
    }
    
    /// Generate low-energy audio (low amplitude sine wave)
    /// - Parameters:
    ///   - durationMs: Duration in milliseconds
    ///   - sampleRate: Sample rate in Hz
    /// - Returns: PCM16 audio data with low energy
    static func generateLowEnergyAudio(durationMs: Int, sampleRate: Double) -> Data {
        return generateSineWave(durationMs: durationMs, sampleRate: sampleRate, amplitude: 0.01)
    }
    
    /// Convert PCM16 Data to AVAudioPCMBuffer
    /// - Parameters:
    ///   - data: PCM16 audio data
    ///   - sampleRate: Sample rate in Hz
    ///   - channels: Number of channels
    /// - Returns: AVAudioPCMBuffer or nil if conversion fails
    static func dataToPCMBuffer(data: Data, sampleRate: Double, channels: Int) -> AVAudioPCMBuffer? {
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: AVAudioChannelCount(channels), interleaved: false)
        guard let audioFormat = format else { return nil }
        
        let frameCount = data.count / (2 * channels) // 16-bit = 2 bytes per sample
        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }
        
        buffer.frameLength = AVAudioFrameCount(frameCount)
        
        // Copy data to buffer
        guard let channelData = buffer.int16ChannelData else { return nil }
        data.withUnsafeBytes { bytes in
            let samples = bytes.bindMemory(to: Int16.self)
            for i in 0..<frameCount {
                channelData.pointee[i] = samples[i]
            }
        }
        
        return buffer
    }
}

/// Fake speech recognizer for testing (doesn't use Apple's Speech framework)
class FakeSpeechRecognizer {
    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?
    var onError: ((Error) -> Void)?
    
    private var isBlockActive = false
    private var partialText = ""
    private var finalText = ""
    
    /// Start a new recognition block
    func startBlock() {
        isBlockActive = true
        partialText = ""
        finalText = ""
    }
    
    /// Append audio buffer (simulates processing)
    func append(_ buffer: AVAudioPCMBuffer) {
        guard isBlockActive else { return }
        // Simulate partial transcript updates
        partialText = "Partial transcript"
        onPartial?(partialText)
    }
    
    /// Commit the current block (emit final transcript)
    func commitBlock() {
        guard isBlockActive else { return }
        finalText = "Final transcript"
        // Emit partial first, then final
        onPartial?(partialText)
        onFinal?(finalText)
        isBlockActive = false
    }
    
    /// Cancel the current block
    func cancelBlock() {
        isBlockActive = false
        partialText = ""
        finalText = ""
    }
}

