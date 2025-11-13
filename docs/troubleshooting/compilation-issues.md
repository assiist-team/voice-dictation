# Compilation issues discovered during build

During a recent `swift build` run, the following **errors** were observed. Each entry includes the error message, file location, and a suggested fix.

---

- **File:** `Sources/SwiftDictation/AudioPreprocessor.swift`
  - **Error:** `initializer for conditional binding must have Optional type, not 'AVAudioInputNode'`
  - **Explanation:** The code used `if let inputNode = audioEngine.inputNode { ... }` but `audioEngine.inputNode` is a non-optional `AVAudioInputNode`. The compiler rejects optional binding on a non-optional value.
  - **Suggested fix:** Remove the optional binding and use the value directly, or use a plain `let`/`guard let` if you make it optional. Example change:

    ```swift
    // Replace
    if let inputNode = audioEngine.inputNode {
        audioEngine.connect(inputNode, to: highPass, format: nil)
    }

    // With
    let inputNode = audioEngine.inputNode
    audioEngine.connect(inputNode, to: highPass, format: nil)
    ```

    Or, if platform differences necessitate optionality, explicitly make the expression optional before binding.

---

- **File:** `Sources/SwiftDictation/AudioStorage.swift`
  - **Error:** `cannot use mutating member on immutable value: 'storageDirectory' is a 'let' constant`
  - **Explanation:** The code declares `storageDirectory` as a `let` constant and then calls `storageDirectory.setResourceValues(...)`, which is a mutating method on `URL`. That is not allowed for a `let` constant.
  - **Suggested fix:** Change `private let storageDirectory: URL` to `private var storageDirectory: URL` (or avoid calling mutating methods on the stored `URL` by creating a mutable copy first). Example:

    ```swift
    // Replace
    private let storageDirectory: URL

    // With
    private var storageDirectory: URL
    ```

    Or perform `var resourceURL = storageDirectory; try resourceURL.setResourceValues(resourceValues)` and store `resourceURL` back if needed.

---

- **File:** `Sources/SwiftDictation/AudioStreamer.swift`
  - **Error:** `invalid redeclaration of 'message'`
  - **Explanation:** The same identifier `message` is declared twice in the same scope: once as a dictionary and later as a `URLSessionWebSocketTask.Message`. This causes a redeclaration error.
  - **Suggested fix:** Rename one of the variables to avoid collision (e.g. `let payload = ...` for the dictionary, then construct the `URLSessionWebSocketTask.Message.string(jsonString)` as `let socketMessage = ...`). Ensure variable names are unique in the scope.

    Example:

    ```swift
    let payload: [String: Any] = [ ... ]
    let jsonString = try JSONSerialization.data(withJSONObject: payload)
    let socketMessage = URLSessionWebSocketTask.Message.string(jsonString)
    webSocketTask.send(socketMessage) { ... }
    ```

---

- **Warnings (non-fatal but worth addressing):**
  - `AudioCaptureSDK.swift`: `result of 'try?' is unused` — consider handling the result or removing unnecessary `try?`.
  - `AudioStreamer.swift`: unused `text` / `data` in switch cases — replace with `_` or handle the values.

---

Verification steps

1. Apply the suggested edits to the files listed above.
2. Run `swift build` from the project root:

```bash
swift build
```

3. Address any remaining compiler diagnostics; iterate until `swift build` completes successfully.

Notes

- The fixes above are minimal, focused changes intended to unblock the build. After the build is green, run the test suite (`swift test`) and address any runtime or test failures.
- If any of the files require platform-specific guards (iOS vs macOS), prefer explicit `#if` checks rather than optional-binding a non-optional API.

