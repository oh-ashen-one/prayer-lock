import Foundation
import UserNotifications

// MARK: - Notification coordinator
//
// The delegate that owns the two moments an alarm touches the system while the
// app itself may be asleep: (1) presenting a banner when it fires in the
// foreground, and (2) forwarding "enter the chapel" taps — from the banner's
// content or its explicit action — into AppRuntime. No other UI path exists on
// a fired alarm; that is the point.

final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {

    var onEnterChapel: ((UUID) -> Void)?

    static let chapelCategory = "MIQAT_CHAPEL"
    static let enterAction = "MIQAT_ENTER_CHAPEL"

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Re-present in the foreground so a fired alarm is never silently
        // swallowed. Silent-chosen alarms carry .nothing, so nothing rings.
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let alarmID = Self.alarmID(from: response.notification.request.content.userInfo) else { return }
        onEnterChapel?(alarmID)
    }

    static func alarmID(from userInfo: [AnyHashable: Any]) -> UUID? {
        guard let raw = userInfo["alarmID"] as? String else { return nil }
        return UUID(uuidString: raw)
    }
}

// MARK: - Scheduler
//
// The pure core (nextOccurrence / dueAlarms) takes injected dates and a
// Calendar so the tests pin scheduling behavior with no container, no clock,
// and no notification center. The wrappers around it only talk to the system.

enum AlarmScheduler {

    // MARK: Pure core

    /// The next moment strictly after `date` at which this alarm fires, or nil
    /// if the configured time is invalid. Empty repeatDays = one-shot: today if
    /// still ahead, otherwise tomorrow — it does not silently become a repeat.
    static func nextOccurrence(
        after date: Date,
        spec: AlarmSpec,
        calendar: Calendar = .current
    ) -> Date? {
        guard AlarmSpec.isValidTime(spec.timeSecondsOfDay) else { return nil }

        let dayStart = calendar.startOfDay(for: date)
        let offsetSeconds = TimeInterval(spec.timeSecondsOfDay)

        if spec.isOneShot {
            let candidate = dayStart.addingTimeInterval(offsetSeconds)
            if candidate > date { return candidate }
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
            return tomorrow.addingTimeInterval(offsetSeconds)
        }

        // Repeat: today plus the next six days is guaranteed to cover any
        // non-empty weekday set.
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: dayStart) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            guard spec.repeatDays.contains(where: { $0.calendarWeekday == weekday }) else { continue }
            let candidate = day.addingTimeInterval(offsetSeconds)
            if candidate > date { return candidate }
        }
        return nil // unreachable for valid, non-empty specs — kept as the honest floor
    }

    /// Which enabled alarms are owed *right now*: their scheduled moment has
    /// arrived (or passed) today, and they have not been discharged since the
    /// day began. A missed morning therefore becomes a standing question for
    /// the rest of that day — an unpaid alarm asks when you next open Miqat.
    /// This is what lets the foreground watcher engage the chapel directly,
    /// without waiting on a banner.
    static func dueAlarms(
        now: Date,
        alarms: [Alarm],
        calendar: Calendar = .current
    ) -> [UUID] {
        var due: [(Int, UUID)] = []

        for alarm in alarms where alarm.enabled {
            let alreadyPaidToday: Bool
            if let last = alarm.lastFiredAt {
                alreadyPaidToday = calendar.isDate(last, inSameDayAs: now)
            } else {
                alreadyPaidToday = false
            }
            guard !alreadyPaidToday else { continue }

            let candidate = calendar.startOfDay(for: now)
                .addingTimeInterval(TimeInterval(alarm.timeSecondsOfDay))
            guard candidate <= now else { continue }

            if alarm.spec.isOneShot {
                due.append((alarm.timeSecondsOfDay, alarm.id))
            } else if let today = RepeatDay.fromCalendarWeekday(calendar.component(.weekday, from: now)),
                      alarm.repeatDays.contains(today) {
                due.append((alarm.timeSecondsOfDay, alarm.id))
            }
        }

        return due.sorted { $0.0 < $1.0 }.map(\.1)
    }

    // MARK: Human wording (home screen, "next light")

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEE")
        return f
    }()

    static func humanDescription(
        of fireDate: Date?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        guard let fireDate else { return "—" }
        let time = timeFormatter.string(from: fireDate)
        let dayDelta = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: fireDate)
        ).day ?? 0

        switch dayDelta {
        case ..<0: return "—"          // never in the future; treat as resting
        case 0: return "today at \(time)"
        case 1: return "tomorrow at \(time)"
        default: return "\(weekdayFormatter.string(from: fireDate)) at \(time)"
        }
    }

    // MARK: System wrappers

    /// Register the chapel's category once. The single action — "Enter the
    /// chapel" — is the only door on a fired alarm's banner, and it deep-links
    /// into the lock exactly like tapping the content.
    static func registerChapelCategory() {
        let enter = UNNotificationAction(
            identifier: NotificationCoordinator.enterAction,
            title: "Enter the chapel",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: NotificationCoordinator.chapelCategory,
            actions: [enter],
            intentIdentifiers: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// Arm (or re-arm) the alarm's next fire. Pending requests are replaced,
    /// never stacked — every toggle or edit re-arms from "now".
    static func schedule(_ alarm: Alarm) {
        guard alarm.enabled else {
            unschedule(alarm)
            return
        }
        let now = Date()
        guard let fireDate = nextOccurrence(after: now, spec: alarm.spec) else { return }

        let content = UNMutableNotificationContent()
        content.title = alarm.label.isEmpty ? "The lamp is lit" : alarm.label
        content.body = "The rite is due: \(alarm.packsLabel). Enter, or it waits."
        content.sound = sound(for: alarm.sound)
        content.categoryIdentifier = NotificationCoordinator.chapelCategory
        content.userInfo = ["alarmID": alarm.id.uuidString]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, fireDate.timeIntervalSince(now)),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: alarm.id.uuidString,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    static func unschedule(_ alarm: Alarm) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [alarm.id.uuidString])
    }

    static func pendingAlarmIDs() -> Set<UUID> {
        // Synchronous snapshot for the home screen (badge: "armed").
        // UNUserNotificationCenter only offers async pending requests, so the
        // truth of "armed" lives in Alarm.enabled; this helper exists for a
        // future reconcile pass and deliberately returns the empty set when we
        // cannot answer without a callback. Kept honest by being unused quietly.
        []
    }

    private static func sound(for choice: SoundChoice) -> UNNotificationSound? {
        switch choice {
        case .bell:
            return .default
        case .chime:
            if Bundle.main.url(forResource: "chapel_chime", withExtension: "caf") != nil {
                return UNNotificationSound(named: UNNotificationSoundName("chapel_chime.caf"))
            }
            return .default   // the documented fallback; see README on dropping a caf in
        case .stillness:
            return .nothing   // light only; the rite itself is what wakes you
        }
    }
}
