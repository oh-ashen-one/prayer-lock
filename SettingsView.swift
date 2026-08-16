import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject private var runtime: AppRuntime

    var body: some View {
        Form {
            Section("Prayer Lock") {
                Toggle(isOn: $runtime.isPrayerLocked) {
                    Text("Lock During Prayer")
                }

                Button(runtime.isPrayerLocked ? "Unlock Now" : "Lock Now") {
                    runtime.togglePrayerLock()
                }
            }

            Section("Recitation") {
                LabeledContent("Recitation volume") {
                    Slider(value: $runtime.recitationVolume, in: 0...2)
                }
            }

            Section("About") {
                Text("Miqat Prayer Lock")
                    .font(.headline)

                Text("Version 1.0")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}

private func makeSettingsPreviewContainer() -> ModelContainer {
    do {
        return try ModelContainer(
            for: Schema([Alarm.self, SealObject.self, EmergencyUse.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    } catch {
        fatalError("Failed to create Settings preview container: \(error)")
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppRuntime())
        .modelContainer(makeSettingsPreviewContainer())
}
