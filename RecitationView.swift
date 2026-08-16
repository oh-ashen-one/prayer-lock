import SwiftUI
import AVFoundation
import AVFAudio
import Dispatch

final class RecitationController: NSObject, ObservableObject, AVSpeechSynthesisDelegate {
    @Published var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isSpeaking = false
            return
        }

        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: trimmed)
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.isSpeaking = false
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.isSpeaking = false
        }
    }
}

struct RecitationView: View {
    @StateObject private var controller = RecitationController()
    @State private var text = "A short recitation placeholder."

    var body: some View {
        NavigationStack {
            Form {
                Section("Text") {
                    TextEditor(text: $text)
                        .frame(minHeight: 140)
                }

                Section("Playback") {
                    Button(action: speakButtonAction) {
                        Label(
                            controller.isSpeaking ? "Playing" : "Play",
                            systemImage: controller.isSpeaking ? "speaker.wave.3.fill" : "play.circle"
                        )
                    }

                    if controller.isSpeaking {
                        Button(role: .destructive, action: stopButtonAction) {
                            Label("Stop", systemImage: "stop.circle")
                        }
                    }
                }
            }
            .navigationTitle("Recitation")
        }
    }

    private func speakButtonAction() {
        if controller.isSpeaking {
            controller.stop()
        } else {
            controller.speak(text)
        }
    }

    private func stopButtonAction() {
        controller.stop()
    }
}

#Preview {
    RecitationView()
}
