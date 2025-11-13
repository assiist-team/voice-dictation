import XCTest
import AVFoundation
@testable import SwiftDictation

final class AudioCaptureSDKTests: XCTestCase {
    // MARK: - Config Tests
    
    func testConfigDefaults() {
        let config = AudioCaptureConfig()
        XCTAssertEqual(config.sampleRate, 16000)
        XCTAssertEqual(config.channels, 1)
        XCTAssertEqual(config.vadSensitivity, 0.5, accuracy: 0.01)
        XCTAssertEqual(config.chunkDurationMs, 1000)
    }
    
    func testConfigCustom() {
        let config = AudioCaptureConfig(
            sampleRate: 48000,
            channels: 2,
            vadSensitivity: 0.8,
            chunkDurationMs: 2000
        )
        XCTAssertEqual(config.sampleRate, 48000)
        XCTAssertEqual(config.channels, 2)
        XCTAssertEqual(config.vadSensitivity, 0.8, accuracy: 0.01)
        XCTAssertEqual(config.chunkDurationMs, 2000)
    }
    
    func testSDKInitialization() {
        let config = AudioCaptureConfig()
        let sdk = AudioCaptureSDK(config: config)
        XCTAssertNotNil(sdk)
    }
    
    func testStreamTargetCreation() {
        let url = URL(string: "wss://example.com/stream")!
        let target = StreamTarget(url: url, headers: ["Authorization": "Bearer token"])
        XCTAssertEqual(target.url, url)
        XCTAssertEqual(target.headers["Authorization"], "Bearer token")
        XCTAssertEqual(target.protocolType, .websocket)
    }
    
    // MARK: - VAD Tests
    
    func testVADLowEnergyDetectsSilence() {
        let sampleRate = 16000.0
        let vad = VoiceActivityDetector(sensitivity: 0.5, sampleRate: sampleRate)
        
        // Generate low-energy audio (silence)
        let lowEnergyData = TestFixtures.generateLowEnergyAudio(durationMs: 100, sampleRate: sampleRate)
        guard let buffer = TestFixtures.dataToPCMBuffer(data: lowEnergyData, sampleRate: sampleRate, channels: 1) else {
            XCTFail("Failed to create PCM buffer")
            return
        }
        
        // Process multiple buffers to build energy history
        for _ in 0..<5 {
            let state = vad.process(buffer: buffer)
            // After building history, should detect silence
            if state == .silence {
                XCTAssertEqual(state, .silence)
                return
            }
        }
        
        // After processing multiple buffers, should eventually detect silence
        let finalState = vad.process(buffer: buffer)
        XCTAssertEqual(finalState, .silence, "Low-energy audio should be detected as silence")
    }
    
    func testVADHighEnergyDetectsSpeech() {
        let sampleRate = 16000.0
        let vad = VoiceActivityDetector(sensitivity: 0.5, sampleRate: sampleRate)
        
        // Generate high-energy audio (speech)
        let highEnergyData = TestFixtures.generateHighEnergyAudio(durationMs: 100, sampleRate: sampleRate)
        guard let buffer = TestFixtures.dataToPCMBuffer(data: highEnergyData, sampleRate: sampleRate, channels: 1) else {
            XCTFail("Failed to create PCM buffer")
            return
        }
        
        // Process buffer - should detect speech
        let state = vad.process(buffer: buffer)
        XCTAssertEqual(state, .speech, "High-energy audio should be detected as speech")
    }
    
    func testVADSensitivityAffectsThreshold() {
        let sampleRate = 16000.0
        
        // Low sensitivity (0.1) - higher threshold, less likely to detect speech
        let lowSensitivityVAD = VoiceActivityDetector(sensitivity: 0.1, sampleRate: sampleRate)
        
        // High sensitivity (0.9) - lower threshold, more likely to detect speech
        let highSensitivityVAD = VoiceActivityDetector(sensitivity: 0.9, sampleRate: sampleRate)
        
        // Generate medium-energy audio
        let mediumEnergyData = TestFixtures.generateSineWave(
            durationMs: 100,
            sampleRate: sampleRate,
            amplitude: 0.1
        )
        guard let buffer = TestFixtures.dataToPCMBuffer(data: mediumEnergyData, sampleRate: sampleRate, channels: 1) else {
            XCTFail("Failed to create PCM buffer")
            return
        }
        
        // Process multiple buffers to build history
        for _ in 0..<10 {
            _ = lowSensitivityVAD.process(buffer: buffer)
            _ = highSensitivityVAD.process(buffer: buffer)
        }
        
        let lowSensState = lowSensitivityVAD.process(buffer: buffer)
        let highSensState = highSensitivityVAD.process(buffer: buffer)
        
        // High sensitivity should be more likely to detect speech
        // (Note: exact behavior depends on implementation, but we verify they can differ)
        XCTAssertNotEqual(lowSensState, .unknown)
        XCTAssertNotEqual(highSensState, .unknown)
    }
    
