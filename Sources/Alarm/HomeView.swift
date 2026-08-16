import SwiftUI
import SwiftData

// MARK: - Tabs
// Two rooms in the house: the Lamp (clock, lights) and the Vestry (settings).
// No third tab; everything else is a sheet or a door.

struct MainTabs: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Lamp", systemImage: "flame") }
            SettingsView()
                .tabItem { Label("Vestry", systemImage: "slider.horizontal.3") }
        }
        .tint(ChapelPalette.resolve(for: scheme).brass)
    }
}

// MARK: - Home (the Lamp)

struct HomeView: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme

    @State private var alarms: [Alarm] = []
    @State private var editingNew = false
    @State private var editingExisting: Alarm?
    @State private var watcherTask: Task<Void, Never>?

    private var palette: ChapelPalette { ChapelPalette.resolve(for: scheme) }

    /// The earliest next fire across all enabled alarms. Drives the header
    /// line and the brass pip on the clock ring.
    private var nextLight: (date: Date, alarm: Alarm)? {
        guard !alarms.isEmpty else { return nil }
        var best: (Date, Alarm)?
        for alarm in alarms where alarm.enabled {
            guard let fire = AlarmScheduler.nextOccurrence(after: .now, spec: alarm.spec) else { continue }
            if best == nil || fire < best!.0 { best = (fire, alarm) }
        }
        guard let b = best else { return nil }
        return (date: b.0, alarm: b.1)
    }

    private var clockMarkerMinutes: Double? {
        guard let fire = nextLight?.date else { return nil }
        let c = Calendar.current.dateComponents([.hour, .minute], from: fire)
        return Double(c.hour ?? 0) * 60 + Double(c.minute ?? 0)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ChapelBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 26) {
                    headerBlock

                    LampClockLiveView(alarmMinutes: clockMarkerMinutes)
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: 340)

                    nextLightLine
                    hairline

                    if alarms.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 12) {
                            ForEach(alarms) { alarm in
                                AlarmRowView(alarm: alarm, onToggleEnabled: { setEnabled($0, for: alarm) }) {
                                    editingExisting = alarm
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 96)   // room for the + button
            }

            plusButton
                .padding(28)
        }
        .onAppear {
            refresh()
            startWatcherIfNeeded()
        }
        .onChange(of: runtime.lockedAlarmID) { _, locked in
            if locked == nil { refresh() }   // the rite paid; the list may have changed
        }
        .onDisappear(perform: stopWatcher)
        .sheet(isPresented: $editingNew) { AlarmEditorView(alarm: nil) }
        .sheet(item: $editingExisting) { alarm in AlarmEditorView(alarm: alarm) }
    }

    // MARK: Blocks

    private var headerBlock: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("MIQAT")
                    .chapelLabel(15, weight: .semibold)
                    .foregroundStyle(palette.brass)
                Text("an alarm as a threshold")
                    .chapelLabel(10, weight: .regular)
                    .foregroundStyle(palette.dim.opacity(0.85))
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var nextLightLine: some View {
        if let nl = nextLight {
            VStack(spacing: 4) {
                Text("NEXT LIGHT")
                    .chapelLabel(10, weight: .medium)
                    .foregroundStyle(palette.dim)
                Text("\(nl.alarm.label.isEmpty ? "the rite" : nl.alarm.label) · \(AlarmScheduler.humanDescription(of: nl.date))")
                    .font(Chapel.display(17, weight: .regular))
                    .foregroundStyle(palette.text)
            }
        } else {
            Text("the house is quiet")
                .chapelLabel(12, weight: .regular)
                .foregroundStyle(palette.dim.opacity(0.85))
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(palette.brass.opacity(0.28))
            .frame(height: 1)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("No lights yet.")
                .riteWord(22)
                .foregroundStyle(palette.text.opacity(0.9))
            Text("Light the first lamp and give it a rite.")
                .chapelLabel(12, weight: .regular)
                .foregroundStyle(palette.dim)
            Button("Light the first lamp") { editingNew = true }
                .chapelLabel(13, weight: .semibold)
                .foregroundStyle(palette.flame)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var plusButton: some View {
        Button { editingNew = true } label: {
            Image(systemName: "plus")
                .font(Chapel.ui(20, weight: .semibold))
                .foregroundStyle(palette.flame)
                .frame(width: 54, height: 54)
                .background(
                    Circle()
                        .fill(palette.surface.opacity(0.9))
                )
                .overlay(
                    Circle()
                        .strokeBorder(palette.brass.opacity(0.5), lineWidth: 1)
                )
        }
        .accessibilityLabel("Add an alarm")
    }

    // MARK: Data

    private func refresh() {
        var descriptor = FetchDescriptor<Alarm>(sortBy: [SortDescriptor(\Alarm.timeSecondsOfDay)])
        alarms = (try? context.fetch(descriptor)) ?? []

        // Re-arm on launch: edits and toggles may have drifted from the
        // pending notification set. schedule() replaces, so this is idempotent.
        for alarm in alarms where alarm.enabled {
            AlarmScheduler.schedule(alarm)
        }
    }

    private func setEnabled(_ enabled: Bool, for alarm: Alarm) {
        alarm.enabled = enabled
        try? context.save()
        if enabled {
            AlarmScheduler.schedule(alarm)
        } else {
            AlarmScheduler.unschedule(alarm)
        }
    }

    // MARK: Foreground watcher
    //
    // While the app is on screen, an unpaid alarm does not wait for a banner:
    // every four seconds we ask "is anything owed right now?" and, if so, lock
    // the chapel directly. (System notifications cover backgrounded/killed.)

    private func startWatcherIfNeeded() {
        guard watcherTask == nil else { return }
        let runtimeRef = runtime
        let contextRef = context

        watcherTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))

                guard runtimeRef.lockedAlarmID == nil else { continue }   // chapel already holds the screen

                var descriptor = FetchDescriptor<Alarm>(sortBy: [SortDescriptor(\Alarm.timeSecondsOfDay)])
                let list = (try? contextRef.fetch(descriptor)) ?? []

                if let dueID = AlarmScheduler.dueAlarms(now: .now, alarms: list).first {
                    runtimeRef.lock(alarmID: dueID)
                }
            }
        }
    }

    private func stopWatcher() {
        watcherTask?.cancel()
        watcherTask = nil
    }
}

