import Foundation
import AVFoundation

/// Handles chunking of audio data for streaming
internal class AudioChunker {
    private let chunkDurationMs: Int
    private let sampleRate: Double
    private var accumulatedData: Data = Data()
    private var sequenceId: Int = 0
    private var chunkStartTime: TimeInterval?
    private let deviceId: String
    
    var onChunkReady: ((Data, ChunkMetadata) -> Void)?
    
    init(chunkDurationMs: Int, sampleRate: Double, deviceId: String) {
        self.chunkDurationMs = chunkDurationMs
        self.sampleRate = sampleRate
        self.deviceId = deviceId
    }
    
    func process(buffer: AVAudioPCMBuffer, timestamp: AVAudioTime) {
        guard let channelData = buffer.int16ChannelData else { return }
        
        let frameLength = Int(buffer.frameLength)
        let bytesPerSample = 2 // 16-bit
        let dataSize = frameLength * bytesPerSample
        
        let bufferData = Data(bytes: channelData.pointee, count: dataSize)
        
        if chunkStartTime == nil {
            chunkStartTime = timestamp.sampleTime
        }
        
        accumulatedData.append(bufferData)
        
        // Check if we've accumulated enough data for a chunk
        let samplesPerChunk = Int(sampleRate * Double(chunkDurationMs) / 1000.0)
        let bytesPerChunk = samplesPerChunk * bytesPerSample
        
        if accumulatedData.count >= bytesPerChunk {
            let chunkData = accumulatedData.prefix(bytesPerChunk)
            accumulatedData.removeFirst(bytesPerChunk)
            
            let startTime = chunkStartTime ?? timestamp.sampleTime
            let duration = Double(chunkData.count) / (sampleRate * Double(bytesPerSample))
            let endTime = startTime + duration
            
            let metadata = ChunkMetadata(
                sequenceId: sequenceId,
                startTimestamp: startTime,
                endTimestamp: endTime,
                sampleRate: sampleRate,
                deviceId: deviceId
            )
            
            sequenceId += 1
            chunkStartTime = endTime
            
            onChunkReady?(Data(chunkData), metadata)
        }
    }
    
    func flush() {
        guard !accumulatedData.isEmpty, let startTime = chunkStartTime else { return }
        
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
    }
}

