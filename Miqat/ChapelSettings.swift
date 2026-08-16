import Foundation

/// The one small document the chapel keeps about its own habits: how the
/// wick sounds, whether it speaks the rite aloud, and the emergency phrase
/// that is the only other door out of a locked chapel. Local only, no cloud.
struct ChapelSettings: Codable {
    var sound: SoundChoice = .bell
    var recitationDefault: Bool = true
    /// The emergency exit phrase. Empty means the door is sealed shut and
    /// only completing the rite releases the phone.
    var emergencyPhrase: String = ""

    init(
        sound: SoundChoice = .bell,
        recitationDefault: Bool = true,
        emergencyPhrase: String = ""
    ) {
        self.sound = sound
        self.recitationDefault = recitationDefault
        self.emergencyPhrase = emergencyPhrase
    }

    var hasEmergencyPhrase: Bool { !emergencyPhrase.isEmpty }
}

/// The on-disk home of the chapel's habits and the phrase behind the door.
enum ChapelSettingsStore {

    private static var settingsURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("miqat-settings.json")
    }

    private static var onboardingURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("miqat-onboarded.txt")
    }

    static func load() -> ChapelSettings {
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONDecoder().decode(ChapelSettings.self, from: data)
        else { return ChapelSettings() }
        return settings
    }

    static func save(_ settings: ChapelSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        _ = try? data.write(to: settingsURL, options: .atomic)
    }

    /// Whether the first-arrival rite has been walked. Not a gate: it can
    /// always be re-opened from the vestry.
    static var hasOnboarded: Bool {
        FileManager.default.fileExists(atPath: onboardingURL.path)
    }

    static func markOnboarded() {
        try? Data("lit".utf8).write(to: onboardingURL, options: .atomic)
    }

    static func resetOnboarding() {
        try? FileManager.default.removeItem(at: onboardingURL)
    }

    /// The emergency door is closed until a phrase is set.
    static var canUseEmergencyExit: Bool {
        load().hasEmergencyPhrase
    }
}
