#if canImport(SwiftUI)
import SwiftUI
#endif
import SwiftDictation

/// V1 Voice Dictation UI Component
public struct VoiceDictationView: View {
    @Binding var text: String
    @StateObject private var viewModel: VoiceDictationViewModel
    
    public init(text: Binding<String>, config: AudioCaptureConfig = AudioCaptureConfig()) {
        self._text = text
        self._viewModel = StateObject(wrappedValue: VoiceDictationViewModel(config: config))
    }
    
    public var body: some View {
        HStack(spacing: 16) {
            if viewModel.state == .idle {
                // Idle state: Large mic button
                micButton
            } else {
                // Recording/Paused/Processing: Control row
                controlRow
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onAppear {
            viewModel.setup()
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }
    
    private var micButton: some View {
        Button(action: {
            viewModel.startRecording()
        }) {
            Image(systemName: "mic.fill")
                .font(.system(size: 32))
                .foregroundColor(.white)
                .frame(width: 64, height: 64)
                .background(Color.red)
                .clipShape(Circle())
        }
        .accessibilityLabel("Start recording")
    }
    
    private var controlRow: some View {
        HStack(spacing: 16) {
            // Cancel button (left)
            Button(action: {
                viewModel.cancelRecording()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.gray)
            }
            .disabled(viewModel.state == .processing)
            .accessibilityLabel("Cancel recording")
            
            // Waveform (middle)
            WaveformView(amplitudes: viewModel.waveformAmplitudes)
                .frame(height: 40)
            
            // Timer and confirm (right)
            HStack(spacing: 12) {
                if viewModel.state == .processing {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    // Timer
                    Text(viewModel.formattedTime)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    // Confirm/Check button
                    Button(action: {
                        viewModel.commitRecording { transcript in
                            text += transcript
                        }
                    }) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.green)
                    }
                    .disabled(viewModel.state == .processing)
                    .accessibilityLabel("Confirm and process recording")
                }
            }
        }
    }
}

/// ViewModel for Voice Dictation
@MainActor
class VoiceDictationViewModel: ObservableObject {
    @Published var state: DictationState = .idle
    @Published var waveformAmplitudes: [Float] = []
    @Published var recordingTime: TimeInterval = 0
    
    private let sdk: AudioCaptureSDK
    private var timer: Timer?
    private var waveformUpdateTimer: Timer?
    private var audioFrames: [AudioFrame] = []
    
    enum DictationState {
        case idle
        case listening
        case paused
        case processing
        case error(String)
    }
    
    var formattedTime: String {
        let minutes = Int(recordingTime) / 60
        let seconds = Int(recordingTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    init(config: AudioCaptureConfig) {
        self.sdk = AudioCaptureSDK(config: config)
        setupCallbacks()
    }
    
    func setup() {
        Task {
            let status = try? await sdk.requestPermissions()
            if status != .granted {
                state = .error("Microphone permission denied")
            }
        }
    }
    
    func cleanup() {
        timer?.invalidate()
        waveformUpdateTimer?.invalidate()
        try? sdk.stopCapture()
    }
    
    private func setupCallbacks() {
        sdk.onFrame = { [weak self] frame in
            Task { @MainActor in
                self?.audioFrames.append(frame)
                self?.updateWaveform(from: frame)
            }
        }
        
        sdk.onVADStateChange = { [weak self] vadState in
            Task { @MainActor in
                // Could use VAD state for UI feedback
            }
        }
        
        sdk.onError = { [weak self] error in
            Task { @MainActor in
                self?.state = .error(error.localizedDescription)
            }
        }
    }
    
    func startRecording() {
        guard state == .idle || state == .paused else { return }
        
        do {
            if state == .idle {
                try sdk.startCapture()
                state = .listening
                startTimer()
                startWaveformUpdates()
            } else {
                try sdk.resumeCapture()
                state = .listening
                startTimer()
            }
        } catch {
            state = .error(error.localizedDescription)
        }
    }
    
    func cancelRecording() {
        guard state == .listening || state == .paused else { return }
        
        do {
            try sdk.stopCapture()
            reset()
        } catch {
            state = .error(error.localizedDescription)
        }
    }
    
    func pauseRecording() {
        guard state == .listening else { return }
        
        do {
            try sdk.pauseCapture()
            state = .paused
            stopTimer()
        } catch {
            state = .error(error.localizedDescription)
        }
    }
    
    func commitRecording(completion: @escaping (String) -> Void) {
        guard state == .listening || state == .paused else { return }
        
        state = .processing
        
        Task {
            do {
                // Stop capture
                try sdk.stopCapture()
                stopTimer()
                
                // Export audio
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("recording_\(UUID().uuidString).wav")
                
                let exportResult = try await sdk.exportRecording(format: .wav, destination: tempURL)
                
                // TODO: Send to ASR service and get transcript
                // For now, simulate with a placeholder
                let transcript = await transcribeAudio(url: tempURL)
                
                await MainActor.run {
                    completion(transcript)
                    reset()
                }
            } catch {
                await MainActor.run {
                    state = .error(error.localizedDescription)
                }
            }
        }
    }
    
    private func reset() {
        state = .idle
        recordingTime = 0
        waveformAmplitudes.removeAll()
        audioFrames.removeAll()
        timer?.invalidate()
        waveformUpdateTimer?.invalidate()
    }
    
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recordingTime += 0.1
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
    }
    
    private func startWaveformUpdates() {
        waveformUpdateTimer?.invalidate()
        waveformUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                // Keep waveform updated
            }
        }
    }
    
    private func updateWaveform(from frame: AudioFrame) {
        // Calculate RMS amplitude for waveform visualization
        let samples = frame.data.withUnsafeBytes { bytes in
            Array(UnsafeBufferPointer<Int16>(start: bytes.baseAddress?.assumingMemoryBound(to: Int16.self), count: frame.data.count / 2))
        }
        
        let sum = samples.reduce(0) { $0 + abs($1) }
        let amplitude = Float(sum) / Float(samples.count) / 32768.0
        
        waveformAmplitudes.append(amplitude)
        
        // Keep only recent amplitudes for display (last 100)
        if waveformAmplitudes.count > 100 {
            waveformAmplitudes.removeFirst()
        }
    }
    
    private func transcribeAudio(url: URL) async -> String {
        // TODO: Integrate with ASR service (Deepgram, Google, AssemblyAI, etc.)
        // For now, return placeholder
        return "[Transcribed text would appear here]"
    }
}

/// Waveform visualization view
struct WaveformView: View {
    let amplitudes: [Float]
    
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height
                let barWidth = width / CGFloat(max(amplitudes.count, 1))
                
                for (index, amplitude) in amplitudes.enumerated() {
                    let x = CGFloat(index) * barWidth
                    let barHeight = CGFloat(amplitude) * height * 0.8
                    let y = (height - barHeight) / 2
                    
                    path.addRect(CGRect(x: x, y: y, width: max(barWidth - 2, 1), height: barHeight))
                }
            }
            .fill(Color.blue)
        }
    }
}

