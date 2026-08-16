import SwiftUI
import SwiftData

@main
struct MiqatApp: App {
    @StateObject private var runtime = AppRuntime()

    static let sharedContainer: ModelContainer = {
        do {
            return try ModelContainer(
                for: Schema([Alarm.self, SealObject.self, EmergencyUse.self]),
                configurations: ModelConfiguration(isStoredInMemoryOnly: false)
            )
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(runtime)
        }
        .modelContainer(Self.sharedContainer)
    }
}