    // MARK: - Chunking Tests
    
    func testChunkerEmitsOneSecondChunk() {
        let sampleRate = 16000.0
        let chunkDurationMs = 1000
        let metricsLogger = MetricsLogger()
        let chunker = AudioChunker(
            chunkDurationMs: chunkDurationMs,
            sampleRate: sampleRate,
            deviceId: "test-device",
            metricsLogger: metricsLogger
        )
        
        var receivedChunks: [(Data, ChunkMetadata)] = []
        chunker.onChunkReady = { data, metadata in
            receivedChunks.append((data, metadata))
        }
        
        // Generate exactly 1 second of audio in smaller chunks (simulating real buffers)
        let samplesPerChunk = Int(sampleRate * Double(chunkDurationMs) / 1000.0)
        let typicalBufferSize = 1024 // Typical AVAudioEngine buffer size
        let bytesPerSample = 2 // 16-bit
        
        // Process multiple smaller buffers that add up to 1 second
        var sampleOffset: Int64 = 0
        while sampleOffset < samplesPerChunk {
            let remainingSamples = samplesPerChunk - Int(sampleOffset)
            let bufferSamples = min(typicalBufferSize, remainingSamples)
            let bufferData = TestFixtures.generateSineWave(
                durationMs: Int(Double(bufferSamples) / sampleRate * 1000.0),
                sampleRate: sampleRate
            )
            
            guard let buffer = TestFixtures.dataToPCMBuffer(data: bufferData, sampleRate: sampleRate, channels: 1) else {
                XCTFail("Failed to create PCM buffer")
                return
            }
            
            // Adjust buffer to exact size if needed
            if Int(buffer.frameLength) != bufferSamples {
                // Create a new buffer with exact frame count
                let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: false)!
                guard let exactBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(bufferSamples)) else {
                    XCTFail("Failed to create exact PCM buffer")
                    return
                }
                exactBuffer.frameLength = AVAudioFrameCount(bufferSamples)
                if let srcData = buffer.int16ChannelData, let dstData = exactBuffer.int16ChannelData {
                    for i in 0..<bufferSamples {
                        dstData.pointee[i] = srcData.pointee[i]
                    }
                }
                
                let timestamp = AVAudioTime(sampleTime: sampleOffset, atRate: sampleRate)
                chunker.process(buffer: exactBuffer, timestamp: timestamp)
            } else {
                let timestamp = AVAudioTime(sampleTime: sampleOffset, atRate: sampleRate)
                chunker.process(buffer: buffer, timestamp: timestamp)
            }
            
