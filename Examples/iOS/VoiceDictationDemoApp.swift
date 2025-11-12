#if canImport(SwiftUI)
import SwiftUI
#endif
import SwiftDictation

@main
struct VoiceDictationDemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var text: String = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Voice Dictation Demo")
                .font(.largeTitle)
                .padding()
            
            TextEditor(text: $text)
                .frame(maxHeight: 200)
                .padding()
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
                .padding(.horizontal)
            
            VoiceDictationView(text: $text)
                .padding()
            
            Spacer()
        }
        .padding()
    }
}

