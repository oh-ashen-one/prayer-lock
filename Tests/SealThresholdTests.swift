import XCTest
@testable import Miqat

/// The seal's pass rule, pinned: accept a finite distance strictly below the
/// threshold; reject everything else. Plus the calibration story that makes
/// "a floor photo must fail" true: same-object reads ~0.1–0.3, a different
/// object or bare floor typically reads > 0.4 — and missing or corrupt
/// evidence always fails closed (no verdict is a no-pass, never a pass).

final class SealThresholdTests: XCTestCase {

    private let t = SealMatchEngine.defaultThreshold   // 0.28, documented in the README

    func testDefaultThresholdSitsInTheUsableRange() {
        XCTAssertTrue(SealMatchEngine.thresholdRange.contains(t))
    }

    func testSameObjectBandPasses() {
        XCTAssertTrue(SealMatchEngine.isAcceptable(0.1, threshold: t))
        XCTAssertTrue(SealMatchEngine.isAcceptable(0.19, threshold: t))
        XCTAssertTrue(SealMatchEngine.isAcceptable(0.27, threshold: t))
    }

    func testBoundaryIsStrict() {
        // Exactly at the threshold is not below it: no pass.
        XCTAssertFalse(SealMatchEngine.isAcceptable(t, threshold: t))
        XCTAssertFalse(SealMatchEngine.isAcceptable(0.15, threshold: 0.15))
    }

    func testOtherObjectOrFloorBandFails() {
        XCTAssertFalse(SealMatchEngine.isAcceptable(0.29, threshold: t))
        XCTAssertFalse(SealMatchEngine.isAcceptable(0.42, threshold: t))
        XCTAssertFalse(SealMatchEngine.isAcceptable(0.45, threshold: t))
        XCTAssertFalse(SealMatchEngine.isAcceptable(1.5, threshold: t))
    }

    func testStrictlyBelowIsTheRuleForEveryThreshold() {
        let distance = 0.2
        for threshold in [0.15, 0.22, 0.30, 0.45] {
            let passes = SealMatchEngine.isAcceptable(distance, threshold: threshold)
            XCTAssertEqual(passes, threshold > distance, "d=\(distance), t=\(threshold)")
        }
    }

    func testMissingEvidenceFailsClosed() {
        XCTAssertFalse(SealMatchEngine.isAcceptable(nil, threshold: t))
        XCTAssertFalse(SealMatchEngine.isAcceptable(nil, threshold: 10.0))   // even a permissive gate
        XCTAssertFalse(SealMatchEngine.isAcceptable(nil, threshold: 0.1))
    }

    func testNonFiniteAndNegativeDistancesFail() {
        XCTAssertFalse(SealMatchEngine.isAcceptable(.nan, threshold: t))
        XCTAssertFalse(SealMatchEngine.isAcceptable(.infinity, threshold: t))
        XCTAssertFalse(SealMatchEngine.isAcceptable(-.infinity, threshold: t))
        XCTAssertFalse(SealMatchEngine.isAcceptable(-0.1, threshold: t))
    }

    func testVerdictSurfaces() {
        let known = SealVerdict(distance: 0.19, threshold: t)
        XCTAssertTrue(known.isMatch)
        XCTAssertTrue(known.human.hasPrefix("0.19"))
        XCTAssertTrue(known.human.contains("known"))

        let unknown = SealVerdict(distance: 0.42, threshold: t)
        XCTAssertFalse(unknown.isMatch)
        XCTAssertTrue(unknown.human.hasPrefix("0.42"))
        XCTAssertTrue(unknown.human.contains("unknown"))

        let blind = SealVerdict(distance: nil, threshold: t)
        XCTAssertFalse(blind.isMatch)
        XCTAssertEqual(blind.human, "the lamp cannot see")
    }

    func testCalibrationStoryIsPinned() {
        // The whole product promise, in two assertions at the default threshold:
        // the object passes; the floor does not.
        XCTAssertTrue(SealMatchEngine.isAcceptable(0.2, threshold: t))
        XCTAssertFalse(SealMatchEngine.isAcceptable(0.45, threshold: t))
    }
}
