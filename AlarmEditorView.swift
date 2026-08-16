import SwiftUI
import SwiftData
import Foundation

struct AlarmDraft {
    var name: String
    var hour: Int
    var minute: Int
    var isEnabled: Bool

    init(from alarm: Alarm?) {
        if let alarm {
            name = alarm.name
            hour = alarm.hour
            minute = alarm.minute
            isEnabled = alarm.isEnabled
        } else {
            name = "Prayer Alarm"
            hour = 6
            minute = 0
            isEnabled = true
        }
    }
}

struct AlarmEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var draft = AlarmDraft(from: nil)

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Alarm name", text: $draft.name)
                }

                Section("Time") {
                    Stepper(value: $draft.hour, in: 0...23) {
                        Text("Hour: \(String(format: "%02d", draft.hour))")
                    }

                    Stepper(value: $draft.minute, in: 0...59) {
                        Text("Minute: \(String(format: "%02d", draft.minute))")
                    }
                }

                Section {
                    Toggle("Enabled", isOn: $draft.isEnabled)
                }
            }
            .navigationTitle("New Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private func save() {
        let alarm = Alarm(
            name: draft.name,
            hour: draft.hour,
            minute: draft.minute,
            isEnabled: draft.isEnabled
        )
        context.insert(alarm)
        dismiss()
    }
}

private func makeAlarmEditorPreviewContainer() -> ModelContainer {
    do {
        return try ModelContainer(
            for: Schema([Alarm.self, SealObject.self, EmergencyUse.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    } catch {
        fatalError("Failed to create Alarm Editor preview container: \(error)")
    }
}

#Preview {
    AlarmEditorView()
        .modelContainer(makeAlarmEditorPreviewContainer())
}
