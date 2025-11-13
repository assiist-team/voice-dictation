### 02 — Interruptions and permission recovery (iOS)

Outcome:
- The SDK gracefully handles audio interruptions and route changes, and recovers the session when possible. Permission changes are detected and surfaced clearly to the app.

Scope:
- Observe and handle `AVAudioSession` interruptions and route changes.
- Re-activate the audio session and restart the engine when appropriate.
- Surface a clear error signal on interruption and a recovery signal when resumed.
- Ensure permission checks cover both mic and speech recognition on iOS.

Acceptance criteria:
- When an interruption begins (e.g., phone call), capture pauses and an interruption error is surfaced.
- When the interruption ends, the SDK re-activates and resumes capture if it was previously recording.
- On route change (e.g., headphones unplugged, Bluetooth handoff), capture continues or cleanly restarts with minimal user impact.
- Permission loss results in a clear error and prevents capture start until restored.

Key files:
- `Sources/SwiftDictation/AudioCaptureSDK.swift`
- `Sources/SwiftDictation/AudioCaptureEngine.swift`
- `Sources/SwiftDictation/AudioCaptureErrors.swift` (already contains `.deviceInterrupted`)

Implementation steps:
1) Add observers (iOS only)
   - Register in `AudioCaptureSDK.startCapture` (and unregister on `stopCapture()`):
     - `AVAudioSession.interruptionNotification`
     - `AVAudioSession.routeChangeNotification`
     - `AVAudioSession.mediaServicesWereLost`
     - `AVAudioSession.mediaServicesWereReset`

2) Handle interruptions
   - On `.began`: set an internal `interrupted = true`, pause the engine if needed, and call `onError?(AudioCaptureError.deviceInterrupted)`.
   - On `.ended`: try `AVAudioSession.sharedInstance().setActive(true)`, then:
     - If we were capturing before, call `captureEngine.resume()` and set `interrupted = false`.
     - If resume fails, surface `onError`.

3) Handle route changes
   - On route change (e.g., `newDeviceAvailable`, `oldDeviceUnavailable`):
     - Re-apply preferred input based on `config.bluetoothPreferred`.
     - If format/sample rate changed, stop engine, re-run `setup()`, then start.
     - Ensure taps are not double-installed (they are installed in `setup()`).

4) Media services lost/reset
   - On lost/reset, treat as a hard interruption:
     - Stop engine cleanly, reconfigure session, call `setup()` and start again if we were previously recording.

5) Permissions recovery
   - `requestPermissions()` (iOS): also request Apple Speech authorization and map to `.granted/.denied`.
   - `checkPermissions()`: read mic permission; optionally cache speech authorization and expose a combined readiness check (mic + speech).
   - If permission is denied, throw `permissionDenied` early in `startCapture`.

6) Example app
   - Show a brief UI banner or error state on interruption; resume automatically when possible.
   - Ensure the UI state machine (Idle/Listening/Paused/Processing) stays consistent during interruptions.

Testing guide:
- Simulate interruption in Simulator (Incoming call) or on-device:
  - Observe error callback, then automatic resume on end.
- Plug/unplug headphones or switch Bluetooth routes:
  - Verify capture continues; if engine restarts, the app should see a brief pause but no crash.
- Revoke mic or speech permission and try `startCapture()`:
  - Receive `.permissionDenied` and no engine start.

Gotchas:
- Don’t call `installTap` more than once without removing the previous one (handled in `stop()`).
- Always activate the session before restarting the engine after interruptions.
- Dispatch notifications onto a serial queue if you mutate engine state to avoid races.

Definition of Done:
- Interruption and route change flows work reliably across devices.
- Minimal regressions to latency and no crashes on noisy route change sequences.
- Example app demonstrates a clean UX during interruptions.


