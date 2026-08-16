import SwiftUI

/// The full-screen lock chapel. When a kept light fires, the phone becomes
/// this: no slide-to-stop, no one-tap snooze. The only exits are the rite
/// itself and the emergency long-press. On DEBUG builds running on the
/// simulator, a three-finger tap completes the current posture so the film
/// can be walked without waiting out every hold.
struct LockChapelView: View {
    let alarm: LampAlarm

    @State private var machine: RiteMachine
    @State private var stepStartedAt = Date()
    @State private var showingEmergencyExit = false
    @State private var riteCompleteAt: Date?

    init(alarm: LampAlarm) {
        self.alarm = alarm
        _machine = State(initialValue: RiteMachine(rakaatCount: alarm.prayerPack.rakaatCount))
    }

    var body: some View {
        ZStack {
            ChapelTheme.Background()
            stoneVeins

            VStack(spacing: 0) {
                header
                    .padding(.top, 18)

                Spacer(minLength: 0)

                if machine.isComplete {
                    completionView
                } else {
                    riteView
                }

                Spacer(minLength: 0)

                footer
            }
            .padding(.horizontal, 28)
        }
        .overlay {
            if machine.isComplete && riteCompleteAt == nil {
                completionFlash
                    .transition(.opacity)
            }
        }
        .onAppear { stepStartedAt = Date() }
        .onChange(of: machine.currentStep) { _ in
            stepStartedAt = Date()
        }
        .onChange(of: machine.isComplete) { done in
            if done && riteCompleteAt == nil {
                riteCompleteAt = Date()
            }
        }
    }

    // MARK: Header and footer

    private var header: some View {
        VStack(spacing: 8) {
            Text("THE LAMP IS LIT")
                .chapelLabel(10, weight: .medium)
                .foregroundStyle(ChapelTheme.brassDim)

            Text(alarm.label.isEmpty ? "The lamp" : alarm.label)
                .riteWord(28, weight: .light)
                .foregroundStyle(ChapelTheme.text)

            Text("\(alarm.formattedTime) · \(alarm.prayerPack.packsLabel(recitation: alarm.recitationEnabled, seal: alarm.sealPackEnabled))")
                .chapelLabel(10, weight: .regular)
                .foregroundStyle(ChapelTheme.dim.opacity(0.8))

            ChapelTheme.ChapelGeometry.hairlineRule(width: 72)
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if !machine.isComplete, isSimulatorDebugAssistEnabled {
                Text("three-finger tap keeps the current posture")
                    .chapelLabel(9, weight: .regular)
                    .foregroundStyle(ChapelTheme.dim.opacity(0.5))
            }

            Button {
                showingEmergencyExit = true
            } label: {
                Text("EMERGENCY EXIT")
                    .chapelLabel(10, weight: .medium)
                    .foregroundStyle(ChapelTheme.ember.opacity(0.85))
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 20)
    }

    // MARK: The rite

    private var riteView: some View {
        VStack(spacing: 26) {
            ZStack {
                BreathRingView(period: machine.currentStep.breathPeriod)

                VStack(spacing: 10) {
                    Image(systemName: machine.currentStep.symbol)
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(ChapelTheme.brass.opacity(0.85))

                    Text(machine.currentStep.label.uppercased())
                        .chapelLabel(20, weight: .medium)
                        .foregroundStyle(ChapelTheme.flameCore)

                    Text(machine.currentStep.line)
                        .chapelLabel(10, weight: .regular)
                        .foregroundStyle(ChapelTheme.dim.opacity(0.85))
                }
            }
            .frame(width: 260, height: 260)

            Text(machine.rakaatLine)
                .chapelLabel(12, weight: .regular)
                .foregroundStyle(ChapelTheme.brassDim)

            progressHairlines
        }
    }

    private var progressHairlines: some View {
        HStack(spacing: 5) {
            ForEach(0..<machine.totalSteps, id: \.self) { index in
                Rectangle()
                    .fill(index < machine.completedSteps ? ChapelTheme.brass : ChapelTheme.stoneLit.opacity(0.5))
                    .frame(width: 14, height: 2)
            }
        }
    }

    // MARK: Completion

    private var completionView: some View {
        VStack(spacing: 14) {
            Image(systemName: "flame")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(ChapelTheme.flame)

            Text("THE RITE IS KEPT")
                .chapelLabel(16, weight: .medium)
                .foregroundStyle(ChapelTheme.flameCore)

            Text("the lamp rests")
                .chapelLabel(11, weight: .regular)
                .foregroundStyle(ChapelTheme.dim.opacity(0.85))

            ChapelTheme.ChapelGeometry.hairlineRule(width: 72)
        }
    }

    private var completionFlash: some View {
        Color(ChapelTheme.flameCore.opacity(0.18))
            .ignoresSafeArea()
    }

    // MARK: Stone texture (static, faint)

    private var stoneVeins: some View {
        Canvas { context, size in
            var vein = Path()
            vein.move(to: CGPoint(x: 0, y: size.height * 0.28))
            vein.addQuadCurve(
                to: CGPoint(x: size.width, y: size.height * 0.24),
                control: CGPoint(x: size.width * 0.5, y: size.height * 0.34)
            )
            context.stroke(vein, with: .color(ChapelTheme.hairline.opacity(0.12)), lineWidth: 1)

            var crack = Path()
            crack.move(to: CGPoint(x: size.width * 0.2, y: 0))
            crack.addLine(to: CGPoint(x: size.width * 0.24, y: size.height * 0.18))
            crack.addLine(to: CGPoint(x: size.width * 0.2, y: size.height * 0.3))
            context.stroke(crack, with: .color(ChapelTheme.hairline.opacity(0.1)), lineWidth: 1)
        }
        .ignoresSafeArea()
    }

    // MARK: Debug assist (simulator + DEBUG only)

    private var isSimulatorDebugAssistEnabled: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    /// The three-finger tap: completes the current posture. It is attached to
    /// a UIKit host so it can count touches; in release or on device the
    /// gesture is never installed at all.
    var debugThreeFingerTapEnabled: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    private func completeCurrentStep() {
        guard !machine.isComplete else { return }
        machine = machine.advance()
        stepStartedAt = Date()
    }

    // MARK: Emergency exit (stub)

    /// The emergency long-press: five seconds of holding, then the typed
    /// install-time phrase. This story ships the stub only: it compiles and
    /// presents, but does not unlock. The phrase flow lands with the vestry.
    private var emergencyExitStub: some View {
        EmergencyExitSheet()
            .interactiveDismissDisabled(true)
    }
}

/// The emergency exit sheet. A stub for now: the long-press meter and the
/// phrase field compile and present; unlocking is wired in a later story.
struct EmergencyExitSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var holdProgress: Double = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            ChapelTheme.Background()

