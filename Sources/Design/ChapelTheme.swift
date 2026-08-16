import SwiftUI

// MARK: - Typefaces
//
// The brief asks for a serious serif on time and ritual words, and a humanist
// sans for UI chrome. SF's built-in designs give us exactly that with zero
// bundled font assets: .serif (SF Serif) for display, the default SF text face
// (a humanist sans) for everything operational.

enum Chapel {
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

// MARK: - Palettes
//
// Two rooms, one app. Dark is the night chapel (wool dark, brass, candle
// flame). Light is candle-paper: warm cream that still reads as lit from a
// flame, never as sterile white.

struct ChapelPalette: Equatable {
    let well: Color      // deepest background
    let surface: Color   // card faces, clock face center
    let brass: Color     // rings, hands, structural lines
    let flame: Color     // the living accent: second hand, pips, glows, warnings
    let text: Color      // primary text
    let dim: Color       // secondary text, minor ticks

    static let chapelNight = ChapelPalette(
        well: Color(red: 0.043, green: 0.039, blue: 0.031),
        surface: Color(red: 0.104, green: 0.090, blue: 0.067),
        brass: Color(red: 0.784, green: 0.620, blue: 0.345),
        flame: Color(red: 1.000, green: 0.620, blue: 0.250),
        text: Color(red: 0.933, green: 0.894, blue: 0.800),
        dim: Color(red: 0.475, green: 0.439, blue: 0.376)
    )

    static let candlePaper = ChapelPalette(
        well: Color(red: 0.965, green: 0.937, blue: 0.855),
        surface: Color(red: 0.929, green: 0.894, blue: 0.796),
        brass: Color(red: 0.522, green: 0.384, blue: 0.161),
        flame: Color(red: 0.824, green: 0.451, blue: 0.122),
        text: Color(red: 0.157, green: 0.122, blue: 0.071),
        dim: Color(red: 0.459, green: 0.396, blue: 0.286)
    )

    static func resolve(for scheme: ColorScheme) -> ChapelPalette {
        scheme == .dark ? .chapelNight : .candlePaper
    }
}

// MARK: - Backgrounds

/// The room the app sits in: a vertical wash from lamp-warmed surface into
/// well, with flame light pooled at the top edge like a hanging lamp.
struct ChapelBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = ChapelPalette.resolve(for: scheme)
        ZStack {
            LinearGradient(
                colors: [palette.surface, palette.well],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [palette.brass.opacity(palette == .candlePaper ? 0.20 : 0.16), .clear],
                center: UnitPoint(x: 0.5, y: -0.12),
                startRadius: 24,
                endRadius: 520
            )
        }
    }
}

/// The full-screen background used inside the locked chapel. Fixed dark,
/// independent of system appearance: a rite in progress does not retheme.
struct ChapelLockBackground: View {
    var body: some View {
        let palette = ChapelPalette.chapelNight
        ZStack {
            LinearGradient(
                colors: [palette.surface.opacity(0.9), palette.well],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [palette.flame.opacity(0.14), .clear],
                center: UnitPoint(x: 0.5, y: 0.16),
                startRadius: 12,
                endRadius: 460
            )
        }
    }
}

// MARK: - Shared surfaces

/// A raised card of paper/wool with a brass hairline. Used by the home
/// screen, the vestry (settings), and inside the chapel for step detail.
private struct ChapelCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let palette = ChapelPalette.resolve(for: scheme)
        content
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(palette.surface.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(palette.brass.opacity(0.35), lineWidth: 1)
            )
    }
}

extension View {
    func chapelCard() -> some View { modifier(ChapelCardModifier()) }

    /// Standard ritual word: large serif, tracked slightly.
    func riteWord(_ size: CGFloat = 40) -> some View {
        font(Chapel.display(size, weight: .medium))
            .tracking(1.2)
    }

    /// Standard UI label: humanist sans, small-caps energy via tracking.
    func chapelLabel(_ size: CGFloat = 13, weight: Font.Weight = .medium) -> some View {
        font(Chapel.ui(size, weight: weight))
            .tracking(0.8)
    }
}

#Preview("Night palette") {
    ZStack {
        ChapelBackground().ignoresSafeArea()
        VStack(spacing: 16) {
            Text("Miqat")
                .riteWord(34)
                .foregroundStyle(ChapelPalette.chapelNight.brass)
            Text("THE LAMP IS BURNING")
                .chapelLabel(12)
                .foregroundStyle(ChapelPalette.chapelNight.dim)
            LampClockLiveView(alarmMinutes: 5 * 60 + 3)
                .frame(width: 240, height: 240)
        }
    }
}

#Preview("Candle paper palette") {
    ZStack {
        ChapelBackground().ignoresSafeArea()
        Text("Miqat")
            .riteWord(34)
            .foregroundStyle(ChapelPalette.candlePaper.brass)
    }
    .preferredColorScheme(.light)
}
