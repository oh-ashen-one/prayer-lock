import SwiftUI
import SwiftData
import UIKit

// MARK: - The locked chapel
//
// Full-screen, no dismiss gesture, fixed dark room. It is deliberately split:
// this view owns the *process* (summons → rite steps → done) and the only
// exit that is not completion (the emergency wick). The steps themselves are
// separate views — PrayerRiteView, RecitationView, SealCaptureView — and each
// reports back exactly one way: "this step is done."

enum ChapelStep {
    case prayer, recitation, seal, stillness

    var title: String {
        switch self {
        case .prayer: "Prayer"
        case .recitation: "Recitation"
        case .seal: "The Seal"
        case .stillness: "Stillness"
        }
    }

    var word: String {
        switch self {
        case .prayer: "The rakaʿāt"
        case .recitation: "The words"
        case .seal: "The seal"
        case .stillness: "Sit with the lamp"
        }
    }
}

struct LockChapelView: View {
    let alarmID: UUID

    @Environment(AppRuntime.self) private var runtime
    @Environment(\.modelContext) private var context

    @State private var alarm: Alarm?
    @State private var sealObjects: [SealObject] = []
    @State private var queue: [ChapelStep] = []
    @State private var stage: Stage = .summons
    @State private var hasReleased = false

    @AppStorage("miqat.sealThreshold") private var sealThreshold: Double = 0.28

    /// The chapel has three movements: the summons (the lamp is lit), the rite
    /// (a queue of steps), and the settle ("the rite is done"). There is no
    /// fourth movement in which you simply leave.
    enum Stage: Equatable {
        case summons
        case step(Int)
        case done
    }

