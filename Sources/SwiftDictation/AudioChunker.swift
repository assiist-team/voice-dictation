import Foundation
import AVFoundation

/// Handles chunking of audio data for streaming
internal class AudioChunker {
    private let chunkDurationMs: Int
    private let sampleRate: Double
    private var accumulatedData: Data = Data()
    private var sequenceId: Int = 0
    private var chunkStartTime: AVAudioFramePosition? // Sample time when chunk started
    private var chunkFirstSampleWallTime: TimeInterval? // Wall time when first sample of chunk arrived
    private let deviceId: String
    private weak var metricsLogger: MetricsLogger?
    
    // Underrun detection
    private var lastBufferTimestamp: AVAudioFramePosition?
    private var expectedBufferDuration: TimeInterval
    
    var onChunkReady: ((Data, ChunkMetadata) -> Void)?
    
    init(chunkDurationMs: Int, sampleRate: Double, deviceId: String, metricsLogger: MetricsLogger?) {
        self.chunkDurationMs = chunkDurationMs
        self.sampleRate = sampleRate
        self.deviceId = deviceId
        self.metricsLogger = metricsLogger
        
        // Calculate expected buffer duration (assuming typical buffer size of ~1024 frames)
        // This is approximate; actual buffer size may vary
        let typicalBufferFrames: Double = 1024.0
        self.expectedBufferDuration = typicalBufferFrames / sampleRate
    }
    
    func process(buffer: AVAudioPCMBuffer, timestamp: AVAudioTime) {
        guard let channelData = buffer.int16ChannelData else { return }
        
        let frameLength = Int(buffer.frameLength)
        let bytesPerSample = 2 // 16-bit
        let dataSize = frameLength * bytesPerSample
        
        let bufferData = Data(bytes: channelData.pointee, count: dataSize)
        let currentTimestamp = timestamp.sampleTime
        
        // Check for underrun (gap detection)
        if let lastTimestamp = lastBufferTimestamp {
            // Convert sample gap to time gap
            let sampleGap = Double(currentTimestamp - lastTimestamp)
            let timeGap = sampleGap / sampleRate
            metricsLogger?.checkUnderrun(expectedBufferDuration: expectedBufferDuration, actualGap: timeGap)
        }
        lastBufferTimestamp = currentTimestamp
        
        // Track first sample wall time for chunk latency
        if chunkStartTime == nil {
            chunkStartTime = currentTimestamp
            chunkFirstSampleWallTime = ProcessInfo.processInfo.systemUptime
        }
        
        accumulatedData.append(bufferData)
        
        // Check if we've accumulated enough data for a chunk
        let samplesPerChunk = Int(sampleRate * Double(chunkDurationMs) / 1000.0)
        let bytesPerChunk = samplesPerChunk * bytesPerSample
        
        if accumulatedData.count >= bytesPerChunk {
            let chunkData = accumulatedData.prefix(bytesPerChunk)
            accumulatedData.removeFirst(bytesPerChunk)
            
            let startTime = Double(chunkStartTime ?? currentTimestamp) / sampleRate
            let duration = Double(chunkData.count) / (sampleRate * Double(bytesPerSample))
            let endTime = startTime + duration
            
            // Measure chunk latency (first sample wall time to emit)
            if let firstSampleWallTime = chunkFirstSampleWallTime {
                let chunkEmitTime = ProcessInfo.processInfo.systemUptime
                let chunkLatencyMs = (chunkEmitTime - firstSampleWallTime) * 1000.0
                metricsLogger?.recordChunkLatency(chunkLatencyMs)
            }
            
            let metadata = ChunkMetadata(
                sequenceId: sequenceId,
                startTimestamp: startTime,
                endTimestamp: endTime,
                sampleRate: sampleRate,
                deviceId: deviceId
            )
            
            sequenceId += 1
            chunkStartTime = AVAudioFramePosition(endTime * sampleRate) // Convert back to sample time
            chunkFirstSampleWallTime = nil // Reset for next chunk
            
            onChunkReady?(Data(chunkData), metadata)
        }
    }
    
    func flush() {
        guard !accumulatedData.isEmpty, let startSampleTime = chunkStartTime else { return }
        
        let startTime = Double(startSampleTime) / sampleRate
        let duration = Double(accumulatedData.count) / (sampleRate * 2.0) // 16-bit = 2 bytes
        let endTime = startTime + duration
        
        let metadata = ChunkMetadata(
            sequenceId: sequenceId,
            startTimestamp: startTime,
            endTimestamp: endTime,
            sampleRate: sampleRate,
            deviceId: deviceId
        )
        
        sequenceId += 1
        onChunkReady?(Data(accumulatedData), metadata)
        accumulatedData.removeAll()
        chunkStartTime = nil
    }
    
    func reset() {
        accumulatedData.removeAll()
        sequenceId = 0
        chunkStartTime = nil
        chunkFirstSampleWallTime = nil
        lastBufferTimestamp = nil
    }
}

