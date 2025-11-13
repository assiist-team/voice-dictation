### 03 — Raw audio persistence and export utilities

Outcome:
- When enabled via config, raw audio is persisted securely to app storage and excluded from backups. The SDK can export recordings to WAV reliably, with clear behavior for empty buffers and unsupported formats.

Scope:
- Move persistence to Application Support with file protection and “exclude from backup”.
- Keep in-memory accumulation for the current session; persist on stop if `persistRawAudio == true`.
- Ensure WAV export works with both in-memory and persisted data paths.

Acceptance criteria:
- On `stopCapture()`, if `persistRawAudio == true` and data exists, a `.pcm` file is written under Application Support in a `SwiftDictation` subdirectory.
- The directory is excluded from iCloud backups and uses sensible file protection on iOS.
- `exportRecording(.wav, destination:)` writes a valid WAV file and returns `ExportResult`.
- Exporting `.m4a` throws a clear “not implemented” error (current behavior is acceptable).

Key files:
- `Sources/SwiftDictation/AudioStorage.swift`
- `Sources/SwiftDictation/AudioCaptureSDK.swift`

Implementation steps:
1) Storage location and protection
   - Change base directory from `.documentDirectory` to `.applicationSupportDirectory`.
   - Ensure the directory exists; mark it excluded from backups:
     - Set `URLIsExcludedFromBackupKey = true` via `setResourceValue`.
   - On iOS, set file protection on created files if needed (e.g., `.completeUntilFirstUserAuthentication`) using `setAttributes`.

2) Naming and structure
   - Keep filenames stable: `"{sessionId}_raw_{timestamp}.pcm"` and `"{sessionId}_processed_{timestamp}.pcm"`.
   - Consider adding a lightweight session index JSON for future listing (non-blocking for V1).

3) Persist on stop
   - In `AudioCaptureSDK.stopCapture()`, raw audio is already persisted behind the flag; ensure this is robust and handles empty data.
   - Optionally also persist processed audio via `saveProcessedAudio` if we want parity (not required for V1).

4) WAV export
   - The current `exportAsWAV` helper writes headers correctly; keep as-is.
   - Add basic parameter validation (channels > 0, sampleRate > 0) and throw `invalidAudioFormat` when invalid.
   - Ensure `exportRecording` chooses `processedAudioData` when available, otherwise raw.

5) Example usage (readme/API)
   - Document that persistence is opt-in in `AudioCaptureConfig.persistRawAudio`.
   - Show example of exporting to a temp URL and sharing the file.

Testing guide:
- Unit:
  - Verify directory creation under Application Support and backup exclusion flag set.
  - Write/read roundtrip for `.pcm`; header validation for `.wav`.
  - Error on empty buffer export.
- Manual:
  - Enable persistence, record a short clip, stop; inspect app container for saved files.
  - Export to `.wav` and open in a standard player; confirm duration matches.

Gotchas:
- Don’t write files on a background thread that might be suspended mid-write; ensure writes complete before app background if possible.
- For large files, consider streaming export in future versions; V1 can buffer in-memory for typical dictation lengths.

Definition of Done:
- Persistence path moved to Application Support, with backup exclusion and protection.
- WAV export succeeds and produces valid files. Errors are clear and typed.


