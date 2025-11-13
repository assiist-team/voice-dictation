### 07 — BYO Streaming V2 (optional): binary WS + provider adapter + token proxy

Outcome:
- Optional streaming path sends raw PCM frames over a secure WebSocket to an external ASR provider with segment‑level ACKs. The transport uses binary frames for audio and compact JSON control for metadata. Providers are pluggable behind a small adapter interface. Tokens are minted via a tiny proxy.

Scope:
- Replace JSON+base64 audio payloads with binary WebSocket frames for audio.
- Keep a small JSON control message for session/segment metadata.
- Introduce a `ProviderAdapter` abstraction for Deepgram/AssemblyAI differences.
- Add resumability via segment sequence IDs and server ACKs.

Acceptance criteria:
- Audio frames are sent as binary WS messages; no base64 for audio payloads.
- Segment metadata (sequenceId, start/end sample index or timestamps, sampleRate, deviceId) is sent as JSON control messages.
- Provider adapter negotiates any provider‑specific headers/handshake and parses ACKs.
- On error or disconnect, SDK can resume from the next un‑ACKed segment.

Key files:
- `Sources/SwiftDictation/AudioStreamer.swift` (rewrite for binary audio frames + JSON control)
- `Sources/SwiftDictation/AudioChunker.swift` (already segments; may add segment grouping)
- Add new: `Sources/SwiftDictation/Streaming/ProviderAdapter.swift`
- Add new: `Sources/SwiftDictation/Streaming/DeepgramAdapter.swift`, `AssemblyAIAdapter.swift`

Design sketch:
1) ProviderAdapter
   - Protocol with:
     - `func makeURLRequest(for target: StreamTarget) -> URLRequest`
     - `func controlMessage(for segment: SegmentMeta) -> Data` (JSON)
     - `func parseAck(_ message: URLSessionWebSocketTask.Message) -> Ack?`
   - Default adapter handles generic servers; specific adapters can set headers and control shapes.

2) Transport framing
   - Audio: binary frames containing raw PCM bytes for the configured frame size (20–60 ms).
   - Control: a small JSON message emitted at segment boundaries:
     ```
     { "sequenceId": 12, "startSampleIndex": 123456, "endSampleIndex": 143456, "sampleRate": 16000, "deviceId": "<uuid>" }
     ```
   - The server responds with an ACK referencing `sequenceId`; adapter parses and triggers `onChunkSent`.

3) Resumability
   - Maintain a ring buffer of recent segments (IDs and byte ranges).
   - On disconnect, reconnect and send a `resumeFrom: <lastAcked+1>` control message if provider supports it; else restart the session cleanly.

4) Token proxy (out of repo)
   - Minimal spec:
     - POST `/token` → `{ token: "<short‑lived>" }`
     - Server validates app auth and mints a provider token with least privilege and short TTL (≤ 10 min).
   - The app sets `StreamTarget.headers["Authorization"] = "Bearer <token>"`.
   - Never embed long‑lived provider keys in the app.

5) Backpressure and threading
   - Queue outbound frames; if the socket send backlog grows beyond N frames, drop or coalesce depending on provider requirements (configurable).
   - Keep parsing/ACK handling on a dedicated queue to avoid blocking capture.

Testing guide:
- Local echo server or mock URLProtocol to assert:
  - Binary frames are received with the right sizes and cadence.
  - Control messages contain the expected JSON fields.
  - ACKs advance sequence tracking; simulated disconnect resumes correctly.

Gotchas:
- iOS backgrounding may suspend sends; plan for reconnect on foreground.
- Ensure URLSessionWebSocketTask is kept alive; handle `closeCode` semantics.
- Providers have slightly different control schemas; keep adapter boundaries clean.

Definition of Done:
- Binary WS audio + JSON control integrated with a provider adapter.
- Basic ACK/resume implemented; graceful handling of disconnects and errors.
- Documentation updated to recommend this path for V2 users requiring 3rd‑party ASR.