    var body: some View {
        ZStack {
            ChapelLockBackground()
                .ignoresSafeArea()

            switch stage {
            case .summons:
                summonsView
                    .transition(.opacity)
            case .step(let index):
                stepShell(index: index)
                    .transition(.opacity)
            case .done:
                doneView
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.55), value: stage)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            EmergencyWickView(alarmID: alarm?.id) { releasedAlarm in
                runtime.recordEmergencyExit(alarmID: releasedAlarm, in: context)
            }
        }
        .onAppear(perform: prepare)
        // Movement clocks. Summoning holds its beat, then the rite begins on
        // its own; "done" lets the flame settle for a moment before release.
        .task(id: stage) {
            switch stage {
            case .summons where !queue.isEmpty:
                try? await Task.sleep(for: .seconds(2.4))
                if stage == .summons {
                    withAnimation(.easeInOut(duration: 0.55)) { stage = .step(0) }
                }
            case .done:
                try? await Task.sleep(for: .seconds(2.8))
                release()
            case .step:
                break   // step views own their own time (holds, speech, matching)
            }
        }
    }

    // MARK: Preparation

    private func prepare() {
        guard alarm == nil else { return }

        var descriptor = FetchDescriptor<Alarm>(predicate: #Predicate { $0.id == alarmID })
        descriptor.fetchLimit = 1
        let fetched = (try? context.fetch(descriptor))?.first

        var sealDescriptor = FetchDescriptor<SealObject>()
        sealDescriptor.sortBy = [SortDescriptor(\SealObject.createdAt)]
        sealObjects = (try? context.fetch(sealDescriptor)) ?? []

        guard let a = fetched else {
            // The alarm vanished (deleted on another pass) — discharge quietly.
            hasReleased = true
            runtime.finishRite(alarm: nil, in: context)
            return
        }

        alarm = a
        queue = buildQueue(for: a)
    }

    /// Order of the rite as configured. An alarm with no packs at all still
    /// asks for something: forty-five seconds of sitting with the lamp. Light
    /// without a rite is not an alarm; it is a screen.
    private func buildQueue(for a: Alarm) -> [ChapelStep] {
        var q: [ChapelStep] = []
        if a.prayerPackEnabled { q.append(.prayer) }

        let hasRealPhrase = a.recitationPhrases.contains {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if a.recitationEnabled && hasRealPhrase { q.append(.recitation) }

        if a.sealPackEnabled, sealObjects.count >= SealObject.minimumCount {
            q.append(.seal)
        }

        return q.isEmpty ? [.stillness] : q
    }

    // MARK: Movements

    private var summonsView: some View {
        VStack(spacing: 22) {
            Spacer()
            LampFlameMark(size: 44)
            Text("THE LAMP IS LIT")
                .chapelLabel(13)
                .foregroundStyle(ChapelPalette.chapelNight.dim)
            Text(alarm?.label.isEmpty == false ? alarm!.label : "The rite")
                .riteWord(34)
                .foregroundStyle(ChapelPalette.chapelNight.text)
            if let a = alarm {
                Text("\(a.timeLabel) · \(a.packsLabel)")
                    .chapelLabel(14, weight: .regular)
                    .foregroundStyle(ChapelPalette.chapelNight.brass.opacity(0.9))
            }
            Spacer()
            Spacer()
        }
    }

    private func stepShell(index: Int) -> some View {
        VStack(spacing: 18) {
            header
            stepTrail(current: index)
            Spacer(minLength: 0)

            stepContent(index)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
    }

    private var header: some View {
        HStack(spacing: 10) {
            LampFlameMark(size: 20, settled: false)
            VStack(alignment: .leading, spacing: 1) {
                Text(alarm?.label.isEmpty == false ? alarm!.label : "The rite")
                    .font(Chapel.display(19, weight: .medium))
                    .foregroundStyle(ChapelPalette.chapelNight.text)
                Text(alarm?.timeLabel ?? "")
                    .chapelLabel(11)
                    .foregroundStyle(ChapelPalette.chapelNight.brass.opacity(0.8))
            }
            Spacer()
            if let a = alarm {
                Text(a.packsLabel)
                    .chapelLabel(11, weight: .regular)
                    .foregroundStyle(ChapelPalette.chapelNight.dim)
            }
        }
    }

    private func stepTrail(current: Int) -> some View {
        HStack(spacing: 16) {
            ForEach(queue.indices, id: \.self) { i in
                HStack(spacing: 6) {
                    Circle()
                        .fill(dotColor(index: i, current: current))
                        .frame(width: 5, height: 5)
                    Text(queue[i].title.uppercased())
                        .chapelLabel(10)
                        .foregroundStyle(wordColor(index: i, current: current))
                }
            }
        }
    }

    private func dotColor(index: Int, current: Int) -> Color {
        if index < current { return ChapelPalette.chapelNight.brass }
        if index == current { return ChapelPalette.chapelNight.flame }
        return ChapelPalette.chapelNight.dim.opacity(0.35)
    }

    private func wordColor(index: Int, current: Int) -> Color {
        if index < current { return ChapelPalette.chapelNight.brass.opacity(0.85) }
        if index == current { return ChapelPalette.chapelNight.text }
        return ChapelPalette.chapelNight.dim.opacity(0.7)
    }

    @ViewBuilder
    private func stepContent(_ index: Int) -> some View {
        guard let a = alarm else {
            Text("…")
                .chapelLabel(14)
                .foregroundStyle(ChapelPalette.chapelNight.dim)
        }

        switch queue[index] {
        case .prayer:
            PrayerRiteView(alarm: a) { advance(from: index) }
        case .recitation:
            RecitationView(phrases: a.recitationPhrases.filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) { advance(from: index) }
        case .seal:
            SealCaptureView(
                objects: sealObjects,
                threshold: sealThreshold
            ) { advance(from: index) }
        case .stillness:
            StillnessHoldView(seconds: 45) { advance(from: index) }
        }
    }

    private var doneView: some View {
        VStack(spacing: 20) {
            Spacer()
            LampFlameMark(size: 46, settled: true)
            Text("The rite is done.")
                .riteWord(36)
                .foregroundStyle(ChapelPalette.chapelNight.text)
            Text("the lamp burns on")
                .chapelLabel(13, weight: .regular)
                .foregroundStyle(ChapelPalette.chapelNight.dim)
            Spacer()
            Spacer()
        }
    }

    // MARK: Movement mechanics

    private func advance(from index: Int) {
        guard !hasReleased else { return }
        withAnimation(.easeInOut(duration: 0.55)) {
            if index + 1 < queue.count {
                stage = .step(index + 1)
            } else {
                stage = .done
            }
        }
    }

    /// Release is idempotent. A one-shot alarm disarms itself as it pays off —
    /// the debt, once done, is not a standing appointment.
    private func release() {
        guard !hasReleased else { return }
        hasReleased = true
        if let a = alarm, a.spec.isOneShot {
            a.enabled = false
            AlarmScheduler.unschedule(a)
        }
        runtime.finishRite(alarm: alarm, in: context)
    }
}

// MARK: - Stillness (the light-only rite)

/// An alarm with every pack disabled still asks for something real: sit, and
/// let the ring close. Forty-five seconds is long enough to be a choice.
struct StillnessHoldView: View {
    let seconds: Int
    var onComplete: () -> Void

    @State private var progress: Double = 0
    @State private var startedAt: Date?

    var body: some View {
        VStack(spacing: 24) {
            Text("SIT WITH THE LAMP")
                .chapelLabel(12)
                .foregroundStyle(ChapelPalette.chapelNight.dim)

            ZStack {
                Circle()
                    .strokeBorder(ChapelPalette.chapelNight.dim.opacity(0.3), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(ChapelPalette.chapelNight.flame,
                            style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(max(0, Int(ceil(Double(seconds) * (1 - progress)))))")
                    .font(Chapel.display(40, weight: .light))
                    .foregroundStyle(ChapelPalette.chapelNight.text.opacity(0.9))
            }
            .frame(width: 180, height: 180)

            Text("no movement is required; only that you stay")
                .chapelLabel(12, weight: .regular)
                .foregroundStyle(ChapelPalette.chapelNight.dim.opacity(0.8))
        }
        .task {
            let start = Date()
            startedAt = start
            while progress < 1 {
                try? await Task.sleep(for: .seconds(0.1))
                progress = min(1, Date().timeIntervalSince(start) / Double(seconds))
            }
            onComplete()
        }
    }
}

// MARK: - The lamp flame

/// A breathing flame. In the settle state it slows to a near-steady glow —
/// the visual equivalent of finishing.
struct LampFlameMark: View {
    var size: CGFloat = 40
    var settled: Bool = false

    private let flame = ChapelPalette.chapelNight.flame
    private let deepFlame = Color(red: 0.85, green: 0.32, blue: 0.10)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let pulse: Double
            if settled {
                pulse = 0.94 + 0.03 * sin(t / 2.6)
            } else {
                let raw = 0.5 * sin(t / 1.7) + 0.32 * sin(t / 4.3) + 0.18 * sin(t / 9.1)
                pulse = min(1, max(0.55, 0.78 + 0.22 * raw))
            }

            ZStack {
                Circle()
                    .fill(flame.opacity(0.22 * pulse))
                    .frame(width: size * 2.8, height: size * 2.8)
                    .blur(radius: 16)

                Image(systemName: "flame.fill")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(colors: [flame, deepFlame],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .scaleEffect(0.9 + 0.14 * pulse)
            }
        }
    }
}

// MARK: - Emergency exit
//
// The only door that is not the rite. Five seconds of holding — long enough to
// be deliberate, short enough for an emergency — then the install-time phrase.
// Every verified opening is written to the ledger by AppRuntime; this view only
// ever asks.

struct EmergencyWickView: View {
    let alarmID: UUID?
    var onVerified: (UUID?) -> Void

    @Environment(AppRuntime.self) private var runtime

    private let holdSeconds: Double = 5.0

    @State private var chargeStart: Date?
    @State private var armedForPhrase = false
    @State private var phrase = ""
    @State private var failCount = 0
    @FocusState private var phraseFieldFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            if armedForPhrase {
                phraseGate
            } else {
                chargeWick
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: Charge stage

    private var chargeWick: some View {
        VStack(spacing: 8) {
            Text("HOLD FIVE SECONDS · RELEASE THE DOOR")
                .chapelLabel(9, weight: .medium)
                .foregroundStyle(ChapelPalette.chapelNight.dim.opacity(0.7))

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: chargeStart == nil)) { timeline in
                let p = progress(at: timeline.date)
                ZStack {
                    Circle()
                        .strokeBorder(ChapelPalette.chapelNight.dim.opacity(0.35), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: p)
                        .stroke(ChapelPalette.chapelNight.flame,
                                style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "flame")
                        .font(Chapel.ui(15, weight: .semibold))
                        .foregroundStyle(p >= 0.98 ? ChapelPalette.chapelNight.flame
                                                   : ChapelPalette.chapelNight.dim)
                }
                .frame(width: 50, height: 50)
            }
        }
        .contentShape(Rectangle())
        .gesture(holdGesture)
    }

    private func progress(at date: Date) -> Double {
        guard let start = chargeStart else { return 0 }
        return min(1, date.timeIntervalSince(start) / holdSeconds)
    }

    private var holdGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard chargeStart == nil else { return }
                let start = Date()
                chargeStart = start
                // Arm exactly at five seconds of continuous hold, without
                // waiting for the finger to lift.
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(holdSeconds))
                    if let stillHolding = chargeStart,
                       Date().timeIntervalSince(stillHolding) >= holdSeconds - 0.05 {
                        withAnimation(.spring(duration: 0.4)) {
                            armedForPhrase = true
                        }
                        phraseFieldFocused = true
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    }
                }
            }
            .onEnded { _ in
                if let start = chargeStart, Date().timeIntervalSince(start) < holdSeconds {
                    withAnimation(.easeOut(duration: 0.3)) { chargeStart = nil }
                } else {
                    chargeStart = nil   // already armed by the watcher task
                }
            }
    }

    // MARK: Phrase stage

    private var phraseGate: some View {
        VStack(spacing: 12) {
            Text("THE DOOR IS UNSEALED · SPEAK THE WORD")
                .chapelLabel(10, weight: .medium)
                .foregroundStyle(ChapelPalette.chapelNight.flame.opacity(0.9))

            SecureField("The word you set at the door", text: $phrase)
                .font(Chapel.ui(15, weight: .regular))
                .foregroundStyle(ChapelPalette.chapelNight.text)
                .tint(ChapelPalette.chapelNight.brass)
                .textFieldStyle(.plain)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(ChapelPalette.chapelNight.surface.opacity(0.9))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(ChapelPalette.chapelNight.brass.opacity(0.4), lineWidth: 1)
                )
                .focused($phraseFieldFocused)
                .submitLabel(.done)
                .onSubmit(attemptVerify)

            HStack(spacing: 20) {
                Button("Withdraw") {
                    withAnimation(.easeOut(duration: 0.3)) {
                        armedForPhrase = false
                        phrase = ""
                    }
                }
                .chapelLabel(13)
                .foregroundStyle(ChapelPalette.chapelNight.dim)

                Button(action: attemptVerify) {
                    Text("OPEN THE DOOR")
                        .chapelLabel(13, weight: .semibold)
                        .foregroundStyle(ChapelPalette.chapelNight.flame)
                }
            }
        }
        .padding(.horizontal, 32)
        .modifier(ShakeEffect(animatableData: CGFloat(failCount)))
        .animation(.linear(duration: 0.35), value: failCount)
    }

    private func attemptVerify() {
        let submitted = phrase
        guard !submitted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if runtime.verifyEmergencyPhrase(submitted) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onVerified(alarmID)   // AppRuntime logs the opening, then releases.
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            phrase = ""
            failCount += 1        // the door does not say why; it only does not open
        }
    }
}

/// Horizontal shake for failed phrases. Triggered by incrementing an Int; the
/// effect oscillates proportional to its value, so each failure shakes once.
private struct ShakeEffect: GeometryEffect {
    var travelDistance: CGFloat = 7
    var shakesPerUnit: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = travelDistance * sin(animatableData * .pi * shakesPerUnit * 2)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

#Preview("Chapel — summons") {
    LockChapelView(alarmID: UUID())
        .environment(AppRuntime())
        .modelContainer(for: Alarm.self, inMemory: true)
}