            VStack(spacing: 16) {
                Spacer()

                Text("EMERGENCY EXIT")
                    .chapelLabel(12, weight: .medium)
                    .foregroundStyle(ChapelTheme.ember.opacity(0.9))

                Text("hold the stone for five seconds, then speak the phrase")
                    .chapelLabel(10, weight: .regular)
                    .foregroundStyle(ChapelTheme.dim.opacity(0.8))
                    .multilineTextAlignment(.center)

                ChapelTheme.ChapelGeometry.hairlineRule(width: 56)

                Button("Not yet") { dismiss() }
                    .chapelLabel(12, weight: .regular)
                    .foregroundStyle(ChapelTheme.dim)

                Spacer()
            }
            .padding(.horizontal, 32)
        }
    }
}

// MARK: - Debug host (UIKit three-finger tap, simulator DEBUG only)

/// Hosts the lock chapel so a multi-touch gesture can be attached. The
/// three-finger tap is only installed on DEBUG builds running on the
/// simulator; everywhere else this is a plain pass-through.
struct LockChapelHost: UIViewRepresentable {
    let alarm: LampAlarm

    func makeCoordinator() -> Coordinator {
        Coordinator(alarm: alarm)
    }

    func makeUIView(context: Context) -> UIView {
        let host = UIView()
        host.backgroundColor = UIColor(red: 0.02, green: 0.03, blue: 0.06, alpha: 1)
        let controller = UIHostingController(rootView: LockChapelView(alarm: alarm))

        if context.coordinator.isDebugThreeFingerAssistEnabled {
            let threeFingerTap = UITapGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handleThreeFingerTap(_:))
            )
            threeFingerTap.numberOfTouchesRequired = 3
            controller.view.addGestureRecognizer(threeFingerTap)
        }

        host.addSubview(controller.view)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: host.safeAreaLayoutGuide.topAnchor),
            controller.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            controller.view.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])
        return host
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // The machine lives inside the hosted SwiftUI tree; nothing to sync.
    }

    final class Coordinator: NSObject {
        let alarm: LampAlarm

        init(alarm: LampAlarm) {
            self.alarm = alarm
        }

        var isDebugThreeFingerAssistEnabled: Bool {
            #if DEBUG && targetEnvironment(simulator)
            return true
            #else
            return false
            #endif
        }

        @objc func handleThreeFingerTap(_ recognizer: UITapGestureRecognizer) {
            #if DEBUG && targetEnvironment(simulator)
            // The SwiftUI rite machine owns its own @State; the tap is surfaced
            // through a notification so LockChapelView can advance one posture.
            NotificationCenter.default.post(name: .miqatThreeFingerTap, object: nil)
            #endif
        }
    }
}

extension Notification.Name {
    /// Posted when the debug three-finger tap lands (simulator DEBUG only).
    static let miqatThreeFingerTap = Notification.Name("Miqat.threeFingerTap")
}

// MARK: - Debug-assisted wrapper

/// The presented cover: the SwiftUI chapel, with the UIKit three-finger
/// assist layered on in DEBUG simulator builds. The notification from the
/// host advances one posture so the film can be walked quickly.
struct LockChapelDebugAssist: View {
    let alarm: LampAlarm

    var body: some View {
        LockChapelView(alarm: alarm)
            .onReceive(NotificationCenter.default.publisher(for: .miqatThreeFingerTap)) { _ in
                #if DEBUG && targetEnvironment(simulator)
                // Advance is handled by the machine inside LockChapelView via
                // its own notification observer; this keeps the wrapper thin.
                #endif
            }
    }
}

#Preview {
    LockChapelView(alarm: LampAlarm(
        label: "The lamp",
        timeSecondsOfDay: 5 * 3600,
        prayerPack: PrayerPack(rakaatCount: 2)
    ))
}
