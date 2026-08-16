import SwiftUI
import SwiftData
import Foundation

struct HomeView: View {
    @EnvironmentObject private var runtime: AppRuntime
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Alarm.hour), SortDescriptor(\Alarm.minute)]) private var alarms: [Alarm]
    @State private var showingNewAlarm = false

    var body: some View {
        NavigationStack {
            List {
                Section("Prayer Lock") {
                    Toggle(isOn: $runtime.isPrayerLocked) {
                        Label("Lock During Prayer", systemImage: "lock")
                    }
                }

                Section("Alarms") {
                    ForEach(alarms, id: \.id) { alarm in
                        Toggle(isOn: Binding(get: { alarm.isEnabled }, set: { alarm.isEnabled = $0 })) {
                            HStack {
                                Text(alarm.name)
                                Spacer()
                                Text(Self.formattedTime(hour: alarm.hour, minute: alarm.minute))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: deleteAlarms)

                    Button {
                        showingNewAlarm = true
                    } label: {
                        Label("Add Alarm", systemImage: "plus")
                    }
                }

                Section("Explore") {
                    NavigationLink {
                        RecitationView()
                    } label: {
                        Label("Recite", systemImage: "speaker.wave.2")
                    }

                    NavigationLink {
                        SealSetupFlow()
                    } label: {
                        Label("Seal Setup", systemImage: "camera")
                    }

                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("Miqat")
        }
        .sheet(isPresented: $showingNewAlarm) {
            AlarmEditorView()
        }
    }

    private static func formattedTime(hour: Int, minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }

    private func deleteAlarms(at offsets: IndexSet) {
        for offset in offsets {
            context.delete(alarms[offset])
        }
    }
}

private func makeHomePreviewContainer() -> ModelContainer {
    do {
        return try ModelContainer(
            for: Schema([Alarm.self, SealObject.self, EmergencyUse.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    } catch {
        fatalError("Failed to create Home preview container: \(error)")
    }
}

#Preview {
    HomeView()
        .environmentObject(AppRuntime())
        .modelContainer(makeHomePreviewContainer())
}
