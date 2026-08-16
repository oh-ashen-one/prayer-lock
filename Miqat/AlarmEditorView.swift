import SwiftUI

struct AlarmDraft {
    var label: String
    var hour: Int
    var minute: Int
    var enabled: Bool = true
    var repeatDays: Set<RepeatDay> = []
    var rakaatCount: Int = 2
    var recitationEnabled: Bool = true
    var sealPackEnabled: Bool = false

    init(alarm: LampAlarm?) {
        if let alarm {
            label = alarm.label
            hour = alarm.hour
            minute = alarm.minute
            enabled = alarm.enabled
            repeatDays = Set(alarm.repeatDays)
            rakaatCount = alarm.prayerPack.rakaatCount
            recitationEnabled = alarm.recitationEnabled
            sealPackEnabled = alarm.sealPackEnabled
        } else {
            label = "The lamp"
            hour = 5
            minute = 0
        }
    }

    var timeSeconds: Int { hour * 3600 + minute * 60 }

    func makeAlarm(id: UUID? = nil) -> LampAlarm {
        LampAlarm(
            id: id ?? UUID(),
            label: label.trimmingCharacters(in: .whitespaces),
            timeSecondsOfDay: timeSeconds,
            enabled: enabled,
            repeatDays: RepeatDay.displayOrder.filter { repeatDays.contains($0) },
            prayerPack: PrayerPack(rakaatCount: rakaatCount),
            recitationEnabled: recitationEnabled,
            sealPackEnabled: sealPackEnabled
        )
    }
}

struct AlarmEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let alarmID: UUID?
    @State private var draft: AlarmDraft

    init(alarm: LampAlarm?) {
        self.alarmID = alarm?.id
        _draft = State(initialValue: AlarmDraft(alarm: alarm))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ChapelTheme.Background()
                Form { timeSection; repeatSection; packSection }
            }
            .navigationTitle(alarmID == nil ? "A new light" : "Keep the light")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .foregroundStyle(ChapelTheme.dim)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Light it") { save() }
                .foregroundStyle(ChapelTheme.brass)
        }
    }

    private var timeSection: some View {
        Section("AT") {
            DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                .labelsHidden()
            TextField("Name the light", text: $draft.label)
        }
    }

    private var repeatSection: some View {
        Section("REPEATS") {
            HStack(spacing: 8) {
                ForEach(RepeatDay.displayOrder) { day in
                    Button(action: { toggle(day) }) {
                        Text(day.short)
                            .chapelLabel(13, weight: draft.repeatDays.contains(day) ? .semibold : .regular)
                            .frame(width: 34, height: 30)
                    }
                    .buttonStyle(.plain)
                    .background(daySquare(draft.repeatDays.contains(day)))
                }
            }
        }
    }

    private var packSection: some View {
        Section("THE PACK") {
            Stepper(value: $draft.rakaatCount, in: 1...4) {
                HStack {
                    Text("\(draft.rakaatCount) rakaat")
                        .chapelLabel(14, weight: .regular)
                    Spacer()
                    Text("stand · bow · prostrate · sit")
                        .chapelLabel(10, weight: .regular)
                        .foregroundStyle(ChapelTheme.dim.opacity(0.7))
                }
            }
            Toggle("Recite the pack aloud", isOn: $draft.recitationEnabled)
                .chapelLabel(13, weight: .regular)
            Toggle("Seal the pack with a photo", isOn: $draft.sealPackEnabled)
                .chapelLabel(13, weight: .regular)
        }
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.date(from: DateComponents(hour: draft.hour, minute: draft.minute)) ?? .now },
            set: { value in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: value)
                draft.hour = parts.hour ?? 0
                draft.minute = parts.minute ?? 0
            }
        )
    }

    private func toggle(_ day: RepeatDay) {
        if draft.repeatDays.contains(day) {
            draft.repeatDays.remove(day)
        } else {
            draft.repeatDays.insert(day)
        }
    }

    private func daySquare(_ on: Bool) -> some View {
        Rectangle()
            .fill(on ? ChapelTheme.brass.opacity(0.85) : ChapelTheme.well.opacity(0.6))
            .overlay(
                Rectangle().strokeBorder(on ? ChapelTheme.flame : ChapelTheme.hairline, lineWidth: 1)
            )
    }

    private func save() {
        var saved = LampStore.load().filter { $0.id != alarmID }
        saved.append(draft.makeAlarm(id: alarmID))
        LampStore.save(saved)
        dismiss()
    }
}
