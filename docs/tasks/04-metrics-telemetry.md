### 04 — Metrics and telemetry (latency, underruns, CPU)

Outcome:
- Basic instrumentation helps catch regressions and field issues. The SDK records capture→emit latency, buffer underruns, and a lightweight CPU usage gauge, exposed via logs and/or an optional callback.

Scope:
- Add an internal `MetricsLogger` to collect counters and timings.
- Emit debug logs and optionally surface a structured callback to the host app.
- Keep overhead low; metrics are lightweight and safe in release builds.

Acceptance criteria:
- Latency metric: average and p95 capture→frame delivery and capture→chunk emit are recorded.
- Buffer underruns: a counter increments when gaps exceed a threshold.
- CPU usage: a coarse gauge (e.g., once per N seconds) is sampled and emitted.
- Metrics appear in debug logs; if a callback is added, the host app receives structured events.

Key files:
- `Sources/SwiftDictation/AudioCaptureSDK.swift`
- `Sources/SwiftDictation/AudioChunker.swift`
- Add new helper: `Sources/SwiftDictation/MetricsLogger.swift`

Implementation steps:
1) Define metrics model
   - Internal structs/enums, e.g.:
     - `enum MetricsEvent { case latencyFrame(ms: Double), latencyChunk(ms: Double), underrun(count: Int), cpu(percent: Double) }`
   - Add `onMetrics: ((MetricsEvent) -> Void)?` to `AudioCaptureSDK` (optional, but recommended).

2) Capture→emit latency
   - In `handleAudioBuffer`, capture a monotonic timestamp at receive time.
   - When invoking `onFrame`, compute elapsed and record `latencyFrame`.
   - In `AudioChunker`, when `onChunkReady` fires, compute elapsed from first sample time in that chunk to callback time; record `latencyChunk`.
   - Use a moving average and a small reservoir for p95 (or compute p95 every N samples).

3) Underrun detection
   - In `AudioChunker.process`, track expected timestamp progression.
   - If the gap between successive buffers exceeds, e.g., 2× expected buffer duration, increment an underrun counter and emit an event.

4) CPU gauge
   - Sample periodically (e.g., every 2 seconds) on a background queue.
   - A simple approach: use `host_statistics` or `task_threads` if available; otherwise approximate using a moving average of processing time inside `handleAudioBuffer` divided by wall time.
   - Emit `cpu(percent:)` via logs/callback.

5) Logging and callback
   - Log with `os_log` in debug builds.
   - If `onMetrics` exists, invoke it with structured events; host app may visualize or upload.

Testing guide:
- Simulate load by running on older devices and long sessions; verify metrics continue to emit without leaks.
- Force an underrun by temporarily sleeping in the processing path; ensure the counter increments.
- Confirm p95 computation produces sensible values over a few hundred samples.

Gotchas:
- Keep all metrics collection lock-free or minimally synchronized; avoid adding jitter to the audio thread.
- Use monotonic clocks (machAbsoluteTime or ProcessInfo uptime) for latency calculations.

Definition of Done:
- Metrics are visible during local runs, and optional callback works if enabled.
- No measurable regression in latency due to metrics collection.


