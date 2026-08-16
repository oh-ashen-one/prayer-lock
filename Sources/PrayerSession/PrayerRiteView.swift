import SwiftUI
import Observation

// MARK: - Conductor
/// The loop that joins the sensor to the machine. Ten times a second it asks
/// "does what is sensed match what the rite expects?"; when the answer holds
/// for the posture's full duration, it advances. A deviation resets the hold
/// clock — a posture you leave does not earn partial credit.

@MainActor
@Observable
final class RiteConductor {
    let engine = PostureEngine()

    /// The pure machine. Read by the UI (columns, piers, counter) and advanced
    /// here on full holds — nowhere else.
    var machine: RiteStateMachine

    private(set) var holdProgress: Double = 0
    private var holdStart: Date?
    private(set) var hasStarted = false

    /// Fired exactly once, on the tick that completes the rite. Hopped to a
    /// Task so we never tear down the view from inside its own heartbeat.
    var onComplete: (() -> Void)?

    init(rakaats: Int) {
        machine = RiteStateMachine(rakaats: rakaats)
    }

    var isComplete: Bool { machine.isComplete }
    var expectedPosture: Posture { machine.expectedPosture }

    func begin() {
        guard !hasStarted else { return }
        hasStarted = true
        engine.start()
        machine.begin(at: .now)
    }

    func stop() {
        engine.stop()
    }

    /// The tap that says "the phone is set on the floor" (prostration only).
    /// It also voids any partial hold: stillness is earned from the tap.
    func markPlaced() {
        engine.markPhoneOnFloor()
        holdStart = nil
    }

    /// 10 Hz heartbeat.
    func tick() {
        guard hasStarted else { return }

        if machine.isComplete {
            holdProgress = 1
            return
        }

        let expected = machine.expectedPosture

        if engine.matches(expected) {
            let now = Date()
            if holdStart == nil {
                holdStart = now
            }
            let required = machine.requiredHold
            holdProgress = min(1, now.timeIntervalSince(holdStart!) / max(required, 0.5))

            if holdProgress >= 1 {
                holdStart = nil
                if let result = machine.advance(at: now) {
                    lastAdvance = result
                    holdProgress = 0
                    if result.riteComplete {
                        let callback = onComplete
                        Task { @MainActor in callback?() }
                    }
                } else {
                    holdProgress = 0
                }
            }
        } else if holdStart != nil {
            // Deviation: the hold clock resets. Honest, and visible — the ring
            // drains to nothing rather than pretending.
            holdStart = nil
            holdProgress = 0
        } else if holdProgress > 0 {
            holdProgress = max(0, holdProgress - 0.1)
        }
    }

    private(set) var lastAdvance: RiteStateMachine.AdvanceResult?

#if DEBUG && targetEnvironment(simulator)
    /// The named simulator assist: three fingers, one step. Device builds do
    /// not contain this method at all.
    func debugCompleteStep() {
        guard hasStarted, !machine.isComplete else { return }
        holdStart = nil
        if let result = machine.advance(at: .now) {
            lastAdvance = result
            holdProgress = 0
            if result.riteComplete {
                let callback = onComplete
                Task { @MainActor in callback?() }
            }
        }
    }
#endif
}

// MARK: - The rakaʿāt, drawn as architecture
/// One column per rakaʿat; a pier for each of the four postures, in order.
/// Piers light as they are held; the expected one glows like a lamp in the arch.

struct RakaatArchitecture: View {
    let conductor: RiteConductor

    private let palette = ChapelPalette.chapelNight
    private static let roman = ["I", "II", "III", "IV"]

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            ForEach(0..<conductor.machine.plan.rakaats, id: \.self) { index in
                column(index: index)
            }
        }
    }

    private func column(index: Int) -> some View {
        let rakaat = index + 1
        let isCurrentRakaat = !conductor.isComplete && conductor.machine.currentRakaat == rakaat
        let completed = conductor.machine.completedPiers(inRakaat: rakaat)

        return VStack(spacing: 7) {
            ForEach(RitePlan.sequence, id: \.rawValue) { posture in
                let done = completed.contains(posture)
                let isExpected = isCurrentRakaat && conductor.expectedPosture == posture

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(pierFill(done: done, expected: isExpected))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(pierStroke(done: done, expected: isExpected), lineWidth: 1)
                    )
                    .shadow(color: isExpected ? palette.flame.opacity(0.8) : .clear, radius: 7)
                    .frame(width: 26, height: 30)
            }

            Text(Self.roman[min(index, 3)])
                .font(Chapel.display(13, weight: .medium))
                .foregroundStyle(isCurrentRakaat ? palette.flame : palette.dim)
        }
    }

    private func pierFill(done: Bool, expected: Bool) -> Color {
        if done { return palette.brass.opacity(0.92) }
        if expected { return palette.flame.opacity(0.85) }
        return palette.dim.opacity(0.12)
    }

    private func pierStroke(done: Bool, expected: Bool) -> Color {
        if done { return palette.brass.opacity(0.9) }
        if expected { return palette.flame }
        return palette.dim.opacity(0.35)
    }
}

// MARK: - The prayer step (host of the conductor + step view)

struct PrayerRiteView: View {
    let alarm: Alarm
    var onComplete: () -> Void

    @State private var conductor: RiteConductor

    init(alarm: Alarm, onComplete: @escaping () -> Void) {
        self.alarm = alarm
        self.onComplete = onComplete
        _conductor = State(initialValue: RiteConductor(rakaats: alarm.rakaatCount))
    }

    private let palette = ChapelPalette.chapelNight

    var body: some View {
        VStack(spacing: 18) {
            RakaatArchitecture(conductor: conductor)

            Spacer(minLength: 6)

            PrayerStepView(conductor: conductor)

            Text("RAKAʿA \(conductor.machine.currentRakaat) OF \(conductor.machine.plan.rakaats)")
                .chapelLabel(11, weight: .medium)
                .foregroundStyle(palette.dim.opacity(0.85))

            Spacer(minLength: 6)
        }
        .padding(.horizontal, 24)
        .task {
            conductor.onComplete = { [onComplete] in onComplete() }
            conductor.begin()
            while !Task.isCancelled && !conductor.isComplete {
                try? await Task.sleep(for: .seconds(0.1))
                conductor.tick()
            }
        }
        .onDisappear { conductor.stop() }
#if DEBUG && targetEnvironment(simulator)
        .simultaneousGesture(
            TapGesture(count: 3).onEnded {
                conductor.debugCompleteStep()
            }
        )
#endif
    }
}

#Preview("Prayer rite") {
    ZStack {
        ChapelLockBackground().ignoresSafeArea()
        PrayerRiteView(alarm: Alarm(timeSecondsOfDay: 300, rakaatCount: 2)) { }
    }
}
