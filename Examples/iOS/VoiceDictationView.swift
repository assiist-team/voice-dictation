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
        VStack(spacing: 8) {
            // Interruption banner
            if viewModel.state == .interrupted {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Recording interrupted. Resuming...")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Transcript display
            if !viewModel.currentTranscript.isEmpty {
                Text(viewModel.currentTranscript)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }
            
            HStack(spacing: 16) {
                // Cancel button (left)
                Button(action: {
                    viewModel.cancelRecording()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.gray)
                }
                .disabled(viewModel.state == .processing || viewModel.state == .interrupted)
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
                                text += transcript + " "
                            }
                        }) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.green)
                        }
                        .disabled(viewModel.state == .processing || viewModel.state == .interrupted)
                        .accessibilityLabel("Confirm and commit recording")
                    }
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
    @Published var currentTranscript: String = ""
    
    private let sdk: AudioCaptureSDK
    private var timer: Timer?
    private var waveformUpdateTimer: Timer?
    private var audioFrames: [AudioFrame] = []
    
    enum DictationState {
        case idle
        case listening
        case paused
        case processing
        case interrupted
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
                state = .error("Microphone or speech recognition permission denied")
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
                // Check if it's an interruption error
                if let captureError = error as? AudioCaptureError,
                   case .deviceInterrupted = captureError {
                    // Only set interrupted state if we're currently listening
                    if self?.state == .listening {
                        self?.state = .interrupted
                    }
                } else {
                    self?.state = .error(error.localizedDescription)
                }
            }
        }
        
        sdk.onInterruptionRecovered = { [weak self] in
            Task { @MainActor in
                // Automatically resume if we were interrupted
                if self?.state == .interrupted {
                    self?.state = .listening
                }
            }
        }
        
        // Native Speech callbacks
        sdk.onPartialTranscript = { [weak self] text in
            Task { @MainActor in
                self?.currentTranscript = text
            }
        }
        
        sdk.onFinalTranscript = { [weak self] text in
            Task { @MainActor in
                // Update current transcript with final version
                self?.currentTranscript = text
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
            // Cancel current block (discards transcript)
            try sdk.cancelCurrentBlock()
            currentTranscript = ""
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
        
        // Store current partial transcript before committing
        let partialText = currentTranscript
        
        do {
            // Commit current block - this will trigger onFinalTranscript callback
            try sdk.commitCurrentBlock()
            
            // Use the partial transcript immediately for UI feedback
            // The onFinalTranscript callback will update currentTranscript when it arrives
            if !partialText.isEmpty {
                completion(partialText)
                // Clear after a short delay to allow final transcript to arrive
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if self.currentTranscript == partialText {
                        self.currentTranscript = ""
                    }
                }
            }
        } catch {
            state = .error(error.localizedDescription)
        }
    }
    
    private func reset() {
        state = .idle
        recordingTime = 0
        currentTranscript = ""
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

