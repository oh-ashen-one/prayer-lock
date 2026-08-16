import SwiftUI
import SwiftData

/// The editor. Two jobs: shape a new light, or mend an existing one. Changes
/// land only when "Keep" is pressed — no accidental half-edits, and the
/// schedule re-arms from "now" at that moment.

struct AlarmEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    private let existingAlarm: Alarm?
    @State private var draft = AlarmDraft()
    @State private var sealCount: Int = 0
    @State private var showingSealSetup = false

    init(alarm: Alarm?) {
        self.existingAlarm = alarm
        _draft = State(initialValue: AlarmDraft(from: alarm))
    }

    private var palette: ChapelPalette { ChapelPalette.resolve(for: scheme) }
    private var isEditing: Bool { existingAlarm != nil }

    /// Dark ink over brass in the night room; near-black over the warmer
    /// candle-paper brass by day. Either way, the button reads as lit metal.
    private var primaryButtonInk: Color {
        scheme == .dark ? ChapelPalette.chapelNight.well : ChapelPalette.candlePaper.text
    }

    var body: some View {
        ZStack {
            ChapelBackground().ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    Text(isEditing ? "The light" : "A new light")
                        .riteWord(28)
                        .foregroundStyle(palette.text)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    timeCard
                    repeatsCard
                    nameCard
                    soundCard
                    prayerCard
                    recitationCard
                    sealCard

                    actionsBlock
                }
                .padding(24)
                .padding(.bottom, 30)
            }
        }
        .task { recountSealObjects() }
        .onChange(of: showingSealSetup) { _, now in
            if !now { recountSealObjects() }
        }
        .sheet(isPresented: $showingSealSetup) { SealSetupFlow() }
    }

    // MARK: Cards

    private var timeCard: some View {
        VStack(spacing: 14) {
            Text("AT")
                .chapelLabel(10, weight: .medium)
                .foregroundStyle(palette.dim)

            Text(String(format: "%02d:%02d", draft.hour, draft.minute))
                .font(Chapel.display(46, weight: .light))
                .foregroundStyle(palette.brass)

            DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
        .chapelCard()
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(from: DateComponents(hour: draft.hour, minute: draft.minute)) ?? .now
            },
            set: { newValue in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                draft.hour = c.hour ?? 0
                draft.minute = c.minute ?? 0
            }
        )
    }

    private var repeatsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("REPEATS")
                .chapelLabel(10, weight: .medium)
                .foregroundStyle(palette.dim)

            HStack(spacing: 8) {
                ForEach(RepeatDay.allCases) { day in
                    repeatChip(day)
                }
            }

            Text(draft.repeats.isEmpty
                 ? "once — then the light rests"
                 : draft.repeats.map(\.shortName).joined(separator: " · "))
                .chapelLabel(11, weight: .regular)
                .foregroundStyle(palette.dim.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .chapelCard()
    }

    private func repeatChip(_ day: RepeatDay) -> some View {
        let isOn = draft.repeats.contains(day)
        return Button {
            if isOn {
                draft.repeats.removeAll { $0 == day }
            } else {
                draft.repeats.append(day)
                draft.repeats.sort { $0.rawValue < $1.rawValue }
            }
        } label: {
            Text(day.shortName)
                .chapelLabel(12, weight: isOn ? .semibold : .regular)
                .frame(width: 40, height: 34)
                .background(
                    Capsule()
                        .fill(palette.brass.opacity(isOn ? 0.28 : 0.06))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(palette.brass.opacity(isOn ? 0.7 : 0.25), lineWidth: 1)
                )
                .foregroundStyle(isOn ? palette.brass : palette.dim)
        }
    }

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NAME THE LIGHT")
                .chapelLabel(10, weight: .medium)
                .foregroundStyle(palette.dim)

            TextField("Fajr", text: $draft.label)
                .font(Chapel.display(20, weight: .regular))
                .foregroundStyle(palette.text)
                .tint(palette.brass)
                .padding(.horizontal, 14)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(palette.well.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(palette.brass.opacity(0.3), lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .chapelCard()
    }

    private var soundCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SOUND")
                .chapelLabel(10, weight: .medium)
                .foregroundStyle(palette.dim)

            ForEach(SoundChoice.allCases) { choice in
                Button { draft.sound = choice } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(draft.sound == choice ? palette.flame : Color.clear)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(choice.label)
                                .chapelLabel(14, weight: draft.sound == choice ? .semibold : .regular)
                                .foregroundStyle(draft.sound == choice ? palette.text : palette.dim)
                            Text(choice.detail)
                                .chapelLabel(10, weight: .regular)
                                .foregroundStyle(palette.dim.opacity(0.75))
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .chapelCard()
    }

    private var prayerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PRAYER PACK")
                        .chapelLabel(10, weight: .medium)
                        .foregroundStyle(palette.dim)
                    Text("the rakaʿāt, held at each posture")
                        .chapelLabel(10, weight: .regular)
                        .foregroundStyle(palette.dim.opacity(0.75))
                }
                Spacer()
                Toggle("", isOn: $draft.prayerEnabled)
                    .labelsHidden()
                    .tint(palette.brass)
            }

            if draft.prayerEnabled {
                HStack(spacing: 14) {
                    Text("Rakaʿāt")
                        .chapelLabel(13)
                        .foregroundStyle(palette.text.opacity(0.85))

                    Stepper(value: $draft.rakaats, in: 1...4) {
                        Text("\(draft.rakaats)")
                            .font(Chapel.display(20, weight: .semibold))
                            .foregroundStyle(palette.brass)
                    }
                    .tint(palette.brass)

                    Spacer()
                }

                Text("stand → bow → prostrate (phone on floor) → sit")
                    .chapelLabel(10, weight: .regular)
                    .foregroundStyle(palette.dim.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .chapelCard()
    }

    private var recitationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("RECITATION")
                        .chapelLabel(10, weight: .medium)
                        .foregroundStyle(palette.dim)
                    Text("short lines, read aloud on this device")
                        .chapelLabel(10, weight: .regular)
                        .foregroundStyle(palette.dim.opacity(0.75))
                }
                Spacer()
                Toggle("", isOn: $draft.recitationEnabled)
                    .labelsHidden()
                    .tint(palette.brass)
            }

            if draft.recitationEnabled {
                TextEditor(text: $draft.phrasesText)
                    .font(Chapel.ui(15, weight: .regular))
                    .foregroundStyle(palette.text)
                    .scrollContentBackground(.hidden)
                    .frame(height: 84)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(palette.well.opacity(0.5))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(palette.brass.opacity(0.3), lineWidth: 1)
                    )

                Text("one phrase per line")
                    .chapelLabel(10, weight: .regular)
                    .foregroundStyle(palette.dim.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .chapelCard()
    }

    private var sealCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SEAL PACK")
                        .chapelLabel(10, weight: .medium)
                        .foregroundStyle(palette.dim)
                    Text("a live photo of a kept object, after prayer")
                        .chapelLabel(10, weight: .regular)
                        .foregroundStyle(palette.dim.opacity(0.75))
                }
                Spacer()
                Toggle("", isOn: $draft.sealEnabled)
                    .labelsHidden()
                    .tint(palette.brass)
            }

            if draft.sealEnabled {
                if sealCount >= SealObject.minimumCount {
                    Text("the seal is kept — \(sealCount) objects")
                        .chapelLabel(12, weight: .regular)
                        .foregroundStyle(palette.brass.opacity(0.9))
                } else {
                    Text("the seal needs at least \(SealObject.minimumCount) kept objects (\(sealCount) now)")
                        .chapelLabel(12, weight: .regular)
                        .foregroundStyle(palette.flame.opacity(0.9))

                    Button("Keep the objects") { showingSealSetup = true }
                        .chapelLabel(13, weight: .semibold)
                        .foregroundStyle(palette.flame)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .chapelCard()
    }

    // MARK: Actions

    private var actionsBlock: some View {
        VStack(spacing: 12) {
            Button(action: save) {
                Text(isEditing ? "KEEP THE LIGHT" : "LIGHT IT")
                    .chapelLabel(14, weight: .semibold)
                    .foregroundStyle(primaryButtonInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(palette.brass)
                    )
            }

            if isEditing, let existing = existingAlarm {
                Button("Unmake this alarm") { remove(existing) }
                    .chapelLabel(12, weight: .regular)
                    .foregroundStyle(palette.flame.opacity(0.85))
            }
        }
    }

    // MARK: Persistence

    private func recountSealObjects() {
        let count = (try? context.fetchCount(FetchDescriptor<SealObject>())) ?? 0
        sealCount = count
    }

    private func save() {
        let seconds = draft.hour * 3_600 + draft.minute * 60
        let phrases = draft.phrasesText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let target: Alarm
        if let existing = existingAlarm {
            existing.timeSecondsOfDay = seconds
            existing.label = draft.label.trimmingCharacters(in: .whitespaces)
            existing.sound = draft.sound
            existing.repeatDays = draft.repeats
            existing.prayerPackEnabled = draft.prayerEnabled
            existing.rakaatCount = draft.rakaats
            existing.recitationEnabled = draft.recitationEnabled
            existing.recitationPhrases = phrases.isEmpty ? Alarm.defaultRecitationPhrases : phrases
            existing.sealPackEnabled = draft.sealEnabled
            target = existing
        } else {
            let fresh = Alarm(
                timeSecondsOfDay: seconds,
                label: draft.label.trimmingCharacters(in: .whitespaces),
                sound: draft.sound,
                prayerPackEnabled: draft.prayerEnabled,
                rakaatCount: draft.rakaats,
                recitationEnabled: draft.recitationEnabled,
                recitationPhrases: phrases.isEmpty ? Alarm.defaultRecitationPhrases : phrases,
                sealPackEnabled: draft.sealEnabled,
                repeatDays: draft.repeats
            )
            context.insert(fresh)
            target = fresh
        }

        try? context.save()
        AlarmScheduler.schedule(target)   // resync; no-ops toward pending if disabled
        dismiss()
    }

    private func remove(_ alarm: Alarm) {
        AlarmScheduler.unschedule(alarm)
        context.delete(alarm)
        try? context.save()
        dismiss()
    }
}