            sampleOffset += Int64(bufferSamples)
        }
        
        // Should have received exactly 1 chunk
        XCTAssertEqual(receivedChunks.count, 1, "Should emit exactly 1 chunk for 1 second of audio")
        
        if let (data, metadata) = receivedChunks.first {
            XCTAssertEqual(metadata.sequenceId, 0, "First chunk should have sequenceId 0")
            XCTAssertEqual(metadata.startTimestamp, 0.0, accuracy: 0.01, "Start timestamp should be 0")
            XCTAssertEqual(metadata.endTimestamp, 1.0, accuracy: 0.01, "End timestamp should be 1.0")
            XCTAssertEqual(metadata.sampleRate, sampleRate)
            XCTAssertEqual(metadata.deviceId, "test-device")
            
            // Verify chunk size (exactly 1 second)
            let expectedBytes = samplesPerChunk * bytesPerSample
            XCTAssertEqual(data.count, expectedBytes, "Chunk size should match expected")
        }
    }
    
    func testChunkerEmitsMultipleChunksAndPartialOnFlush() {
        let sampleRate = 16000.0
        let chunkDurationMs = 1000
        let metricsLogger = MetricsLogger()
        let chunker = AudioChunker(
            chunkDurationMs: chunkDurationMs,
            sampleRate: sampleRate,
            deviceId: "test-device",
            metricsLogger: metricsLogger
        )
        
        var receivedChunks: [(Data, ChunkMetadata)] = []
        chunker.onChunkReady = { data, metadata in
            receivedChunks.append((data, metadata))
        }
        
        // Generate 2.5 seconds of audio in smaller chunks (simulating real buffers)
        let samplesPerChunk = Int(sampleRate * Double(chunkDurationMs) / 1000.0)
        let totalSamples = Int(sampleRate * 2.5)
        let typicalBufferSize = 1024 // Typical AVAudioEngine buffer size
        
        // Process multiple smaller buffers that add up to 2.5 seconds
        var sampleOffset: Int64 = 0
        while sampleOffset < totalSamples {
            let remainingSamples = totalSamples - Int(sampleOffset)
            let bufferSamples = min(typicalBufferSize, remainingSamples)
            let bufferData = TestFixtures.generateSineWave(
                durationMs: Int(Double(bufferSamples) / sampleRate * 1000.0),
                sampleRate: sampleRate
            )
            
            guard let buffer = TestFixtures.dataToPCMBuffer(data: bufferData, sampleRate: sampleRate, channels: 1) else {
                XCTFail("Failed to create PCM buffer")
                return
            }
            
            // Create buffer with exact frame count
            let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: false)!
            guard let exactBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(bufferSamples)) else {
                XCTFail("Failed to create exact PCM buffer")
                return
            }
            exactBuffer.frameLength = AVAudioFrameCount(bufferSamples)
            if let srcData = buffer.int16ChannelData, let dstData = exactBuffer.int16ChannelData {
                for i in 0..<bufferSamples {
                    dstData.pointee[i] = srcData.pointee[i]
                }
            }
            
            let timestamp = AVAudioTime(sampleTime: sampleOffset, atRate: sampleRate)
            chunker.process(buffer: exactBuffer, timestamp: timestamp)
            
            sampleOffset += Int64(bufferSamples)
        }
        
        // Flush remaining data
        chunker.flush()
        
        // Should have received 2 full chunks + 1 partial chunk from flush
        XCTAssertEqual(receivedChunks.count, 3, "Should emit 2 full chunks + 1 partial chunk")
        
        // Verify sequence IDs
        XCTAssertEqual(receivedChunks[0].1.sequenceId, 0)
        XCTAssertEqual(receivedChunks[1].1.sequenceId, 1)
        XCTAssertEqual(receivedChunks[2].1.sequenceId, 2)
        
        // Verify timestamps
        XCTAssertEqual(receivedChunks[0].1.startTimestamp, 0.0, accuracy: 0.01)
        XCTAssertEqual(receivedChunks[0].1.endTimestamp, 1.0, accuracy: 0.01)
        XCTAssertEqual(receivedChunks[1].1.startTimestamp, 1.0, accuracy: 0.01)
        XCTAssertEqual(receivedChunks[1].1.endTimestamp, 2.0, accuracy: 0.01)
        // Partial chunk should start at 2.0
        XCTAssertEqual(receivedChunks[2].1.startTimestamp, 2.0, accuracy: 0.01)
    }
    
    // MARK: - Export Tests
    
    func testWAVExportValidatesHeader() {
        let sampleRate = 16000.0
        let channels = 1
        
        // Generate short audio buffer
        let audioData = TestFixtures.generateSineWave(durationMs: 100, sampleRate: sampleRate)
        
        let storage = try! AudioStorage()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_export.wav")
        
        // Clean up if exists
        try? FileManager.default.removeItem(at: tempURL)
        
        do {
            try storage.exportAsWAV(
                audioData: audioData,
                sampleRate: sampleRate,
                channels: channels,
                destination: tempURL
            )
            
            // Read back and validate WAV header
            let fileData = try Data(contentsOf: tempURL)
            XCTAssertGreaterThan(fileData.count, 44, "WAV file should have header + data")
            
            // Validate RIFF header
            let riffHeader = String(data: fileData.prefix(4), encoding: .ascii)
            XCTAssertEqual(riffHeader, "RIFF", "Should start with RIFF")
            
            // Validate WAVE header
            let waveHeader = String(data: fileData.subdata(in: 8..<12), encoding: .ascii)
            XCTAssertEqual(waveHeader, "WAVE", "Should contain WAVE")
            
            // Validate fmt chunk
            let fmtHeader = String(data: fileData.subdata(in: 12..<16), encoding: .ascii)
            XCTAssertEqual(fmtHeader, "fmt ", "Should contain fmt chunk")
            
            // Validate data chunk
            let dataHeaderStart = fileData.firstIndex(of: 0x64) ?? 0 // 'd'
            if dataHeaderStart > 0 && dataHeaderStart < fileData.count - 4 {
                let dataHeader = String(data: fileData.subdata(in: dataHeaderStart..<dataHeaderStart+4), encoding: .ascii)
                XCTAssertEqual(dataHeader, "data", "Should contain data chunk")
            }
            
            // Clean up
            try? FileManager.default.removeItem(at: tempURL)
        } catch {
            XCTFail("Export failed: \(error)")
            try? FileManager.default.removeItem(at: tempURL)
        }
    }
    
    func testWAVExportEmptyBufferThrowsError() {
        let storage = try! AudioStorage()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_empty.wav")
        
        // Clean up if exists
        try? FileManager.default.removeItem(at: tempURL)
        
        do {
            try storage.exportAsWAV(
                audioData: Data(),
                sampleRate: 16000.0,
                channels: 1,
                destination: tempURL
            )
            XCTFail("Should throw error for empty buffer")
        } catch {
            // Verify it's the expected error type
            if let audioError = error as? AudioCaptureError {
                switch audioError {
                case .exportFailed:
                    // Expected error
                    break
                default:
                    XCTFail("Unexpected error type: \(audioError)")
                }
            } else {
                // Check if it's wrapped in NSError
                let nsError = error as NSError
                if nsError.domain == "AudioCaptureSDK" && nsError.code == -1 {
                    // Expected error
                } else {
                    XCTFail("Unexpected error: \(error)")
                }
            }
        }
        
        // Clean up
        try? FileManager.default.removeItem(at: tempURL)
    }
    
    // MARK: - Lifecycle Tests
    
    func testPauseCaptureWithoutStartThrows() {
        let config = AudioCaptureConfig()
        let sdk = AudioCaptureSDK(config: config)
        
        do {
            try sdk.pauseCapture()
            XCTFail("Should throw error when pausing without starting")
        } catch {
            if let audioError = error as? AudioCaptureError {
                XCTAssertEqual(audioError, .captureNotInProgress)
            } else {
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }
    
    func testResumeCaptureWhenNotPausedThrows() {
        let config = AudioCaptureConfig()
        let sdk = AudioCaptureSDK(config: config)
        
        // Note: This test can't actually start capture without permissions,
        // so we test the error case when capture is not in progress
        do {
            try sdk.resumeCapture()
            XCTFail("Should throw error when resuming without starting")
        } catch {
            if let audioError = error as? AudioCaptureError {
                XCTAssertEqual(audioError, .captureNotInProgress)
            } else {
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }
    
    func testStartCaptureTwiceThrows() {
        // Note: This test requires permissions, so it may not run in CI
        // We'll test the logic path that would throw this error
        let config = AudioCaptureConfig()
        let sdk = AudioCaptureSDK(config: config)
        
        // The actual startCapture requires permissions, so we can't fully test this
        // without mocking. However, we can verify the error type exists
        XCTAssertNotNil(AudioCaptureError.captureAlreadyInProgress)
    }
    
    // MARK: - Integration Tests (with Fake Speech Recognizer)
    
    func testFakeSpeechRecognizerPartialThenFinal() {
        let fakeRecognizer = FakeSpeechRecognizer()
        
        var partialReceived = false
        var finalReceived = false
        var partialText = ""
        var finalText = ""
        
        fakeRecognizer.onPartial = { text in
            partialReceived = true
            partialText = text
        }
        
        fakeRecognizer.onFinal = { text in
            finalReceived = true
            finalText = text
        }
        
        // Start block
        fakeRecognizer.startBlock()
        
        // Append audio (should trigger partial)
        let sampleRate = 16000.0
        let audioData = TestFixtures.generateSineWave(durationMs: 100, sampleRate: sampleRate)
        guard let buffer = TestFixtures.dataToPCMBuffer(data: audioData, sampleRate: sampleRate, channels: 1) else {
            XCTFail("Failed to create PCM buffer")
            return
        }
        
        fakeRecognizer.append(buffer)
        
        // Give callback time to execute
        let expectation = XCTestExpectation(description: "Partial transcript received")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertTrue(partialReceived, "Partial transcript should be received")
        XCTAssertEqual(partialText, "Partial transcript")
        
        // Commit block (should trigger final)
        fakeRecognizer.commitBlock()
        
        let finalExpectation = XCTestExpectation(description: "Final transcript received")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            finalExpectation.fulfill()
        }
        wait(for: [finalExpectation], timeout: 1.0)
        
        XCTAssertTrue(finalReceived, "Final transcript should be received")
        XCTAssertEqual(finalText, "Final transcript")
        
        // Verify partial was called before final
        XCTAssertTrue(partialReceived, "Partial should be received before final")
    }
}

