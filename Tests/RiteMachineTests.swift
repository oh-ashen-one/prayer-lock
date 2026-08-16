import XCTest
@testable import Miqat

/// The rakaʿat state machine, pinned: postures advance only in ritual order,
/// a rakaʿat closes on its sit (and only then), the completed rite is observed
/// exactly once, and nothing advances before begin. Interruption is modeled by
/// discarding the machine — an interrupted rite is a rite not done.

final class RiteMachineTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 1_700_000_000)

    private func machine(_ rakaats: Int, at now: Date = t0) -> RiteStateMachine {
        var m = RiteStateMachine(rakaats: rakaats)
        m.begin(at: now)
        return m
    }

    func testNothingAdvancesBeforeBegin() {
        var m = RiteStateMachine(rakaats: 4)
        XCTAssertNil(m.advance(at: t0))
        XCTAssertFalse(m.isComplete)
        XCTAssertEqual(m.expectedPosture, .standing)   // what it will demand once begun
    }

    func testOneRakaatCompletesInExactOrder() {
        var m = machine(1)

        let stand = m.advance(at: t0)!
        XCTAssertEqual(stand.completedPosture, .standing)
        XCTAssertNil(stand.completedRakaat)            // only a sit closes a rakaʿat
        XCTAssertEqual(stand.nextExpected, .bowing)

        let bow = m.advance(at: t0)!
        XCTAssertEqual(bow.completedPosture, .bowing)
        XCTAssertNil(bow.completedRakaat)
        XCTAssertEqual(bow.nextExpected, .prostrating)

        let prostrate = m.advance(at: t0)!
        XCTAssertEqual(prostrate.completedPosture, .prostrating)
        XCTAssertNil(prostate.completedRakaat)
        XCTAssertEqual(prostrate.nextExpected, .sitting)

        let sit = m.advance(at: t0)!
        XCTAssertEqual(sit.completedPosture, .sitting)
        XCTAssertEqual(sit.completedRakaat, 1)          // the sit closes its rakaʿat
        XCTAssertTrue(sit.riteComplete)
        XCTAssertNil(sit.nextExpected)

        XCTAssertTrue(m.isComplete)
        XCTAssertEqual(m.currentRakaat, 1)              // clamped to the plan at rest
    }

    func testCompletedRiteCannotBeOverAdvanced() {
        var m = machine(1)
        _ = m.advance(at: t0)!   // stand
        _ = m.advance(at: t0)!   // bow
        _ = m.advance(at: t0)!   // prostrate
        _ = m.advance(at: t0)!   // sit — complete

        XCTAssertNil(m.advance(at: t0))
        XCTAssertTrue(m.isComplete)   // still complete, not corrupted by the attempt
    }

    func testTwoRakaatsRestartOnStanding() {
        var m = machine(2)
        XCTAssertEqual(m.totalSteps, 8)
        XCTAssertEqual(m.currentRakaat, 1)

        _ = m.advance(at: t0)!   // stand
        _ = m.advance(at: t0)!   // bow

        XCTAssertEqual(m.completedPiers(inRakaat: 1), [.standing, .bowing])
        XCTAssertEqual(m.completedPiers(inRakaat: 2), [])

        _ = m.advance(at: t0)!
        let sitOne = m.advance(at: t0)!

        XCTAssertEqual(sitOne.completedRakaat, 1)
        XCTAssertFalse(sitOne.riteComplete)            // a rakaʿat closed, not the rite

        XCTAssertEqual(m.currentRakaat, 2)
        XCTAssertEqual(m.expectedPosture, .standing)   // rakaʿat two begins standing

        XCTAssertEqual(
            m.completedPiers(inRakaat: 1),
            [.standing, .bowing, .prostrating, .sitting]
        )

        let standTwo = m.advance(at: t0)!
        XCTAssertNil(standTwo.completedRakaat)
        XCTAssertEqual(m.completedPiers(inRakaat: 2), [.standing])

        _ = m.advance(at: t0)!   // bow
        _ = m.advance(at: t0)!   // prostrate
        let sitTwo = m.advance(at: t0)!

        XCTAssertEqual(sitTwo.completedRakaat, 2)
        XCTAssertTrue(sitTwo.riteComplete)
        XCTAssertNil(sitTwo.nextExpected)
    }

    func testStandardHoldsMatchTheDocumentedPlan() {
        let plan = RitePlan.standard(rakaats: 4)

        XCTAssertEqual(plan.holds[.standing], 6.0)
        XCTAssertEqual(plan.holds[.bowing], 5.0)
        XCTAssertEqual(plan.holds[.prostrating], 6.0)
        XCTAssertEqual(plan.holds[.sitting], 4.0)

        var m = RiteStateMachine(plan: plan)
        m.begin(at: t0)

        XCTAssertEqual(m.requiredHold, 6.0)    // standing
        _ = m.advance(at: t0)!
        XCTAssertEqual(m.requiredHold, 5.0)    // bowing
        _ = m.advance(at: t0)!
        XCTAssertEqual(m.requiredHold, 6.0)    // prostrating
        _ = m.advance(at: t0)!
        XCTAssertEqual(m.requiredHold, 4.0)    // sitting
    }

    func testSequenceIsTheRitualOrder() {
        XCTAssertEqual(
            RitePlan.sequence,
            [.standing, .bowing, .prostrating, .sitting]
        )
    }

    func testRakaatCountIsClampedToThePlan() {
        XCTAssertEqual(RitePlan.standard(rakaats: 9).rakaats, 4)
        XCTAssertEqual(RitePlan.standard(rakaats: -3).rakaats, 1)
        XCTAssertEqual(RiteStateMachine(rakaats: 9).totalSteps, 16)
        XCTAssertEqual(RiteStateMachine(rakaats: -3).totalSteps, 4)
    }
}
