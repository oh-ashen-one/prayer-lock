import SwiftUI

/// The step screen: the posture word, its small line beneath it, and the
/// breath ring that fills over the timed hold. For prostration only, it adds
/// the hybrid's one explicit affordance — the tap that says "the phone is on
/// the floor" — after which stillness (not more touching) finishes the hold.

struct PrayerStepView: View {
    let conductor: RiteConductor

    private let palette = ChapelPalette.chapelNight

    var body: some View {
        let expected = conductor.expectedPosture

        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .strokeBorder(palette.dim.opacity(0.25), lineWidth: 3)

                Circle()
                    .trim(from: 0, to: conductor.holdProgress)
                    .stroke(palette.flame, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: palette.flame.opacity(0.55), radius: 9)

                LampFlameMark(size: 34, settled: false)
            }
            .frame(width: 208, height: 208)

            Text(expected.word.uppercased())
                .riteWord(46)
                .foregroundStyle(palette.text)

            Text(expected.line)
                .chapelLabel(12, weight: .regular)
                .foregroundStyle(palette.dim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

            placementControl(for: expected)
        }
    }

    @ViewBuilder
    private func placementControl(for posture: Posture) -> some View {
        if posture == .prostrating {
            if !conductor.engine.phonePlaced {
                Button(action: { conductor.markPlaced() }) {
                    Text("TAP — PHONE IS ON THE FLOOR")
                        .chapelLabel(12, weight: .semibold)
                        .foregroundStyle(palette.flame)
                        .padding(.horizontal, 22)
                        .frame(height: 46)
                        .background(
                            Capsule().fill(palette.flame.opacity(0.12))
                        )
                        .overlay(
                            Capsule().strokeBorder(palette.flame.opacity(0.8), lineWidth: 1.2)
                        )
                }
                .buttonStyle(.plain)
            } else if !conductor.engine.atRest {
                Text("set — hold still")
                    .chapelLabel(12, weight: .regular)
                    .foregroundStyle(palette.flame.opacity(0.85))
            } else {
                Text("still — the floor knows")
                    .chapelLabel(12, weight: .regular)
                    .foregroundStyle(palette.brass.opacity(0.9))
            }
        } else {
            Color.clear.frame(height: 1)   // keep the vertical rhythm steady
        }
    }
}

#Preview("Step — prostrate") {
    struct Host: View {
        @State private var conductor = RiteConductor(rakaats: 1)
        var body: some View {
            ZStack {
                ChapelLockBackground().ignoresSafeArea()
                PrayerStepView(conductor: conductor)
            }
        }
    }
    return Host()
}
