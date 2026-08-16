import SwiftUI

/// The oil-lamp chapel palette: deep night blues for stone and well,
/// candle gold for lit metal, ember amber for the wick. Song-geometry
/// accents (square caps, hairline rules) live in `ChapelGeometry`.
enum ChapelTheme {

    // MARK: Night stone

    static let nightTop = Color(red: 0.055, green: 0.075, blue: 0.13)
    static let night = Color(red: 0.04, green: 0.05, blue: 0.10)
    static let well = Color(red: 0.02, green: 0.03, blue: 0.06)
    static let stone = Color(red: 0.11, green: 0.14, blue: 0.21)
    static let stoneLit = Color(red: 0.17, green: 0.21, blue: 0.30)
    static let hairline = Color(red: 0.26, green: 0.31, blue: 0.42)

    // MARK: Candle gold and wick

    static let brass = Color(red: 0.83, green: 0.69, blue: 0.42)
    static let brassDim = Color(red: 0.58, green: 0.49, blue: 0.32)
    static let flame = Color(red: 1.0, green: 0.82, blue: 0.53)
    static let flameCore = Color(red: 1.0, green: 0.93, blue: 0.78)
    static let ember = Color(red: 0.95, green: 0.46, blue: 0.22)

    // MARK: Text

    static let text = Color(red: 0.93, green: 0.91, blue: 0.86)
    static let dim = Color(red: 0.64, green: 0.66, blue: 0.72)

    // MARK: Geometry (Song-type accents: square caps, hairline rules)

    enum ChapelGeometry {
        static let cardRadius: CGFloat = 10
        static let hairline: CGFloat = 1

        /// A thin brass rule, the chapel's only ornament.
        static func hairlineRule(width: CGFloat = 56) -> some View {
            Rectangle()
                .fill(ChapelTheme.brass.opacity(0.7))
                .frame(width: width, height: ChapelGeometry.hairline)
        }

        /// A square-cornered brass frame, the Song-geometry accent.
        static func sealFrame<Content: View>(
            @ViewBuilder content: () -> Content
        ) -> some View {
            content()
                .padding(14)
                .overlay(
                    Rectangle()
                        .strokeBorder(ChapelTheme.brass.opacity(0.5), lineWidth: ChapelGeometry.hairline)
                )
        }
    }

    // MARK: Type

    /// The chapel's display type: light, wide-tracked serif.
    static func display(_ size: CGFloat, weight: Font.Weight = .light) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// Small tracked labels ("AT", "REPEATS") in a grotesque.
    static func label(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default).smallCaps()
    }

    // MARK: Surfaces

    /// The stone room behind everything.
    struct Background: View {
        var body: some View {
            ZStack {
                LinearGradient(
                    colors: [ChapelTheme.nightTop, ChapelTheme.well],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()
        }
    }

    /// A raised stone card with a hairline brass edge.
    struct Card<Content: View>: View {
        @ViewBuilder var content: () -> Content

        var body: some View {
            content()
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: ChapelGeometry.cardRadius, style: .continuous)
                        .fill(ChapelTheme.stone.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ChapelGeometry.cardRadius, style: .continuous)
                        .strokeBorder(ChapelTheme.brass.opacity(0.22), lineWidth: ChapelGeometry.hairline)
                )
        }
    }
}

extension View {
    /// Wrap in a raised stone card.
    func chapelCard() -> some View {
        ChapelTheme.Card(content: { self })
    }

    /// The chapel's display type.
    func riteWord(_ size: CGFloat, weight: Font.Weight = .light) -> some View {
        font(ChapelTheme.display(size, weight: weight))
    }

    /// Small tracked chapel labels.
    func chapelLabel(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        font(ChapelTheme.label(size, weight: weight))
    }
}
