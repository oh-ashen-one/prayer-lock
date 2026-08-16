import Foundation
import SwiftData

// MARK: - Value types (pure; the scheduler and its tests never touch a container)

/// A weekday. rawValue 0 = Sunday, matching (Calendar.component(.weekday) - 1).
enum RepeatDay: Int, Codable, CaseIterable, Identifiable {
    case sunday = 0, monday, tuesday, wednesday, thursday, friday, saturday

    var id: Int { rawValue }

    var shortName: String {
        switch self {
        case .sunday: "Sun"
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        }
    }

    /// Foundation's Calendar weekday numbering is 1 = Sunday ... 7 = Saturday.
    var calendarWeekday: Int { rawValue + 1 }

    static func fromCalendarWeekday(_ weekday: Int) -> RepeatDay? {
        RepeatDay(rawValue: (weekday - 1).clamped(to: 0...6))
    }
}

/// What the alarm means, stripped of identity and persistence.
struct AlarmSpec: Equatable {
    var timeSecondsOfDay: Int      // 0 ..< 86400
    var repeatDays: [RepeatDay]    // empty = one-shot (fires once, then disables)

    static func isValidTime(_ seconds: Int) -> Bool {
        (0..<86_400).contains(seconds)
    }

    var isOneShot: Bool { repeatDays.isEmpty }
}

enum SoundChoice: String, Codable, CaseIterable, Identifiable {
    case bell = "bell"             // system default notification tone
    case chime = "chime"           // bundled lamp chime if present, else bell
    case stillness = "stillness"   // silent — the screen alone wakes you

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bell: "Bell"
        case .chime: "Lamp chime"
        case .stillness: "Stillness (silent)"
        }
    }

    var detail: String {
        switch self {
        case .bell: "The usual alarm sound, out of respect."
        case .chime: "A soft brass chime. Falls back to the bell if absent."
        case .stillness: "No sound at all. Only light. The rite is the wake-up."
        }
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Models

@Model
final class Alarm {
    var id: UUID
    var timeSecondsOfDay: Int          // 0 ..< 86400, seconds from midnight
    var label: String
    var soundRaw: String

    // Prayer pack.
    var prayerPackEnabled: Bool
    var rakaatCount: Int               // 1...4

    // Recitation (optional, on-device Speech).
    var recitationEnabled: Bool
    var recitationPhrases: [String]

    // Seal pack (optional, Vision feature prints).
    var sealPackEnabled: Bool

    var enabled: Bool
    var repeatsRaw: [Int]              // RepeatDay rawValues, sorted
    var lastFiredAt: Date?             // keeps the foreground watcher honest

    init(
        timeSecondsOfDay: Int,
        label: String = "",
        sound: SoundChoice = .bell,
        prayerPackEnabled: Bool = true,
        rakaatCount: Int = 4,
        recitationEnabled: Bool = false,
        recitationPhrases: [String] = Alarm.defaultRecitationPhrases,
        sealPackEnabled: Bool = false,
        repeatDays: [RepeatDay] = []
    ) {
        self.id = UUID()
        self.timeSecondsOfDay = timeSecondsOfDay.clamped(to: 0...86_399)
        self.label = label
        self.soundRaw = sound.rawValue
        self.prayerPackEnabled = prayerPackEnabled
        self.rakaatCount = rakaatCount.clamped(to: 1...4)
        self.recitationEnabled = recitationEnabled
        self.recitationPhrases = recitationPhrases
        self.sealPackEnabled = sealPackEnabled
        self.enabled = true
        self.repeatsRaw = repeatDays.map(\.rawValue).sorted()
    }

    // MARK: Derived, human-readable pieces

    static let defaultRecitationPhrases = [
        "Subhan Allah, walhamdulillah, wa la ilaha illallah, wallahu akbar."
    ]

    var sound: SoundChoice {
        get { SoundChoice(rawValue: soundRaw) ?? .bell }
        set { soundRaw = newValue.rawValue }
    }

    var repeatDays: [RepeatDay] {
        get { repeatsRaw.compactMap(RepeatDay.init(rawValue:)) }
        set { repeatsRaw = newValue.map(\.rawValue).sorted() }
    }

    var spec: AlarmSpec {
        AlarmSpec(timeSecondsOfDay: timeSecondsOfDay, repeatDays: repeatDays)
    }

    var hour: Int { timeSecondsOfDay / 3_600 }
    var minute: Int { (timeSecondsOfDay % 3_600) / 60 }

    var timeLabel: String {
        String(format: "%02d:%02d", hour, minute)
    }

    var repeatsLabel: String {
        repeatDays.isEmpty ? "Once" : repeatDays.map(\.shortName).joined(separator: ", ")
    }

    var packsLabel: String {
        var parts: [String] = []
        if prayerPackEnabled { parts.append("\(rakaatCount) rakaʿāt") }
        if recitationEnabled { parts.append("recitation") }
        if sealPackEnabled { parts.append("seal") }
        return parts.isEmpty ? "light only" : parts.joined(separator: " · ")
    }

    /// Seconds of day for a given date — used by the foreground watcher and tests.
    static func secondsOfDay(for date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return (c.hour ?? 0) * 3_600 + (c.minute ?? 0) * 60 + (c.second ?? 0)
    }
}

/// One photographed household object in the Seal pack. The thumbnail is a
/// downscaled JPEG (~768 px); the Vision feature print (the "embedding") is
/// computed from it on demand — there is no persisted ML artifact to rot.
@Model
final class SealObject {
    var id: UUID
    var name: String             // user-given ("the brass lantern") or numbered
    var thumbnailJPEG: Data
    var createdAt: Date

    init(name: String, thumbnailJPEG: Data) {
        self.id = UUID()
        self.name = name
        self.thumbnailJPEG = thumbnailJPEG
        self.createdAt = Date()
    }

    /// 5..15 objects is the Seal contract.
    static let minimumCount = 5
    static let maximumCount = 15
}

/// A stamped entry whenever the emergency exit is used. It exists so the door,
/// however rare it opens, has a ledger.
@Model
final class EmergencyUse {
    var id: UUID
    var alarmID: UUID?
    var at: Date

    init(alarmID: UUID?, at: Date = Date()) {
        self.id = UUID()
        self.alarmID = alarmID
        self.at = at
    }
}
