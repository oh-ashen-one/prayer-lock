import Foundation
import UIKit
import Vision

// MARK: - Verdict (pure)
/// What the Seal asks. `distance` is nil when nothing could be compared
/// (corrupt stored thumbnail, Vision failure) — and the Seal fails closed: a
/// seal that cannot be checked is not passed.

struct SealVerdict: Equatable {
    let distance: Double?
    let threshold: Double

    var isMatch: Bool { SealMatchEngine.isAcceptable(distance, threshold: threshold) }
    /// Distance as a human line for the UI ("0.19 — known" / "0.42 — unknown").
    var human: String {
        guard let d = distance else { return "the lamp cannot see" }
        return String(format: "%.2f", d) + (isMatch ? " — known" : " — unknown")
    }
}

// MARK: - Engine (Vision feature prints, on-device)
/// Household objects are photographed at setup; their thumbnails are kept as
/// JPEG. At match time, Vision computes a feature print (the "embedding") for
/// the stored thumbnail and for the live photo, in-process — nothing is ever
/// persisted beyond your photos. Distance semantics from calibration: the same
/// object under ordinary light lands around 0.1–0.3; a different object or the
/// bare floor typically reads past 0.4. Hence the default threshold: accept
/// strictly below it.

enum SealMatchEngine {

    static let defaultThreshold = 0.28
    /// The strictest useful value (near-exact only) and the loosest (accepting
    /// different angles/lights generously). The Vestry slider moves between.
    static let thresholdRange: ClosedRange<Double> = 0.15...0.45

    /// The pure rule, pinned by tests: accept a finite distance strictly below
    /// threshold; reject everything else, including "no distance".
    static func isAcceptable(_ distance: Double?, threshold: Double) -> Bool {
        guard let d = distance, d.isFinite else { return false }
        return d >= 0 && d < threshold
    }

    enum SealMatchingError: Error { case noObservation }

    /// Compare a stored object thumbnail against a live capture.
    static func match(
        storedJPEG: Data,
        liveImage: CGImage,
        liveOrientation: CGImagePropertyOrientation = .up,
        threshold: Double = defaultThreshold
    ) -> SealVerdict {
        do {
            let storedObservation = try observation(fromJPEG: storedJPEG)
            let liveObservation = try observation(of: liveImage, orientation: liveOrientation)
            // Same-object reads ≈ 0.1–0.3; floor/other-object typically > 0.4.
            let distance = Double(storedObservation.distance(from: liveObservation))
            return SealVerdict(distance: distance, threshold: threshold)
        } catch {
            // Fail closed. The UI says the same thing either way; this just
            // keeps "cannot verify" and "does not match" from being the door.
            return SealVerdict(distance: nil, threshold: threshold)
        }
    }

    // MARK: Internals

    private static func observation(fromJPEG data: Data) throws -> VNFeaturePrintObservation {
        guard let image = UIImage(data: data)?.cgImage else { throw SealMatchingError.noObservation }
        return try observation(of: image, orientation: .up)
    }

    private static func observation(
        of image: CGImage,
        orientation: CGImagePropertyOrientation
    ) throws -> VNFeaturePrintObservation {
        let request = VNFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation)
        try handler.perform([request])
        guard let observation = request.results?.first else { throw SealMatchingError.noObservation }
        return observation
    }
}
