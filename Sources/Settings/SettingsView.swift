import SwiftUI
import SwiftData

// MARK: - The Vestry (settings)
/// What the house keeps, and what it forgets: seal strictness, the word at
/// the door, the objects themselves, and a small honest ledger of every time
/// the emergency exit was used.

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.colorScheme) private var scheme

    /// Same key the locked chapel reads — strictness set here takes effect on
    /// the very next rite, no restart.
    @AppStorage("miqat.sealThreshold") private var sealThreshold: Double = SealMatchEngine.defaultThreshold

    @State private var emergencies: [EmergencyUse] = []
    @State private var sealCount = 0
    @State private var showingPhraseSheet = false
    @State private var showingSealSetup = false
    @State private var confirmReleaseSeal = false
    @State private var confirmWipe = false

    private var palette: ChapelPalette { ChapelPalette.resolve(for: scheme) }
    private var primaryInk: Color {
        scheme == .dark ? ChapelPalette.chapelNight.well : ChapelPalette.candlePaper.text
    }

    var body: some View {
        ZStack {
            ChapelBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    headerBlock
                    strictnessCard
                    wordCard
                    sealCard
                    ledgerCard
                    houseResetCard

#if DEBUG
                    Text("Simulator builds: three fingers complete the current prayer step. On a device this assist does not exist.")
                        .chapelLabel(10, weight: .regular)
                        .foregroundStyle(palette.dim.opacity(0.7))
#endif

                    Spacer(minLength: 24)
                }
                .padding(24)
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: showingSealSetup) { _, now in
            if !now { refresh() }
        }
        .sheet(isPresented: $showingPhraseSheet) { PhraseGateView() }
        .sheet(isPresented: $showingSealSetup) { SealSetupFlow() }
        .task(id: confirmReleaseSeal) {
            if confirmReleaseSeal {
                try? await Task.sleep(for: .seconds(4))
                withAnimation { confirmReleaseSeal = false }   // two taps, close together
            }
        }
        .task(id: confirmWipe) {
            if confirmWipe {
                try? await Task.sleep(for: .seconds(4))
                withAnimation { confirmWipe = false }
            }
        }
    }

    // MARK: Sections

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("THE VESTRY")
                .riteWord(28)
                .foregroundStyle(palette.text)
            Text("what the house keeps, and what it forgets")
                .chapelLabel(11, weight: .regular)
                .foregroundStyle(palette.dim.opacity(0.85))
        }
    }

    private var strictnessCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("THE SEAL — STRICTNESS")

            HStack {
                Text(String(format: "the lamp passes under %.2f", sealThreshold))
                    .font(Chapel.display(17, weight: .regular))
                    .foregroundStyle(palette.brass)
                Spacer()
            }

            Slider(value: $sealThreshold, in: SealMatchEngine.thresholdRange)
                .tint(palette.brass)

            Text("Lower: only the object itself passes. Higher: it forgives light, angle, and a hurried hand.")
                .chapelLabel(10, weight: .regular)
                .foregroundStyle(palette.dim.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .chapelCard()
    }

    private var wordCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("THE WORD AT THE DOOR")

            Text(runtime.hasEmergencyPhrase
                 ? "The word is set. Change it rarely; the ledger remembers the door, not the word."
                 : "No word yet — without one, the emergency exit cannot open at all.")
                .chapelLabel(12, weight: .regular)
                .foregroundStyle(palette.dim)

            Button(runtime.hasEmergencyPhrase ? "Change it" : "Set the word") {
                showingPhraseSheet = true
            }
            .chapelLabel(13, weight: .semibold)
            .foregroundStyle(palette.flame)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .chapelCard()
    }

    private var sealCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("THE SEAL — KEPT OBJECTS")

            Text(sealCount == 0
                 ? "Nothing kept yet. The seal needs \(SealObject.minimumCount)–\(SealObject.maximumCount)."
                 : "\(sealCount) of \(SealObject.minimumCount)–\(SealObject.maximumCap) kept.")
                .chapelLabel(12, weight: .regular)
                .foregroundStyle(palette.dim)

            HStack(spacing: 20) {
                Button("Manage") { showingSealSetup = true }
                    .chapelLabel(13, weight: .semibold)
                    .foregroundStyle(palette.brass.opacity(0.95))

                if sealCount > 0 {
                    if confirmReleaseSeal {
                        Button("release everything") { releaseAllObjects() }
                            .chapelLabel(12, weight: .semibold)
                            .foregroundStyle(palette.flame)
                    } else {
                        Button("Release all") { withAnimation { confirmReleaseSeal = true } }
                            .chapelLabel(12, weight: .regular)
                            .foregroundStyle(palette.dim.opacity(0.85))
                    }
                }

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .chapelCard()
    }

    private var ledgerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("THE LEDGER")

            if emergencies.isEmpty {
                Text("The door has never opened.")
                    .chapelLabel(12, weight: .regular)
                    .foregroundStyle(palette.dim.opacity(0.85))
            } else {
                ForEach(Array(emergencies.prefix(10))) { entry in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(palette.flame.opacity(0.9))
                            .frame(width: 5, height: 5)
                        Text("the door opened · \(entry.at.formatted(date: .abbreviated, time: .shortened))")
                            .chapelLabel(12, weight: .regular)
                            .foregroundStyle(palette.dim)
                        Spacer()
                    }
                }
                if emergencies.count > 10 {
                    Text("and \(emergencies.count - 10) more, in the store")
                        .chapelLabel(10, weight: .regular)
                        .foregroundStyle(palette.dim.opacity(0.7))
                }
            }

            Text("Every verified opening is written here — however rare, the door keeps a ledger.")
                .chapelLabel(10, weight: .regular)
                .foregroundStyle(palette.dim.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .chapelCard()
    }

    private var houseResetCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("RESET THE HOUSE")

            Text("Removes every light, kept object, and ledger entry on this phone. The word at the door remains set — it is yours to keep or change.")
                .chapelLabel(12, weight: .regular)
                .foregroundStyle(palette.dim)

            if confirmWipe {
                Button("I am sure — wipe the house") { wipeHouse() }
                    .chapelLabel(13, weight: .semibold)
                    .foregroundStyle(palette.flame)
            } else {
                Button("Reset…") { withAnimation { confirmWipe = true } }
                    .chapelLabel(13, weight: .regular)
                    .foregroundStyle(palette.dim.opacity(0.85))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .chapelCard()
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .chapelLabel(10, weight: .semibold)
            .foregroundStyle(palette.brass.opacity(0.9))
    }

    // MARK: Actions

    private func refresh() {
        var descriptor = FetchDescriptor<EmergencyUse>(
            sortBy: [SortDescriptor(\EmergencyUse.at, order: .reverse)]
        )
        emergencies = (try? context.fetch(descriptor)) ?? []
        sealCount = (try? context.fetchCount(FetchDescriptor<SealObject>())) ?? 0
    }

    private func releaseAllObjects() {
        let all = (try? context.fetch(FetchDescriptor<SealObject>())) ?? []
        for object in all { context.delete(object) }
        try? context.save()
        confirmReleaseSeal = false
        refresh()
    }

    private func wipeHouse() {
        for alarm in (try? context.fetch(FetchDescriptor<Alarm>())) ?? [] { context.delete(alarm) }
        for object in (try? context.fetch(FetchDescriptor<SealObject>())) ?? [] { context.delete(object) }
        for entry in (try? context.fetch(FetchDescriptor<EmergencyUse>())) ?? [] { context.delete(entry) }
        try? context.save()

        confirmWipe = false
        runtime.onboardingComplete = false   // the ballet is performed again on next launch
        refresh()
    }
}

