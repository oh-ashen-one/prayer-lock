import SwiftUI

/// The lamp clock. Brass ring, serif hour figures on a dark well, hands that
/// sweep rather than tick, and a halo behind the glass that breathes like
/// candlelight. Drawn entirely in Canvas — no images, no assets.
struct LampClockView: View {
    var date: Date = .now
    var palette: ChapelPalette = .chapelNight
    /// 0...1 ambient pulse, driven by the live wrapper (the "flicker").
    var haloPulse: Double = 0.85
    /// Optional brass pip on the ring marking the next alarm (minutes of day).
    var alarmMinutes: Double? = nil

    private static let romanNumerals = [
        "XII", "I", "II", "III", "IV", "V",
        "VI", "VII", "VIII", "IX", "X", "XI"
    ]

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
            let radius = min(size.width, size.height) / 2.0
            guard radius > 8 else { return }

            drawHalo(in: &context, center: center, radius: radius)
            drawWell(in: &context, center: center, radius: radius)
            drawRings(in: &context, center: center, radius: radius)
            drawTicks(in: &context, center: center, radius: radius)
            if let minutes = alarmMinutes {
                drawAlarmPip(in: &context, center: center, radius: radius, atMinutes: minutes)
            }
            drawNumerals(in: &context, center: center, radius: radius)
            drawHands(in: &context, center: center, radius: radius)
        }
    }

    // MARK: - Layers

    private func drawHalo(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        let rect = CGRect(
            x: center.x - radius * 1.18, y: center.y - radius * 1.18,
            width: radius * 2.36, height: radius * 2.36
        )
        let strength = 0.10 + 0.28 * haloPulse
        context.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(
                Gradient(colors: [
                    palette.brass.opacity(strength),
                    palette.flame.opacity(strength * 0.35),
                    .clear
                ]),
                center: CGPoint(x: center.x, y: center.y - radius * 0.25),
                startRadius: radius * 0.1,
                endRadius: radius * 1.2
            )
        )
    }

    private func drawWell(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        let r = radius * 0.97
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
            with: .radialGradient(
                Gradient(colors: [palette.surface, palette.well]),
                center: center, startRadius: 0, endRadius: r
            )
        )
    }

    private func drawRings(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        // Outer brass ring.
        let outer = radius * 0.97
        context.stroke(
            Path(ellipseIn: CGRect(x: center.x - outer, y: center.y - outer,
                                   width: outer * 2, height: outer * 2)),
            with: .color(palette.brass),
            lineWidth: radius * 0.022
        )
        // Hairline inner ring where the figures sit.
        let inner = radius * 0.565
        context.stroke(
            Path(ellipseIn: CGRect(x: center.x - inner, y: center.y - inner,
                                   width: inner * 2, height: inner * 2)),
            with: .color(palette.brass.opacity(0.35)),
            lineWidth: max(0.75, radius * 0.006)
        )
    }

    private func drawTicks(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        for i in 0..<60 {
            let isHour = (i % 5 == 0)
            let theta = Double(i) / 60.0 * .pi * 2 - .pi / 2
            let rOuter = radius * 0.935
            let rInner = isHour ? radius * 0.87 : radius * 0.91
            var path = Path()
            path.move(to: point(center: center, radius: rInner, theta: theta))
            path.addLine(to: point(center: center, radius: rOuter, theta: theta))
            context.stroke(
                path,
                with: .color(isHour ? palette.brass.opacity(0.9) : palette.dim),
                lineWidth: isHour ? max(1.6, radius * 0.014) : max(0.8, radius * 0.006)
            )
        }
    }

    private func drawAlarmPip(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat,
                              atMinutes minutes: Double) {
        let theta = (minutes / 60.0) * .pi * 2 - .pi / 2
        let p = point(center: center, radius: radius * 0.97, theta: theta)
        let dot = max(3, radius * 0.03)
        context.fill(
            Path(ellipseIn: CGRect(x: p.x - dot, y: p.y - dot, width: dot * 2, height: dot * 2)),
            with: .color(palette.flame)
        )
    }

    private func drawNumerals(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        for hour in 0..<12 {
            let theta = Double(hour) / 12.0 * .pi * 2 - .pi / 2
            let p = point(center: center, radius: radius * 0.74, theta: theta)
            let numeral = Text(Self.romanNumerals[hour])
                .font(Chapel.display(radius * 0.135, weight: .medium))
                .foregroundColor(palette.text.opacity(hour % 3 == 0 ? 0.95 : 0.7))
            context.draw(numeral, at: p)
        }
    }

    private func drawHands(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        let t = date.timeIntervalSinceReferenceDate
        let secondsFrac = t.truncatingRemainder(dividingBy: 60)
        let minutesFrac = (t / 60).truncatingRemainder(dividingBy: 60)
        let hoursFrac = (t / 3600).truncatingRemainder(dividingBy: 12)

        // Hour hand.
        drawHand(in: &context, center: center, radius: radius * 0.5,
                 fraction: hoursFrac / 12, width: max(3, radius * 0.045),
                 tailFrac: 0.16, color: palette.brass)
        // Minute hand.
        drawHand(in: &context, center: center, radius: radius * 0.72,
                 fraction: minutesFrac / 60, width: max(2.2, radius * 0.03),
                 tailFrac: 0.14, color: palette.brass.opacity(0.92))
        // Second hand — a thin wick, flame-tipped.
        let secondTheta = (secondsFrac / 60) * .pi * 2 - .pi / 2
        let tip = point(center: center, radius: radius * 0.80, theta: secondTheta)
        let tail = point(center: center, radius: -radius * 0.12, theta: secondTheta)
        var wick = Path()
        wick.move(to: tail)
        wick.addLine(to: tip)
        context.stroke(wick, with: .color(palette.flame.opacity(0.9)),
                       lineWidth: max(1, radius * 0.008))
        let tipDot = max(2, radius * 0.014)
        context.fill(
            Path(ellipseIn: CGRect(x: tip.x - tipDot, y: tip.y - tipDot,
                                   width: tipDot * 2, height: tipDot * 2)),
            with: .color(palette.flame)
        )
        // Center boss.
        let boss = max(4, radius * 0.03)
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - boss, y: center.y - boss,
                                   width: boss * 2, height: boss * 2)),
            with: .color(palette.brass)
        )
    }

    private func drawHand(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat,
                          fraction: Double, width: CGFloat, tailFrac: Double, color: Color) {
        let theta = fraction * .pi * 2 - .pi / 2
        var path = Path()
        path.move(to: point(center: center, radius: -radius * tailFrac, theta: theta))
        path.addLine(to: point(center: center, radius: radius, theta: theta))
        context.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    private func point(center: CGPoint, radius: CGFloat, theta: Double) -> CGPoint {
        CGPoint(x: center.x + radius * cos(theta), y: center.y + radius * sin(theta))
    }
}

/// A `LampClockView` driven by a Timeline: hands sweep continuously and the halo
/// flickers on three incommensurate sines so it never visibly loops.
struct LampClockLiveView: View {
    var alarmMinutes: Double? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let rawFlicker = 0.5 * sin(t / 4.7) + 0.32 * sin(t / 1.9) + 0.18 * sin(t / 9.3)
            let pulse = min(1, max(0, 0.55 + 0.45 * rawFlicker))
            LampClockView(
                date: timeline.date,
                palette: ChapelPalette.resolve(for: colorScheme),
                haloPulse: pulse,
                alarmMinutes: alarmMinutes
            )
        }
    }
}

#Preview("Chapel night") {
    ZStack {
        Color(red: 0.05, green: 0.045, blue: 0.035).ignoresSafeArea()
        LampClockLiveView(alarmMinutes: 4.98 * 60)
            .frame(width: 300, height: 300)
    }
}