// MARK: - Draft (edits live here until "keep")

private struct AlarmDraft {
    var hour: Int
    var minute: Int
    var label: String
    var sound: SoundChoice
    var repeats: [RepeatDay]
    var prayerEnabled: Bool
    var rakaats: Int
    var recitationEnabled: Bool
    var phrasesText: String
    var sealEnabled: Bool

    init(from alarm: Alarm?) {
        if let a = alarm {
            hour = a.hour
            minute = a.minute
            label = a.label
            sound = a.sound
            repeats = a.repeatDays
            prayerEnabled = a.prayerPackEnabled
            rakaats = a.rakaatCount
            recitationEnabled = a.recitationEnabled
            phrasesText = a.recitationPhrases.joined(separator: "\n")
            sealEnabled = a.sealPackEnabled
        } else {
            hour = 5
            minute = 0
            label = ""
            sound = .bell
            repeats = []
            prayerEnabled = true
            rakaats = 4
            recitationEnabled = false
            phrasesText = Alarm.defaultRecitationPhrases.joined(separator: "\n")
            sealEnabled = false
        }
    }
}

#Preview("Editor (new)") {
    AlarmEditorView(alarm: nil)
        .environment(AppRuntime())
        .modelContainer(for: Alarm.self, SealObject.self, EmergencyUse.self, inMemory: true)
}
