# Manual QA Checklist

This checklist should be executed on physical devices to validate behavior across different hardware configurations and scenarios.

## Test Devices

- [ ] iPhone 12 (or similar)
- [ ] iPhone 15 (or similar)
- [ ] Additional device: _______________

## Test Routes

For each device, test with:
- [ ] Built-in microphone
- [ ] Wired headset (if available)
- [ ] Bluetooth device (AirPods or similar)

## Test Scenarios

### 1. Basic Lifecycle Operations

#### Start/Pause/Resume/Stop Sequence
- [ ] Start capture successfully
- [ ] Pause capture (verify audio stops)
- [ ] Resume capture (verify audio resumes)
- [ ] Stop capture (verify clean shutdown)
- [ ] Verify no crashes or memory leaks

#### Error Cases
- [ ] Attempt to pause without starting → should throw `captureNotInProgress`
- [ ] Attempt to resume when not paused → should throw `captureNotInProgress`
- [ ] Attempt to start twice → should throw `captureAlreadyInProgress`
- [ ] Verify error messages are clear and actionable

### 2. Dictation Block Management

#### Commit/Cancel Sequences
- [ ] Start capture
- [ ] Speak some words
- [ ] Call `commitCurrentBlock()` → verify `onFinalTranscript` fires
- [ ] Verify new block starts automatically
- [ ] Speak more words
- [ ] Call `cancelCurrentBlock()` → verify no final transcript
- [ ] Verify new block starts automatically

#### Transcript Callbacks
- [ ] Verify `onPartialTranscript` fires during speech
- [ ] Verify `onFinalTranscript` fires after commit
- [ ] Verify partial fires before final
- [ ] Verify transcript text is accurate

### 3. Interruption Handling

#### Incoming Call Interruption
- [ ] Start capture
- [ ] Initiate incoming call (from another device)
- [ ] Verify capture pauses automatically
- [ ] Verify `onError` callback fires with `deviceInterrupted`
- [ ] End call
- [ ] Verify `onInterruptionRecovered` callback fires
- [ ] Verify capture resumes automatically (if configured)

#### Route Changes
- [ ] Start capture with built-in mic
- [ ] Plug in wired headset → verify route change handled
- [ ] Unplug headset → verify route change handled
- [ ] Connect Bluetooth device → verify route change handled
- [ ] Disconnect Bluetooth device → verify route change handled
- [ ] Verify no crashes during route changes
- [ ] Verify audio continues after route change

### 4. Long Session Stability

#### Extended Capture Session
- [ ] Start capture
- [ ] Run for ≥10 minutes continuously
- [ ] Monitor memory usage (should remain stable)
- [ ] Verify no crashes or freezes
- [ ] Verify audio quality remains consistent
- [ ] Stop capture cleanly

#### Memory and Performance
- [ ] Check memory usage before capture
- [ ] Check memory usage during capture (after 5 minutes)
- [ ] Check memory usage after capture stops
- [ ] Verify memory is released after stop
- [ ] Monitor CPU usage (should be reasonable)

### 5. Audio Quality

#### Different Input Routes
- [ ] Built-in mic: verify clear audio capture
- [ ] Wired headset: verify clear audio capture
- [ ] Bluetooth device: verify clear audio capture
- [ ] Compare quality across routes

#### Background Noise Handling
- [ ] Test in quiet environment
- [ ] Test in noisy environment
- [ ] Verify VAD correctly distinguishes speech from noise
- [ ] Verify noise suppression works (if enabled)

### 6. Export Functionality

#### WAV Export
- [ ] Capture audio for 5 seconds
- [ ] Export as WAV format
- [ ] Verify file is created
- [ ] Verify file can be played back
- [ ] Verify audio quality matches original
- [ ] Verify WAV header is valid (check with audio tool)

#### PCM16 Export
- [ ] Capture audio for 5 seconds
- [ ] Export as PCM16 format
- [ ] Verify file is created
- [ ] Verify file size matches expected (samples × 2 bytes)

### 7. Streaming (if applicable)

- [ ] Start capture
- [ ] Start streaming to test endpoint
- [ ] Verify chunks are sent
- [ ] Verify `onChunkSent` callback fires
- [ ] Verify chunk metadata is correct
- [ ] Stop streaming
- [ ] Verify clean shutdown

### 8. Permissions

- [ ] Test with microphone permission denied
- [ ] Test with speech recognition permission denied
- [ ] Test with both permissions granted
- [ ] Verify error messages are clear
- [ ] Verify permission requests work correctly

## Test Results

### Device 1: _______________
- Date tested: _______________
- iOS version: _______________
- Overall result: ☐ Pass ☐ Fail
- Notes: _______________

### Device 2: _______________
- Date tested: _______________
- iOS version: _______________
- Overall result: ☐ Pass ☐ Fail
- Notes: _______________

### Device 3: _______________
- Date tested: _______________
- iOS version: _______________
- Overall result: ☐ Pass ☐ Fail
- Notes: _______________

## Known Issues

List any issues discovered during testing:

1. _______________
2. _______________
3. _______________

## Test Environment

- Tester name: _______________
- Test date range: _______________
- Test duration: _______________
- Additional notes: _______________