// MARK: - Alarm row

struct AlarmRowView: View {
    let alarm: Alarm
    var onToggleEnabled: (Bool) -> Void
    var onTap: () -> Void

    @Environment(\.colorScheme) private var scheme
    private var palette: ChapelPalette { ChapelPalette.resolve(for: scheme) }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(alarm.timeLabel)
                    .font(Chapel.display(26, weight: .medium))
                    .foregroundStyle(alarm.enabled ? palette.text : palette.dim)

                Text(alarm.label.isEmpty ? "untitled light" : alarm.label)
                    .chapelLabel(13, weight: .regular)
                    .foregroundStyle(palette.dim)

                Text(alarm.repeatsLabel.uppercased())
                    .chapelLabel(9, weight: .medium)
                    .foregroundStyle(palette.brass.opacity(0.75))
            }

            Spacer(minLength: 8)

            Text(alarm.packsLabel)
                .chapelLabel(10, weight: .regular)
                .foregroundStyle(palette.dim.opacity(0.85))

            Toggle("", isOn: Binding(get: { alarm.enabled }, set: onToggleEnabled))
                .labelsHidden()
                .tint(palette.brass)
                .scaleEffect(0.78, anchor: .center)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(palette.surface.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(palette.brass.opacity(0.25), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

#Preview("Home") {
    MainTabs()
        .environment(AppRuntime())
        .modelContainer(for: Alarm.self, SealObject.self, EmergencyUse.self, inMemory: true)
}
