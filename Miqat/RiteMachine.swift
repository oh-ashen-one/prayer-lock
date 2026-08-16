import Foundation

/// One posture of a single rakaat, in the order the rite walks them.
enum RiteStep: Int, CaseIterable, Codable, Equatable {
    case stand = 0
    case bow = 1
    case prostrate = 2
    case sit = 3

    /// The word the rite holds on, in small tracked caps.
    var label: String {
        switch self {
        case .stand: return "Stand"
        case .bow: return "Bow"
        case .prostrate: return "Prostrate"
        case .sit: return "Sit"
        }
    }

    /// How long the held posture keeps its breath ring before it settles.
    var holdSeconds: Double {
        switch self {
        case .stand: return 6.0
        case .bow: return 4.0
        case .prostrate: return 5.0
        case .sit: return 7.0
        }
    }

    /// The breathing pace of the hold, in seconds per full ring.
    var breathPeriod: Double {
        switch self {
        case .stand, .sit: return 4.5
        default: return 3.6
        }
    }

    /// The one-line instruction beneath the word, kept plain.
    var line: String {
        switch self {
        case .stand: return "rise to the qiyam"
        case .bow: return "lower into the ruku"
        case .prostrate: return "go down to the sujud"
        case .sit: return "rest in the jalsa"
        }
    }

    /// The lamp glyph for the step, drawn small in brass.
    var symbol: String {
        switch self {
        case .stand: return "figure.stand"
        case .bow: return "arrow.turn.down.right"
        case .prostrate: return "chevron.compact.down"
        case .sit: return "figure.seated.side"
        }
    }
}

/// The rakaat state machine. It walks stand, bow, prostrate, sit once per
/// rakaat of the pack and knows exactly when the whole rite is done. Pure
/// value type, no UI: the lock chapel renders it and advances it.
struct RiteMachine: Equatable {
    private(set) var rakaatCount: Int = 2
    private(set) var rakaatIndex: Int = 0   // 1-based, from the first step
    private(set) var stepIndex: Int = 0     // index into RiteStep.allCases

    init(rakaatCount: Int) {
        self.rakaatCount = min(max(1, rakaatCount), 4)
    }

    var currentStep: RiteStep { RiteStep(rawValue: stepIndex) ?? .stand }
    var isComplete: Bool { rakaatIndex > rakaatCount }

    /// Total postures in the whole rite, for progress hairlines.
    var totalSteps: Int { rakaatCount * RiteStep.allCases.count }

    /// Postures kept so far, counting the current one as begun.
    var completedSteps: Int { isComplete ? totalSteps : rakaatIndex * RiteStep.allCases.count - 1 + stepIndex }

    /// "Rakaat two of three" for the running line.
    var rakaatLine: String { "rakaat \(roman(rakaatIndex)) of \(roman(rakaatCount))" }

    /// Advance one posture. Returns the machine after moving; when the last
    /// sit closes, `isComplete` is true and every step of every rakaat is kept.
    mutating func advance() -> RiteMachine {
        guard !isComplete else { return self }
        stepIndex += 1
        if stepIndex >= RiteStep.allCases.count {
            stepIndex = 0
            rakaatIndex += 1
        }
        return self
    }

    private func roman(_ n: Int) -> String {
        switch n {
        case 1: return "one"
        case 2: return "two"
        case 3: return "three"
        default: return "four"
        }
    }
}
