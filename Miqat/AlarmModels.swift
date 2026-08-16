import Foundation

enum RepeatDay: Int, Codable, CaseIterable, Identifiable {
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7
    case sunday = 1

    var id: Int { rawValue }

    /// The Gregorian weekday this day stands for (Calendar.weekday).
    var calendarWeekday: Int { rawValue }

    /// One letter, for the day's square.
    var short: String {
        switch self {
        case .monday: return "M"
        case .tuesday: return "T"
        case .wednesday: return "W"
        case .thursday: return "T"
        case .friday: return "F"
        case .saturday: return "S"
        case .sunday: return "S"
        }
    }

    /// The full name, for the editor's running line.
    var long: String {
        switch self {
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        case .sunday: return "Sunday"
        }
    }

    /// Calendar.weekday values run Sunday-first; so do the day squares.
    static var displayOrder: [RepeatDay] { [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday] }
}

/// How the lamp sounds when it fires. Kept as raw data for Codable.
enum SoundChoice: Int, Codable, CaseIterable {
    case bell = 0
    case chime = 1
    case stillness = 2

    var label: String {
        switch self {
        case .bell: return "Bell"
        case .chime: return "Chime"
        case .stillness: return "Stillness"
        }
    }
}

/// One rite kept with an alarm: how many rakaat to stand, bow, prostrate
/// and sit through. A pack is one to four rakaat; the four postures are
/// counted per rakaat by the rite itself.
struct PrayerPack: Codable, Equatable {
    var rakaatCount: Int

    init(rakaatCount: Int) {
        self.rakaatCount = min(max(1, rakaatCount), 4)
    }

    /// The four postures of a single rakaat, in order. The rite walks them
    /// once per rakaat of the pack.
    static let postures = ["Stand", "Bow", "Prostrate", "Sit"]

    var label: String {
        "\(rakaatCount) \(rakaatCount == 1 ? "rakaat" : "rakaat")"
    }

    /// The whole rite spelled out for the notification: "3 rakaat, recited, sealed."
    func packsLabel(recitation: Bool, seal: Bool) -> String {
        var parts = [label]
        if recitation { parts.append("recited") }
        if seal { parts.append("sealed") }
        return parts.joined(separator: ", ")
    }
}

/// An alarm kept on this device only. No cloud, no account: the whole life
/// of a light is Codable data in an on-disk store.
struct LampAlarm: Identifiable, Codable, Equatable {
    var id = UUID()
    var label: String
    var timeSecondsOfDay: Int
    var enabled: Bool

    /// Empty means one-shot: it fires once and rests. Non-empty means the
    /// light returns on those days.
    var repeatDays: [RepeatDay]

    var prayerPack: PrayerPack
    /// Read the pack aloud while the rite is kept.
    var recitationEnabled: Bool
    /// Seal the pack: a household object is photographed before and after.
    var sealPackEnabled: Bool

    var sound: SoundChoice

    init(
        id: UUID = UUID(),
        label: String,
        timeSecondsOfDay: Int,
        enabled: Bool = true,
        repeatDays: [RepeatDay] = [],
        prayerPack: PrayerPack = PrayerPack(rakaatCount: 2),
        recitationEnabled: Bool = true,
        sealPackEnabled: Bool = false,
        sound: SoundChoice = .bell
    ) {
        self.id = id
        self.label = label
        self.timeSecondsOfDay = min(max(0, timeSecondsOfDay), 86399)
        self.enabled = enabled
        self.repeatDays = repeatDays
        self.prayerPack = prayerPack
        self.recitationEnabled = recitationEnabled
        self.sealPackEnabled = sealPackEnabled
        self.sound = sound
    }

    var hour: Int { timeSecondsOfDay / 3600 }
    var minute: Int { (timeSecondsOfDay % 3600) / 60 }

    var formattedTime: String {
        String(format: "%02d:%02d", hour, minute)
    }

    var isOneShot: Bool { repeatDays.isEmpty }

    /// The next moment strictly after `date` at which this alarm fires.
    func nextFire(after date: Date, calendar: Calendar = .current) -> Date? {
        let dayStart = calendar.startOfDay(for: date)
        let offsetSeconds = TimeInterval(timeSecondsOfDay)

        if isOneShot {
            let candidate = dayStart.addingTimeInterval(offsetSeconds)
            if candidate > date { return candidate }
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
            return tomorrow.addingTimeInterval(offsetSeconds)
        }

        // A non-empty weekday set is covered by today plus the next six days.
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: dayStart) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            guard repeatDays.contains(where: { $0.calendarWeekday == weekday }) else { continue }
            let candidate = day.addingTimeInterval(offsetSeconds)
            if candidate > date { return candidate }
        }
        return nil
    }

    /// The short line under the lamp on home: "every Mon, Wed" or "once".
    var repeatSummary: String {
        guard !isOneShot else { return "once" }
        let letters = RepeatDay.displayOrder
            .filter { repeatDays.contains($0) }
            .map(\.short)
        return "every " + letters.joined(separator: ", ")
    }

    /// The whole kept light in one line, for the editor's footer.
    var summaryLine: String {
        "\(formattedTime) · \(repeatSummary) · \(prayerPack.label)" +
            (recitationEnabled ? " · recited" : "") +
            (sealPackEnabled ? " · sealed" : "")
    }
}

/// The on-device store. A JSON document in the app's Documents directory is
/// the whole persistence: local only, no account, no network.
enum LampStore {

    private static var storeURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("miqat-lamps.json")
    }

    static func load() -> [LampAlarm] {
        guard let data = try? Data(contentsOf: storeURL),
              let list = try? JSONDecoder().decode([LampAlarm].self, from: data)
        else { return [] }
        return list
    }

    static func save(_ alarms: [LampAlarm]) {
        guard let data = try? JSONEncoder().encode(alarms) else { return }
        _ = try? data.write(to: storeURL, options: .atomic)
    }

    static func upsert(_ alarm: LampAlarm) {
        var list = load()
        if let index = list.firstIndex(where: { $0.id == alarm.id }) {
            list[index] = alarm
        } else {
            list.append(alarm)
        }
        save(list)
    }

    static func remove(id: UUID) {
        let list = load().filter { $0.id != id }
        save(list)
    }
}
