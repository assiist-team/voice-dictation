import XCTest
@testable import SwiftDictation

final class AudioCaptureSDKTests: XCTestCase {
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
}

