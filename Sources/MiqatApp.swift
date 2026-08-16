import SwiftUI
import SwiftData

@main
struct MiqatApp: App {
    @State private var runtime = AppRuntime()
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(
                for: Alarm.self, SealObject.self, EmergencyUse.self
            )
        } catch {
            // The vestry cannot be opened; there is nothing to recover into.
            fatalError("Miqat could not open its on-device store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(runtime)
        }
        .modelContainer(container)
        // Deep link: miqat://chapel/<alarm-id> — the door handle of a fired
        // alarm delivered as an iOS notification tap.
        .onOpenURL { url in
            runtime.route(url: url)
        }
    }
}

/// Root routing. The whole app is either: the onboarding rite, the house (home
/// + vestry), or — over everything — the locked chapel.
struct RootView: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.modelContext) private var modelContext
    @State private var booted = false

    private var isLocked: Bool { runtime.lockedAlarmID != nil }

    var body: some View {
        ZStack {
            ChapelBackground()
                .ignoresSafeArea()

            if runtime.onboardingComplete {
                MainTabs()
            } else {
                OnboardingFlow()
            }
        }
        // The chapel is a full-screen cover with no dismiss gesture: there is
        // deliberately no slide-to-stop. The rite, or the logged emergency exit.
        .fullScreenCover(
            isPresented: Binding(get: { isLocked }, set: { _ in })
        ) {
            if let alarmID = runtime.lockedAlarmID {
                LockChapelView(alarmID: alarmID)
                    .ignoresSafeArea()
            }
        }
        .statusBarHidden(isLocked)
        .persistentSystemOverlays(isLocked ? .hidden : .automatic)
        .onAppear {
            guard !booted else { return }
            booted = true
            runtime.boot()                            // notification plumbing, idempotent
            runtime.restoreInterruptedRite(in: modelContext)  // killed mid-rite? reopen, restart
        }
    }
}
