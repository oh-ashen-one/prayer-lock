import SwiftUI

/// The breath ring: a slow brass circle that swells and settles for the whole
/// hold of the current posture. It is the only moving ornament in the lock
/// chapel, and it keeps time with the step's breath period.
struct BreathRingView: View {
    let period: Double
    var tint: Color = ChapelTheme.brass

    @State private var phase = 0.0

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            // One full breath per period: 0 at the exhale, 1 at the swell.
            let cycle = (t.truncatingRemainder(dividingBy: period)) / period
            let swell = (1 - cos(cycle * 2 * .pi)) / 2
            ring(swell: swell)
        }
    }

    private func ring(swell: Double) -> some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.16), lineWidth: 1)

            Circle()
                .stroke(tint.opacity(0.35 + 0.45 * swell), lineWidth: 2)
                .frame(width: 168 + 34 * swell, height: 168 + 34 * swell)

            Circle()
                .stroke(tint.opacity(0.2 + 0.3 * swell), lineWidth: 1)
                .frame(width: 208 + 30 * swell, height: 208 + 30 * swell)

            // The wick at the hub: a small ember that brightens with the breath.
            Ellipse()
                .fill(ChapelTheme.flame.opacity(0.5 + 0.4 * swell))
                .frame(width: 9, height: 13)

            Ellipse()
                .fill(ChapelTheme.flameCore.opacity(0.6 + 0.4 * swell))
                .frame(width: 3, height: 5)
        }
    }
}

#Preview {
    ZStack {
        ChapelTheme.Background()
        BreathRingView(period: 4.0)
    }
}
