import Foundation

// MARK: - Postures
// The four postures of the rakaʿāt, in ritual order.

enum Posture: Int, CaseIterable, Codable {
    case standing = 0
    case bowing
    case prostrating
    case sitting

    /// The big word on the step screen.
    var word: String {
        switch self {
        case .standing: "Stand"
        case .bowing: "Bow"
        case .prostrating: "Prostrate"
        case .sitting: "Sit"
        }
    }

    /// The small line under the word — what the body and the phone do now.
    var line: String {
        switch self {
        case .standing: "rise, phone in hand"
        case .bowing: "lean forward until the phone tilts with you"
        case .prostrating: "place the phone on the floor, then tap when it is set"
        case .sitting: "sit back up and tilt the phone toward you"
        }
    }
}

// MARK: - Plan
/// The shape of a rite: how many rakaʿāt, and the hold time at each posture.

struct RitePlan: Equatable {
    let rakaats: Int
    var holds: [Posture: Double]

    /// The canonical choreography — the same holds the README documents.
    /// stand 6s · bow 5s · prostrate 6s · sit 4s.
    static func standard(rakaats: Int) -> RitePlan {
        let n = min(max(rakaats, 1), 4)
        return RitePlan(
            rakaats: n,
            holds: [
                .standing: 6.0,
                .bowing: 5.0,
                .prostrating: 6.0,
                .sitting: 4.0
            ]
        )
    }

    /// One rakaʿāt, in order. The machine walks this four times (once per
    /// rakaʿat) — the "rakaʿat as architecture" the UI draws from.
    static let sequence: [Posture] = [.standing, .bowing, .prostrating, .sitting]
}

// MARK: - Machine
/// Pure state machine. No motion, no views — the parts its tests pin are:
/// a rakaʿat completes only when stand, bow, prostrate and sit each advance
/// in order; a completed rite cannot be over-advanced; nothing advances before
/// begin. Intentional interruption (a kill, a call) destroys the machine and
/// rebuilds it from zero — a rite interrupted is a rite not done.

struct RiteStateMachine {
    let plan: RitePlan

    /// Index of the posture currently being held. == totalSteps ⇒ complete.
    private(set) var stepIndex = 0
    /// The rite has started (the conductor called begin).
    private(set) var hasBegun = false

    init(plan: RitePlan) {
        self.plan = plan
    }

    init(rakaats: Int) {
        self.init(plan: .standard(rakaats: rakaats))
    }

    var totalSteps: Int { plan.rakaats * RitePlan.sequence.count }
    var isComplete: Bool { hasBegun && stepIndex >= totalSteps }

    /// The posture the rite currently demands. (Read-only when complete.)
    var expectedPosture: Posture {
        guard !isComplete else { return .sitting }
        return RitePlan.sequence[stepIndex % RitePlan.sequence.count]
    }

    /// Which rakaʿat is in progress (1-based), clamped to the plan.
    var currentRakaat: Int { min(stepIndex / 4 + 1, plan.rakaats) }

    /// How long the current posture must be held before it counts.
    var requiredHold: Double { plan.holds[expectedPosture] ?? 4.0 }

    mutating func begin(at now: Date) {
        hasBegun = true
    }

    struct AdvanceResult: Equatable {
        let completedPosture: Posture
        /// nil when the rite is complete.
        let nextExpected: Posture?
        /// Set only when a sit has just closed its rakaʿat.
        let completedRakaat: Int?
        let riteComplete: Bool
    }

    /// Accept the completion of the currently-held posture. Returns nil when
    /// not begun or already complete — a rite cannot be advanced by force.
    mutating func advance(at now: Date) -> AdvanceResult? {
        guard hasBegun, stepIndex < totalSteps else { return nil }

        let completed = expectedPosture   // read before the increment
        stepIndex += 1

        let riteComplete = stepIndex >= totalSteps
        // A sit at index k (k % 4 == 3) closes rakaʿat floor(k/4) + 1;
        // after incrementing, that is exactly stepIndex / 4.
        let rakaatClosed: Int? = (completed == .sitting) ? min(stepIndex / 4, plan.rakaats) : nil

        return AdvanceResult(
            completedPosture: completed,
            nextExpected: riteComplete ? nil : RitePlan.sequence[stepIndex % RitePlan.sequence.count],
            completedRakaat: rakaatClosed,
            riteComplete: riteComplete
        )
    }

    /// The postures already completed within rakaʿat `r` (1-based).
    /// Drives the architecture: one column per rakaʿat, a lit pier per posture.
    func completedPiers(inRakaat r: Int) -> [Posture] {
        guard (1...plan.rakaats).contains(r) else { return [] }
        let base = (r - 1) * RitePlan.sequence.count
        return RitePlan.sequence.enumerated().compactMap { offset, posture in
            (base + offset) < stepIndex ? posture : nil
        }
    }
}

// MARK: - Debug simulator assist (compiled out of device builds)
/// Three-finger tap in a DEBUG *simulator* build force-completes the current
/// posture: it is treated as if the hold had just finished.

extension RiteStateMachine {
    /// Advance regardless of sensor state; used only behind the DEBUG-simulator
    /// gate in the prayer UI. Returns nil when there is nothing to advance.
    mutating func debugAdvance(at now: Date) -> AdvanceResult? {
        advance(at: now)
    }
}
