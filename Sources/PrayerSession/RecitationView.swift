import SwiftUI
import AVFoundation

// MARK: - Speech delegate
/// Forwards "utterance finished" to the view. The synthesizer reports on the
/// main queue, so no further hopping is needed before we schedule state work.

final class RecitationSpeaker: NSObject, AVSpeechSynthesisDelegate {
    /// Called with the index of the finished utterance (see identifier).
    var onFinished: ((Int) -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        guard let identifier = utterance.identifier, let index = Int(identifier) else { return }
        onFinished?(index)
    }
}

// MARK: - Recitation step
/// On-device recitation. Each line is spoken by AVSpeechSynthesizer — no
/// network, no permission (synthesis only) — at a deliberately slow rate.
/// After the last line, continuing is a deliberate tap: progressing through a
/// rite is never accidental.

struct RecitationView: View {
    let phrases: [String]
    var onComplete: () -> Void

    @State private var synth = AVSpeechSynthesizer()
    @State private var speaker = RecitationSpeaker()
    @State private var index = 0
    @State private var isDone = false

    private let palette = ChapelPalette.chapelNight
    private var lines: [String] { phrases }   // LockChapelView already filters empties

    var body: some View {
        VStack(spacing: 20) {
            Text("RECITATION")
                .chapelLabel(11, weight: .medium)
                .foregroundStyle(palette.dim)

            VStack(spacing: 8) {
                if isDone && !lines.isEmpty {
                    Text("the words are done")
                        .font(Chapel.display(20, weight: .regular))
                        .foregroundStyle(palette.brass)
                } else if let current = lines.indices.contains(min(index, max(lines.count - 1, 0))) ? lines[min(index, lines.count - 1)] : nil {
                    Text(current)
                        .font(Chapel.display(24, weight: .regular))
                        .foregroundStyle(palette.text)
                } else {
                    Text("…")
                        .font(Chapel.display(24))
                        .foregroundStyle(palette.dim)
                }
            }
            .multilineTextAlignment(.center)
            .frame(minHeight: 96, alignment: .center)

            if !lines.isEmpty {
                HStack(spacing: 8) {
                    ForEach(lines.indices, id: \.self) { i in
                        Circle()
                            .fill(dotColor(i))
                            .frame(width: 6, height: 6)
                    }
                }
            }

            if isDone {
                Button(action: onComplete) {
                    Text("CONTINUE")
                        .chapelLabel(13, weight: .semibold)
                        .foregroundStyle(palette.flame)
                        .frame(maxWidth: 220)
                        .frame(height: 48)
                        .background(
                            Capsule().fill(palette.flame.opacity(0.12))
                        )
                        .overlay(
                            Capsule().strokeBorder(palette.flame.opacity(0.8), lineWidth: 1.2)
                        )
                }
                .buttonStyle(.plain)
            } else if !lines.isEmpty {
                Text(speakingWord)
                    .chapelLabel(10, weight: .regular)
                    .foregroundStyle(palette.dim.opacity(0.7))
            }
        }
        .padding(26)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(palette.surface.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(palette.brass.opacity(0.3), lineWidth: 1)
        )
        .task {
            guard !lines.isEmpty else {
                isDone = true
                return
            }
            speaker.onFinished = { finished in handleFinished(finished) }
            speak(0)
        }
        .onDisappear {
            synth.stopSpeaking(at: .immediate)
        }
    }

    private var speakingWord: String {
        if synth.isSpeaking { "speaking…" } else { "a breath between lines" }
    }

    private func dotColor(_ i: Int) -> Color {
        if isDone || i < index { return palette.brass }
        if i == index { return palette.flame }
        return palette.dim.opacity(0.3)
    }

    // MARK: Speech mechanics

    private func speak(_ i: Int) {
        guard lines.indices.contains(i) else {
            isDone = true
            return
        }
        let utterance = AVSpeechUtterance(string: lines[i])
        utterance.identifier = String(i)
        utterance.rate = 0.42   // slower than default; recitation is not broadcast
        if let voice = preferredVoice() {
            utterance.voice = voice
        }
        synth.speak(utterance)
    }

    /// If any phrase is Arabic script, prefer an Arabic voice when the device
    /// has one; otherwise the user's system default. Never a network fetch —
    /// on-device voices only.
    private func preferredVoice() -> AVSpeechSynthesisVoice? {
        let hasArabic = lines.contains { line in
            line.unicodeScalars.contains { scalar in (0x0600...0x06FF).contains(scalar.value) }
        }
        if hasArabic {
            return AVSpeechSynthesisVoice(language: "ar-SA")
        }
        return nil
    }

    private func handleFinished(_ finished: Int) {
        Task { @MainActor in
            guard finished == index else { return }   // ignore stale callbacks
            let next = finished + 1
            index = next
            if next < lines.count {
                try? await Task.sleep(for: .seconds(0.9))   // a breath between lines
                speak(next)
            } else {
                isDone = true
            }
        }
    }
}

#Preview("Recitation") {
    ZStack {
        ChapelLockBackground().ignoresSafeArea()
        RecitationView(phrases: ["Subhan Allah.", "Alhamdulillah."]) { }
    }
}
