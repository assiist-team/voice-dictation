import Foundation
import os.log

#if os(iOS) || os(macOS)
import Darwin
#endif

/// Metrics event types emitted by the SDK
public enum MetricsEvent {
    /// Frame latency: time from capture to frame delivery (milliseconds)
    case latencyFrame(ms: Double, p95: Double?)
    
    /// Chunk latency: time from first sample in chunk to chunk emit (milliseconds)
    case latencyChunk(ms: Double, p95: Double?)
    
    /// Buffer underrun detected (total count)
    case underrun(count: Int)
    
    /// CPU usage percentage (sampled periodically)
    case cpu(percent: Double)
}

/// Internal metrics logger for collecting and reporting SDK metrics
internal class MetricsLogger {
    private let logger = Logger(subsystem: "com.swiftdictation", category: "metrics")
    
    // Latency tracking
    private var frameLatencies: [Double] = []
    private var chunkLatencies: [Double] = []
    private let maxSamples = 1000 // Keep last 1000 samples for p95
    private var frameLatencySum: Double = 0
    private var chunkLatencySum: Double = 0
    private var frameLatencyCount: Int = 0
    private var chunkLatencyCount: Int = 0
    
    // Underrun tracking
    private var underrunCount: Int = 0
    private let underrunThresholdMultiplier: Double = 2.0 // 2x expected buffer duration
    
    // CPU tracking
    private var cpuSamplingTimer: DispatchSourceTimer?
    private let cpuSamplingInterval: TimeInterval = 2.0 // Sample every 2 seconds
    private var lastCpuTime: TimeInterval = 0
    private var lastWallTime: TimeInterval = 0
    
    // Thread-safe access
    private let metricsQueue = DispatchQueue(label: "com.swiftdictation.metrics", qos: .utility)
    
    // Callback for metrics events
    var onMetricsEvent: ((MetricsEvent) -> Void)?
    
    init() {
        #if os(iOS) || os(macOS)
        lastWallTime = ProcessInfo.processInfo.systemUptime
        lastCpuTime = getCpuTime()
        #endif
    }
    
    deinit {
        stopCPUSampling()
    }
    
    // MARK: - Latency Tracking
    