// MARK: - Phrase gate (set / change the emergency word)

private struct PhraseGateView: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var a = ""
    @State private var b = ""

    private var palette: ChapelPalette { ChapelPalette.resolve(for: scheme) }

    private var valid: Bool {
        let ta = a.trimmingCharacters(in: .whitespacesAndNewlines)
        let tb = b.trimmingCharacters(in: .whitespacesAndNewlines)
        return ta == tb && ta.count >= 4
    }

    var body: some View {
        ZStack {
            ChapelBackground().ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Text("THE WORD")
                    .riteWord(24)
                    .foregroundStyle(palette.text)

                Text("Four letters or more. Stored as a digest only — Miqat never keeps the text itself.")
                    .chapelLabel(12, weight: .regular)
                    .foregroundStyle(palette.dim)

                SecureField("The word", text: $a)
                    .font(Chapel.ui(15))
                    .foregroundStyle(palette.text)
                    .tint(palette.brass)
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(palette.surface.opacity(0.7))
                    )

                SecureField("Again", text: $b)
                    .font(Chapel.ui(15))
                    .foregroundStyle(palette.text)
                    .tint(palette.brass)
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(palette.surface.opacity(0.7))
                    )

                if !valid && (!a.isEmpty || !b.isEmpty) {
                    Text("they must match, four letters or more")
                        .chapelLabel(11, weight: .regular)
                        .foregroundStyle(palette.flame.opacity(0.9))
                }

                HStack {
                    Button("Cancel") { dismiss() }
                        .chapelLabel(13)
                        .foregroundStyle(palette.dim)

                    Spacer()

                    Button(action: save) {
                        Text("SET IT")
                            .chapelLabel(13, weight: .semibold)
                            .foregroundStyle(valid ? (scheme == .dark ? palette.well : palette.text) : palette.dim.opacity(0.6))
                            .frame(width: 120, height: 46)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(palette.brass.opacity(valid ? 0.95 : 0.3))
                            )
                    }
                    .disabled(!valid)
                }

                Spacer()
            }
            .padding(24)
        }
    }

    private func save() {
        guard valid else { return }
        runtime.storeEmergencyPhrase(a)
        dismiss()
    }
}

#Preview("Vestry") {
    SettingsView()
        .environment(AppRuntime())
        .modelContainer(for: Alarm.self, SealObject.self, EmergencyUse.self, inMemory: true)
}
