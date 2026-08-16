import CoreMotion
import Foundation
import Observation

// MARK: - Posture engine (Core Motion, honest hybrid)
/// Reads device motion and answers one question per posture: "does what the
/// sensor sees right now agree with this expected posture?"
///
/// Raw gravity cannot tell "phone in hand" from "phone on the floor" — both
/// are near-flat against g. The honest hybrid is therefore:
///   1) sequence — the machine only ever accepts its expected posture, so no
///      single sample can fake a step out of order; and
///   2) one explicit affordance — the tap that says "the phone is set on the
///      floor", which prostration (and only prostration) requires, together
///      with stillness.
///
/// Thresholds live here as constants on purpose: one place to tune, and the
/// README documents them.

@MainActor
@Observable
final class PostureEngine {

    // MARK: Thresholds (gravity normalized to 1 g)

    /// Near-vertical (in hand, or flat on a surface — the tap disambiguates).
    static let standingGzMin = 0.80
    /// Tilted forward, roughly 25°–80° off vertical.
    static let bowingGzRange: ClosedRange<Double> = 0.17...0.91
    /// Flat — required for prostration alongside placement and stillness.
    static let prostratingGzMin = 0.85
    /// Picked up off the floor and tilted back, roughly 10°–63° from flat.
    static let sittingGzRange: ClosedRange<Double> = 0.45...0.98

    /// Mean squared high-pass acceleration below which we call the phone at rest
    /// (≈ 0.35 g RMS). A hand's micro-motion is well under this; walking is not.
    static let stillnessMeanSquaredMax = 0.12
    /// Stillness window, in samples (~1.2 s at 20 Hz).
    static let atRestWindowSize = 24

    /// How long the phone must stay off-flat before "placed" is cleared
    /// (i.e., it has been picked up for the sit).
    static let placedClearSeconds: TimeInterval = 1.2

    private static let standardGravity = 9.806_65
    private static let sampleInterval: TimeInterval = 1.0 / 20.0

    // MARK: Observable state (read by the step UI)

    private(set) var atRest = false
    /// True from "phone set on the floor" tap until sustained pick-up. Guards
    /// prostration in and standing/sitting out, so a set phone can never pass
    /// for "standing".
    private(set) var phonePlaced = false

    // MARK: Private sensor state

    private let manager = CMMotionManager()
    private var gz: Double = 1.0                 // |gravity.z| / g
    private var belowFlatFor: TimeInterval = 0   // placement-lifecycle bookkeeping
    private var lastSampleDate: Date?
    private var accelWindow: [Double] = []       // |userAcceleration|² samples

    // MARK: Lifecycle

    var isRunning: Bool { manager.isDeviceMotionActive }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        accelWindow.removeAll()
        atRest = false

        manager.deviceMotionUpdateInterval = Self.sampleInterval
        manager.startDeviceMotionUpdates(to: OperationQueue()) { [weak self] motion, _ in
            guard let motion else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.ingest(motion)
            }
        }
    }

    func stop() {
        if manager.isDeviceMotionActive {
            manager.stopDeviceMotionUpdates()
        }
    }

    // MARK: Placement (the hybrid's one explicit affordance)

    func markPhoneOnFloor() {
        phonePlaced = true
        belowFlatFor = 0
    }

    // MARK: Ingest (main actor)

    private func ingest(_ motion: CMDeviceMotion) {
        let now = Date()
        let dt: TimeInterval = lastSampleDate.map { now.timeIntervalSince($0) } ?? Self.sampleInterval
        lastSampleDate = now

        gz = min(1, abs(motion.gravity.z) / Self.standardGravity)

        // Placement lifecycle: once "placed", a sustained time off-flat means
        // the phone has been picked up (the sit is happening) — clear the flag
        // so standing/bowing/sitting cannot be confused with prostration.
        if phonePlaced {
            if gz < (Self.standingGzMin - 0.05) {
                belowFlatFor += dt
            } else {
                belowFlatFor = 0
            }
            if belowFlatFor >= Self.placedClearSeconds {
                phonePlaced = false
                belowFlatFor = 0
            }
        }

        // Stillness over high-pass acceleration (gravity already removed).
        let a = motion.userAcceleration
        accelWindow.append(a.x * a.x + a.y * a.y + a.z * a.z)
        if accelWindow.count > Self.atRestWindowSize {
            accelWindow.removeFirst(accelWindow.count - Self.atRestWindowSize)
        }
        if accelWindow.count >= 12 {
            let meanSquared = accelWindow.reduce(0, +) / Double(accelWindow.count)
            atRest = meanSquared <= Self.stillnessMeanSquaredMax
        }
    }

    // MARK: The gated question

    /// "Does the sensor agree with this expected posture?" — see the file
    /// header for why expectation, not classification, is the input.
    func matches(_ expected: Posture) -> Bool {
#if DEBUG && targetEnvironment(simulator)
        // The simulator has no motion sensor: give it a calm world in which
        // every posture holds, so the rite's UI (ring, architecture, timing)
        // is exercisable there. On a device this branch does not exist — the
        // three-finger tap is the only shortcut, and it is simulator-only too.
        return true
#else
        switch expected {
        case .standing:
            // Near-vertical and not set down. (A phone left on a table would
            // also match — the sequence and the holds are what keep it honest.)
            return !phonePlaced && gz >= Self.standingGzMin

        case .bowing:
            return !phonePlaced && Self.bowingGzRange.contains(gz)

        case .prostrating:
            // The tap, plus flatness, plus stillness. This is the floor check
            // that a live held phone cannot fake.
            return phonePlaced && gz >= Self.prostratingGzMin && atRest

        case .sitting:
            // Picked up off the floor (placement cleared) and tilted back.
            return !phonePlaced && Self.sittingGzRange.contains(gz)
        }
#endif
    }
}
