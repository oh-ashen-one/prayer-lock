import SwiftUI
import SwiftData
import CryptoKit
import UserNotifications

/// A rite in progress. Written the moment the chapel locks, cleared only when
/// the rite finishes or the emergency exit is used. This is what makes a
/// call-or-kill mid-prayer honest: on next launch the chapel re-opens for that
/// alarm and the prayer starts over. A rite interrupted is a rite not done.
struct RiteToken: Codable {
    var alarmID: UUID
    var startedAt: Date
}

@MainActor
@Observable
final class AppRuntime {

    private enum Keys {
        static let onboarded = "miqat.onboarded.v1"
        static let riteToken = "miqat.rite.token.v1"
        static let emergencyPhraseSHA256 = "miqat.emergency.sha256.v1"
    }

    // MARK: State

    var onboardingComplete: Bool {
        didSet { UserDefaults.standard.set(onboardingComplete, forKey: Keys.onboarded) }
    }

    /// Non-nil while the chapel holds the screen. RootView presents it as a
    /// full-screen cover with no dismiss gesture.
    var lockedAlarmID: UUID?

    /// Notification plumbing (delegate + category registration) lives with the
    /// scheduler in Alarm/AlarmScheduler.swift; the runtime just owns it and
    /// forwards its "enter chapel" callback.
    let notifications = NotificationCoordinator()

    private var booted = false

    init() {
        onboardingComplete = UserDefaults.standard.bool(forKey: Keys.onboarded)
    }

    // MARK: Boot (idempotent; called once from RootView.onAppear)

    func boot() {
        guard !booted else { return }
        booted = true

        notifications.onEnterChapel = { [weak self] alarmID in
            Task { @MainActor in
                self?.lock(alarmID: alarmID)
            }
        }

        AlarmScheduler.registerChapelCategory()

        let center = UNUserNotificationCenter.current()
        center.delegate = notifications
    }

    // MARK: Deep link — miqat://chapel/<alarm-uuid>

    func route(url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "miqat" else { return }

        // The id may arrive as the last path component or, in edge cases, as
        // part of the host. Take whatever parses last.
        let components = url.absoluteString
            .components(separatedBy: "/")
            .filter { !$0.isEmpty && !($0.hasPrefix("miqat:") || $0 == "miqat://") }
        if let candidate = components.last, let alarmID = UUID(uuidString: candidate) {
            lock(alarmID: alarmID)
        }
    }

    // MARK: Lock / rite lifecycle

    func lock(alarmID: UUID) {
        let token = RiteToken(alarmID: alarmID, startedAt: Date())
        if let data = try? JSONEncoder().encode(token) {
            UserDefaults.standard.set(data, forKey: Keys.riteToken)
        }
        lockedAlarmID = alarmID
    }

    /// If the app was killed or a call cut in mid-rite, bring the chapel back.
    /// The rite restarts from its first step — it is not resumed, and it does
    /// not count.
    func restoreInterruptedRite(in context: ModelContext) {
        guard onboardingComplete, lockedAlarmID == nil else { return }
        guard let token = currentRiteToken() else { return }

        var descriptor = FetchDescriptor<Alarm>(predicate: #Predicate { $0.id == token.alarmID })
        let count = (try? context.fetchCount(descriptor)) ?? 0
        guard count > 0 else {
            clearRiteToken()   // alarm was deleted; the debt is discharged
            return
        }

        // Refresh the token so "startedAt" reflects this attempt.
        let fresh = RiteToken(alarmID: token.alarmID, startedAt: Date())
        if let data = try? JSONEncoder().encode(fresh) {
            UserDefaults.standard.set(data, forKey: Keys.riteToken)
        }
        lockedAlarmID = token.alarmID
    }

    /// Called when the rite is complete. Marks the alarm fired, discharges the
    /// token, and releases the screen.
    func finishRite(alarm: Alarm?, in context: ModelContext) {
        if let alarm {
            alarm.lastFiredAt = Date()
            try? context.save()
        }
        clearRiteToken()
        lockedAlarmID = nil
    }

    /// Called after the emergency exit verifies. The rite is not done — it was
    /// released — so we log the opening and discharge without marking fired.
    func recordEmergencyExit(alarmID: UUID?, in context: ModelContext) {
        let entry = EmergencyUse(alarmID: alarmID, at: Date())
        context.insert(entry)
        try? context.save()
        clearRiteToken()
        lockedAlarmID = nil
    }

    private func currentRiteToken() -> RiteToken? {
        guard let data = UserDefaults.standard.data(forKey: Keys.riteToken) else { return nil }
        return try? JSONDecoder().decode(RiteToken.self, from: data)
    }

    private func clearRiteToken() {
        UserDefaults.standard.removeObject(forKey: Keys.riteToken)
    }

    // MARK: Emergency phrase — install-time, stored only as a SHA-256 digest.
    // The plaintext never touches disk; it is typed into memory, compared in
    // constant time, and dropped.

    func storeEmergencyPhrase(_ phrase: String) {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UserDefaults.standard.set(Self.sha256(trimmed), forKey: Keys.emergencyPhraseSHA256)
    }

    var hasEmergencyPhrase: Bool {
        UserDefaults.standard.data(forKey: Keys.emergencyPhraseSHA256) != nil
    }

    func verifyEmergencyPhrase(_ phrase: String) -> Bool {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let stored = UserDefaults.standard.data(forKey: Keys.emergencyPhraseSHA256)
        else { return false }

        let digest = Self.sha256(trimmed)
        guard stored.count == digest.count else { return false }

        var difference: UInt8 = 0
        for index in stored.indices {
            difference |= stored[index] ^ digest[index]
        }
        return difference == 0
    }

    private static func sha256(_ string: String) -> Data {
        let hash = Insecure.SHA256.hash(data: Data(string.utf8))
        return Data(hash)
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