    /// Record frame latency (capture to frame delivery)
    func recordFrameLatency(_ latencyMs: Double) {
        metricsQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.frameLatencySum += latencyMs
            self.frameLatencyCount += 1
            
            // Maintain reservoir for p95
            self.frameLatencies.append(latencyMs)
            if self.frameLatencies.count > self.maxSamples {
                self.frameLatencies.removeFirst()
            }
            
            let average = self.frameLatencySum / Double(self.frameLatencyCount)
            let p95 = self.computeP95(self.frameLatencies)
            
            let event = MetricsEvent.latencyFrame(ms: average, p95: p95)
            self.emitEvent(event)
        }
    }
    
    /// Record chunk latency (first sample to chunk emit)
    func recordChunkLatency(_ latencyMs: Double) {
        metricsQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.chunkLatencySum += latencyMs
            self.chunkLatencyCount += 1
            
            // Maintain reservoir for p95
            self.chunkLatencies.append(latencyMs)
            if self.chunkLatencies.count > self.maxSamples {
                self.chunkLatencies.removeFirst()
            }
            
            let average = self.chunkLatencySum / Double(self.chunkLatencyCount)
            let p95 = self.computeP95(self.chunkLatencies)
            
            let event = MetricsEvent.latencyChunk(ms: average, p95: p95)
            self.emitEvent(event)
        }
    }
    
    // MARK: - Underrun Detection
    
    /// Check for buffer underrun based on timestamp gap
    func checkUnderrun(expectedBufferDuration: TimeInterval, actualGap: TimeInterval) {
        let threshold = expectedBufferDuration * underrunThresholdMultiplier
        
        if actualGap > threshold {
            metricsQueue.async { [weak self] in
                guard let self = self else { return }
                self.underrunCount += 1
                let event = MetricsEvent.underrun(count: self.underrunCount)
                self.emitEvent(event)
            }
        }
    }
    
    // MARK: - CPU Usage
    
    /// Start periodic CPU sampling
    func startCPUSampling() {
        stopCPUSampling() // Ensure no duplicate timers
        
        let timer = DispatchSource.makeTimerSource(queue: metricsQueue)
        timer.schedule(deadline: .now() + cpuSamplingInterval, repeating: cpuSamplingInterval)
        timer.setEventHandler { [weak self] in
            self?.sampleCPU()
        }
        timer.resume()
        cpuSamplingTimer = timer
    }
    
    /// Stop CPU sampling
    func stopCPUSampling() {
        cpuSamplingTimer?.cancel()
        cpuSamplingTimer = nil
    }
    
    /// Sample CPU usage
    private func sampleCPU() {
        #if os(iOS) || os(macOS)
        let currentWallTime = ProcessInfo.processInfo.systemUptime
        let currentCpuTime = getCpuTime()
        
        let wallDelta = currentWallTime - lastWallTime
        let cpuDelta = currentCpuTime - lastCpuTime
        
        guard wallDelta > 0 else {
            lastWallTime = currentWallTime
            lastCpuTime = currentCpuTime
            return
        }
        
        let cpuPercent = (cpuDelta / wallDelta) * 100.0
        lastWallTime = currentWallTime
        lastCpuTime = currentCpuTime
        
        let event = MetricsEvent.cpu(percent: min(100.0, max(0.0, cpuPercent)))
        emitEvent(event)
        #endif
    }
    
    #if os(iOS) || os(macOS)
    /// Get CPU time for current process
    private func getCpuTime() -> TimeInterval {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else {
            return 0
        }
        
        // Convert to seconds (user_time + system_time)
        let totalTime = Double(info.user_time.seconds) + Double(info.user_time.microseconds) / 1_000_000.0
        let systemTime = Double(info.system_time.seconds) + Double(info.system_time.microseconds) / 1_000_000.0
        return totalTime + systemTime
    }
    #endif
    
    // MARK: - Event Emission
    
    /// Emit a metrics event (log and callback)
    private func emitEvent(_ event: MetricsEvent) {
        // Log with os_log
        #if DEBUG
        switch event {
        case .latencyFrame(let ms, let p95):
            if let p95 = p95 {
                logger.debug("Frame latency: avg=\(String(format: "%.2f", ms))ms, p95=\(String(format: "%.2f", p95))ms")
            } else {
                logger.debug("Frame latency: avg=\(String(format: "%.2f", ms))ms")
            }
        case .latencyChunk(let ms, let p95):
            if let p95 = p95 {
                logger.debug("Chunk latency: avg=\(String(format: "%.2f", ms))ms, p95=\(String(format: "%.2f", p95))ms")
            } else {
                logger.debug("Chunk latency: avg=\(String(format: "%.2f", ms))ms")
            }
        case .underrun(let count):
            logger.warning("Buffer underrun detected: total count=\(count)")
        case .cpu(let percent):
            logger.debug("CPU usage: \(String(format: "%.1f", percent))%")
        }
        #endif
        
        // Invoke callback if set
        onMetricsEvent?(event)
    }
    
    // MARK: - Helper Methods
    
    /// Compute p95 from sorted array
    private func computeP95(_ values: [Double]) -> Double? {
        guard values.count >= 20 else { return nil } // Need at least 20 samples for meaningful p95
        
        let sorted = values.sorted()
        let index = Int(Double(sorted.count) * 0.95)
        return sorted[min(index, sorted.count - 1)]
    }
    
    /// Reset all metrics
    func reset() {
        metricsQueue.async { [weak self] in
            guard let self = self else { return }
            self.frameLatencies.removeAll()
            self.chunkLatencies.removeAll()
            self.frameLatencySum = 0
            self.chunkLatencySum = 0
            self.frameLatencyCount = 0
            self.chunkLatencyCount = 0
            self.underrunCount = 0
        }
    }
}

