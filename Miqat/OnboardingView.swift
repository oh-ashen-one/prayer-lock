import SwiftUI

/// The first-arrival rite: three quiet screens that explain the lamp, the
/// locked chapel, and the two doors out. No account, no cloud, nothing to
/// sign in to. Walking it once marks the chapel as lit; the vestry can
/// always open it again.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss

    /// One screen of the rite, kept as a small struct so it can carry an id
    /// for transitions (a tuple could not).
    private struct Page: Identifiable, Equatable {
        let id: Int
        let title: String
        let line: String
    }

    @State private var page = 0

    private static let pages: [Page] = [
        Page(
            id: 0,
            title: "A lamp, not an alarm",
            line: "Miqat keeps the hours you appoint. When one arrives it lights a small flame on the home face, and nothing else."
        ),
        Page(
            id: 1,
            title: "The phone becomes a chapel",
            line: "When the light fires, the whole screen is stone. There is no slide to stop and no one-tap snooze. The only way through is to keep the rite: stand, bow, prostrate, sit."
        ),
        Page(
            id: 2,
            title: "Two doors out",
            line: "Finish the rite, or hold the ember for five seconds and type the phrase you choose in the vestry. Both stay on this phone."
        )
    ]

    private var currentPage: Page { Self.pages[page] }

    var body: some View {
        ZStack(alignment: .bottom) {
            ChapelTheme.Background()

            VStack(spacing: 0) {
                HStack {
                    Button("Skip") { finish() }
                        .chapelLabel(11, weight: .regular)
                        .foregroundStyle(ChapelTheme.dim.opacity(0.7))

                    Spacer()
                }
                .padding(.horizontal, 34)
                .padding(.top, 20)

                Spacer()

                VStack(spacing: 20) {
                    ChapelTheme.ChapelGeometry.hairlineRule(width: 40)

                    Text(currentPage.title)
                        .font(ChapelTheme.display(30, weight: .light))
                        .foregroundStyle(ChapelTheme.text)
                        .multilineTextAlignment(.center)

                    Text(currentPage.line)
                        .font(ChapelTheme.display(15, weight: .regular))
                        .foregroundStyle(ChapelTheme.dim)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)

                    Text("no account · no cloud · everything stays on this phone")
                        .chapelLabel(10, weight: .regular)
                        .foregroundStyle(ChapelTheme.brassDim)
                }
                .padding(.horizontal, 34)
                .id(currentPage.id)

                Spacer()

                HStack(spacing: 10) {
                    ForEach(Self.pages) { item in
                        Circle()
                            .fill(item.id == page ? ChapelTheme.brass : ChapelTheme.hairline.opacity(0.6))
                            .frame(width: 5, height: 5)
                    }
                }

                Button(action: advance) {
                    Text(page == Self.pages.count - 1 ? "Enter the chapel" : "Continue")
                        .chapelLabel(14, weight: .medium)
                        .foregroundStyle(ChapelTheme.well)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: ChapelTheme.ChapelGeometry.cardRadius, style: .continuous)
                                .fill(ChapelTheme.brass)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 34)
                .padding(.bottom, 26)
            }
        }
    }

    private func advance() {
        if page < Self.pages.count - 1 {
            withAnimation(.easeInOut(duration: 0.3)) { page += 1 }
        } else {
            finish()
        }
    }

    private func finish() {
        ChapelSettingsStore.markOnboarded()
        dismiss()
    }
}

#Preview {
    OnboardingView()
        .preferredColorScheme(.dark)
}
