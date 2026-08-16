import SwiftUI

/// The vestry: the small back room where the lamp's habits are kept.
/// Sound, the default for reciting aloud, and the emergency phrase that is
/// the only other door out of a locked chapel. Everything stays on this phone.
struct VestryView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var settings: ChapelSettings
    @State private var phraseDraft = ""
    @State private var confirmingClear = false

    init() {
        let loaded = ChapelSettingsStore.load()
        _settings = State(initialValue: loaded)
        _phraseDraft = State(initialValue: loaded.emergencyPhrase)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ChapelTheme.Background()

                Form {
                    soundSection
                    recitationSection
                    phraseSection
                    riteSection
                }
            }
            .navigationTitle("Vestry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Keep") { save() }
                        .foregroundStyle(ChapelTheme.brass)
                }
            }
        }
    }

    // MARK: Sections

    private var soundSection: some View {
        Section("THE WICK") {
            ForEach(SoundChoice.allCases, id: \.self) { choice in
                Button {
                    settings.sound = choice
                } label: {
                    HStack {
                        Text(choice.label)
                            .chapelLabel(14, weight: settings.sound == choice ? .semibold : .regular)
                            .foregroundStyle(settings.sound == choice ? ChapelTheme.flameCore : ChapelTheme.text)
                        Spacer()
                        if settings.sound == choice {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(ChapelTheme.flame)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var recitationSection: some View {
        Section("SPEECH") {
            Toggle("Recite the pack by default", isOn: $settings.recitationDefault)
                .chapelLabel(13, weight: .regular)
        }
    }

    private var phraseSection: some View {
        Section("THE DOOR") {
            if settings.hasEmergencyPhrase {
                Text("A phrase is set. The emergency door can be opened with it.")
                    .chapelLabel(10, weight: .regular)
                    .foregroundStyle(ChapelTheme.dim.opacity(0.8))

                Button("Clear the phrase") { confirmingClear = true }
                    .chapelLabel(12, weight: .regular)
                    .foregroundStyle(ChapelTheme.ember.opacity(0.9))
            } else {
                Text("No phrase is set, so the only door out of a locked chapel is finishing the rite.")
                    .chapelLabel(10, weight: .regular)
                    .foregroundStyle(ChapelTheme.dim.opacity(0.8))

                TextField("Type the phrase you will type under pressure", text: $phraseDraft)
                    .chapelLabel(14, weight: .regular)

                Button("Set the phrase") {
                    settings.emergencyPhrase = phraseDraft.trimmingCharacters(in: .whitespaces)
                }
                .chapelLabel(12, weight: .medium)
                .foregroundStyle(ChapelTheme.brass)
                .disabled(phraseDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var riteSection: some View {
        Section("THE RITE") {
            Button("Walk the first-arrival rite again") {
                ChapelSettingsStore.resetOnboarding()
            }
            .chapelLabel(12, weight: .regular)
            .foregroundStyle(ChapelTheme.dim)
        }
    }

    // MARK: Actions

    private func save() {
        ChapelSettingsStore.save(settings)
        dismiss()
    }

    private func confirmClear() {
        settings.emergencyPhrase = ""
        phraseDraft = ""
        confirmingClear = false
    }
}

#Preview {
    VestryView()
        .preferredColorScheme(.dark)
}
