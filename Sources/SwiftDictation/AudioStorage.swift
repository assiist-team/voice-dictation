import Foundation
import AVFoundation

/// Handles local storage of raw and processed audio
internal class AudioStorage {
    private let storageDirectory: URL
    
    init() throws {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        storageDirectory = documentsPath.appendingPathComponent("SwiftDictation", isDirectory: true)
        
        // Create directory if it doesn't exist
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
    }
    
    func saveRawAudio(_ data: Data, sessionId: String) throws -> URL {
        let filename = "\(sessionId)_raw_\(Date().timeIntervalSince1970).pcm"
        let fileURL = storageDirectory.appendingPathComponent(filename)
        try data.write(to: fileURL)
        return fileURL
    }
    
    func saveProcessedAudio(_ data: Data, sessionId: String) throws -> URL {
        let filename = "\(sessionId)_processed_\(Date().timeIntervalSince1970).pcm"
        let fileURL = storageDirectory.appendingPathComponent(filename)
        try data.write(to: fileURL)
        return fileURL
    }
    
    func exportAsWAV(audioData: Data, sampleRate: Double, channels: Int, destination: URL) throws {
        let file = try FileHandle(forWritingTo: destination)
        defer { try? file.close() }
        
        // WAV header
        let sampleRateInt = UInt32(sampleRate)
        let channelsUInt16 = UInt16(channels)
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRateInt * UInt32(channelsUInt16) * UInt32(bitsPerSample) / 8
        let blockAlign = channelsUInt16 * bitsPerSample / 8
        let dataSize = UInt32(audioData.count)
        let fileSize = 36 + dataSize
        
        var header = Data()
        header.append("RIFF".data(using: .ascii)!)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(fileSize).littleEndian) { Data($0) })
        header.append("WAVE".data(using: .ascii)!)
        header.append("fmt ".data(using: .ascii)!)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) }) // fmt chunk size
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) }) // audio format (PCM)
        header.append(contentsOf: withUnsafeBytes(of: channelsUInt16.littleEndian) { Data($0) })
        header.append(contentsOf: withUnsafeBytes(of: sampleRateInt.littleEndian) { Data($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(byteRate).littleEndian) { Data($0) })
        header.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        header.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        header.append("data".data(using: .ascii)!)
        header.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        
        try file.write(contentsOf: header)
        try file.write(contentsOf: audioData)
    }
}

