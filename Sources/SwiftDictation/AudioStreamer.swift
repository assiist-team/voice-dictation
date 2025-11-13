import Foundation

/// Handles streaming audio chunks to a remote server
internal class AudioStreamer {
    private var webSocketTask: URLSessionWebSocketTask?
    private var isStreaming = false
    private let target: StreamTarget
    
    var onChunkSent: ((ChunkMetadata) -> Void)?
    var onError: ((Error) -> Void)?
    
    init(target: StreamTarget) {
        self.target = target
    }
    
    func start() throws {
        guard !isStreaming else {
            throw AudioCaptureError.captureAlreadyInProgress
        }
        
        switch target.protocolType {
        case .websocket:
            try startWebSocket()
        case .grpc:
            throw AudioCaptureError.invalidConfiguration // gRPC not implemented yet
        }
    }
    
    private func startWebSocket() throws {
        var request = URLRequest(url: target.url)
        request.timeoutInterval = 5
        
        // Add custom headers
        for (key, value) in target.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        isStreaming = true
        
        // Start receiving messages (for ACKs)
        receiveMessage()
    }
    
    func sendChunk(_ data: Data, metadata: ChunkMetadata) throws {
        guard isStreaming, let webSocketTask = webSocketTask else {
            throw AudioCaptureError.captureNotInProgress
        }
        
        // Create message with metadata and audio data
        let payload: [String: Any] = [
            "sequenceId": metadata.sequenceId,
            "startTimestamp": metadata.startTimestamp,
            "endTimestamp": metadata.endTimestamp,
            "sampleRate": metadata.sampleRate,
            "deviceId": metadata.deviceId,
            "audioData": data.base64EncodedString()
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw AudioCaptureError.streamingFailed(NSError(domain: "AudioStreamer", code: -1))
        }
        
        let socketMessage = URLSessionWebSocketTask.Message.string(jsonString)
        webSocketTask.send(socketMessage) { [weak self] error in
            if let error = error {
                self?.onError?(AudioCaptureError.streamingFailed(error))
            } else {
                self?.onChunkSent?(metadata)
            }
        }
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                // Handle ACK or other server messages
                switch message {
                case .string(_):
                    // Parse ACK if needed
                    break
                case .data(_):
                    // Handle binary ACK if needed
                    break
                @unknown default:
                    break
                }
                // Continue receiving
                self?.receiveMessage()
            case .failure(let error):
                self?.onError?(AudioCaptureError.streamingFailed(error))
            }
        }
    }
    
    func stop() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isStreaming = false
    }
}

