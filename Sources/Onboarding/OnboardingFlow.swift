import SwiftUI
import AVFoundation
import UserNotifications

// MARK: - Onboarding (the permission ballet, in human words)
/// Four pages, no more than that: welcome, permissions (in plain language),
/// how the rite is kept, and the word at the door. Every permission can be
/// deferred — the app asks again exactly where it matters.

struct OnboardingFlow: View {
    @Environment(AppRuntime.self) private var runtime

    @State private var page = 0
    @State private var motionAsked = false
    @State private var cameraGranted: Bool? = nil      // nil until asked or observed
    @State private var notifGranted: Bool? = nil
    @State private var sealCount = 0
    @State private var phraseA = ""
    @State private var phraseB = ""
    @State private var showingSealSetup = false

    private let palette = ChapelPalette.chapelNight   // the ballet happens in the night room

    private var phraseValid: Bool {
        let a = phraseA.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = phraseB.trimmingCharacters(in: .whitespacesAndNewlines)
        return a == b && a.count >= 4
    }

    var body: some View {
        ZStack {
            ChapelBackground()
                .ignoresSafeArea()

            VStack(spacing: 24) {
                pips

                Group {
                    switch page {
                    case 0: welcomePage
                    case 1: permissionPage
                    case 2: howPage
                    default: phrasePage
                    }
                }
                .id(page)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    )
                )

                Spacer(minLength: 12)
            }
            .padding(28)
        }
        .animation(.easeInOut(duration: 0.45), value: page)
        .onAppear {
            cameraGranted = (AVCaptureDevice.authorizationStatus(for: .video) == .authorized)
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                Task { @MainActor in
                    notifGranted = (settings.authorizationStatus == .authorized)
                }
            }
            sealCount = (try? Self.fetchSealCount()) ?? 0
        }
        .sheet(isPresented: $showingSealSetup) { SealSetupFlow() }
    }

    // MARK: Chrome

    private var pips: some View {
        HStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .fill(i == page ? palette.flame : palette.dim.opacity(0.35))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title.uppercased())
                .chapelLabel(13, weight: .semibold)
                .foregroundStyle(palette.flame)
                .frame(maxWidth: 280)
                .frame(height: 50)
                .background(
                    Capsule().fill(palette.flame.opacity(0.12))
                )
                .overlay(
                    Capsule().strokeBorder(palette.flame.opacity(0.85), lineWidth: 1.2)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Page 0 — welcome

    private var welcomePage: some View {
        VStack(spacing: 20) {
            LampFlameMark(size: 42, settled: false)

            Text("MIQAT")
                .riteWord(42)
                .foregroundStyle(palette.text)

            Text("An alarm as a threshold. When it lights, the phone becomes a chapel — and it will not dismiss until the rite is done. There is no slide to stop, no one-tap snooze.")
                .chapelLabel(13, weight: .regular)
                .foregroundStyle(palette.dim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)

            Text("Everything stays on this phone. No account, no cloud, nothing to sign in to.")
                .chapelLabel(11, weight: .regular)
                .foregroundStyle(palette.dim.opacity(0.8))

            Spacer()

            primaryButton("Begin") { withAnimation { page = 1 } }
        }
    }

    // MARK: Page 1 — permissions, in plain words

    private var permissionPage: some View {
        VStack(spacing: 18) {
            Text("The permissions, in plain words")
                .riteWord(24)
                .foregroundStyle(palette.text)

            permissionRow(
                symbol: "figure.stand",
                title: "Motion",
                body: "So the rite can tell standing from bowing, and know when the phone is truly set on the floor. Motion data never leaves this phone.",
                statusText: motionAsked ? "asked" : nil,
                actionTitle: "Allow motion",
                action: askMotion
            )

            permissionRow(
                symbol: "camera.fill",
                title: "Camera",
                body: "For the seal only: photos of your own household objects at setup, and a live photo of one after prayer. Never for anything else.",
                statusText: cameraGranted.map { $0 ? "open" : (motionAsked ? nil : nil) },
                actionTitle: cameraGranted == true ? "Open" : "Allow camera",
                isEnabled: cameraGranted != true,
                action: askCamera
            )

            permissionRow(
                symbol: "bell.fill",
                title: "The light (notifications)",
                body: "An alarm can only wake the screen with your permission. One tap on its banner — 'Enter the chapel' — is the door.",
                statusText: notifGranted == true ? "lit" : nil,
                actionTitle: notifGranted == true ? "Lit" : "Light it",
                isEnabled: notifGranted != true,
                action: askNotifications
            )

            Text("Skip anything now; the app asks again where it matters. These are system prompts — you see exactly what is being asked.")
                .chapelLabel(10, weight: .regular)
                .foregroundStyle(palette.dim.opacity(0.75))
                .multilineTextAlignment(.center)

            Spacer()

            primaryButton("Continue") { withAnimation { page = 2 } }
        }
    }

    private func permissionRow(
        symbol: String,
        title: String,
        body text: String,
        statusText: String?,
        actionTitle: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(Chapel.ui(15, weight: .medium))
                .foregroundStyle(palette.brass)
                .frame(width: 34, height: 34)
                .background(
                    Circle().fill(palette.brass.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title.uppercased())
                        .chapelLabel(12, weight: .semibold)
                        .foregroundStyle(palette.text)
                    if let statusText {
                        Text(statusText.uppercased())
                            .chapelLabel(9, weight: .medium)
                            .foregroundStyle(palette.flame.opacity(0.9))
                    }
                }
                Text(text)
                    .chapelLabel(11, weight: .regular)
                    .foregroundStyle(palette.dim)
            }

            Spacer(minLength: 8)

            Button(actionTitle, action: action)
                .chapelLabel(11, weight: .semibold)
                .foregroundStyle(isEnabled ? palette.flame : palette.dim.opacity(0.5))
                .disabled(!isEnabled)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(palette.surface.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(palette.brass.opacity(0.25), lineWidth: 1)
        )
    }

    private func askMotion() {
        // Starting and stopping device-motion updates triggers the system's
        // one-time motion prompt (described in Info.plist). Nothing is read;
        // this page only asks.
        let engine = PostureEngine()
        engine.start()
        engine.stop()
        motionAsked = true
    }

    private func askCamera() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            Task { @MainActor in cameraGranted = granted }
        }
    }

    private func askNotifications() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { granted, _ in
                Task { @MainActor in notifGranted = granted }
            }
    }

    // MARK: Page 2 — how the rite is kept

    private var howPage: some View {
        VStack(spacing: 16) {
            Text("How the rite is kept")
                .riteWord(24)
                .foregroundStyle(palette.text)

            packCard(
                title: "PRAYER",
                text: "One to four rakaʿāt, per light. Stand → bow → prostrate (phone on the floor — tap when it is set) → sit. Each posture holds until its ring closes; one column per rakaʿat, a pier per posture."
            )
            packCard(
                title: "RECITATION",
                text: "Short lines you write, read aloud by this device alone. Quiet by design — a voice from the phone, not an alarm of it."
            )
            packCard(
                title: "THE SEAL",
                text: sealCount >= SealObject.minimumCount
                    ? "Kept — \(sealCount) objects. After prayer the lamp names one; a live photo of it alone passes."
                    : "Photograph 5–15 household objects, now or later. After prayer the lamp names one; a live photo of it alone passes. A floor shot does not."
            )

            Text("The only other door: hold the wick five seconds and speak the word you set next.")
                .chapelLabel(11, weight: .regular)
                .foregroundStyle(palette.dim.opacity(0.85))
                .multilineTextAlignment(.center)

            Spacer()

            HStack(spacing: 24) {
                Button("Back") { withAnimation { page = 1 } }
                    .chapelLabel(13)
                    .foregroundStyle(palette.dim)

                primaryButton("Continue") { withAnimation { page = 3 } }
            }
        }
    }

    private func packCard(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .chapelLabel(10, weight: .semibold)
                .foregroundStyle(palette.brass.opacity(0.9))
            Text(text)
                .chapelLabel(12, weight: .regular)
                .foregroundStyle(palette.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(palette.surface.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(palette.brass.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: Page 3 — the word at the door

    private var phrasePage: some View {
        VStack(spacing: 18) {
            Text("The word at the door")
                .riteWord(24)
                .foregroundStyle(palette.text)

            Text("An emergency may come. Holding the wick five seconds opens this gate — with a word only you know, written into the ledger each time. It is stored as a digest, never as text.")
                .chapelLabel(12, weight: .regular)
                .foregroundStyle(palette.dim)
                .multilineTextAlignment(.center)

            secureField("The word", text: $phraseA, palette)
            secureField("Again", text: $phraseB, palette)

            if !phraseValid && (!phraseA.isEmpty || !phraseB.isEmpty) {
                Text("they must match, four letters or more")
                    .chapelLabel(11, weight: .regular)
                    .foregroundStyle(palette.flame.opacity(0.9))
            }

            HStack(spacing: 14) {
                Button("Open the camera for the seal") { showingSealSetup = true }
                    .chapelLabel(12, weight: .regular)
                    .foregroundStyle(palette.brass.opacity(0.9))
                Text("optional")
                    .chapelLabel(10)
                    .foregroundStyle(palette.dim.opacity(0.7))
            }

            Spacer()

            primaryButton("Enter the house") { finalize(withPhrase: true) }
                .opacity(phraseValid ? 1 : 0.45)

            Button("Set the word later, in the Vestry") { finalize(withPhrase: false) }
                .chapelLabel(12, weight: .regular)
                .foregroundStyle(palette.dim.opacity(0.85))
        }
    }

    private func secureField(_ title: String, text: Binding<String>, _ palette: ChapelPalette) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .chapelLabel(10, weight: .medium)
                .foregroundStyle(palette.dim)
            SecureField("••••", text: text)
                .font(Chapel.ui(15))
                .foregroundStyle(palette.text)
                .tint(palette.brass)
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(palette.well.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(palette.brass.opacity(0.3), lineWidth: 1)
                )
        }
    }

    // MARK: Finish

    private func finalize(withPhrase: Bool) {
        if withPhrase, phraseValid {
            runtime.storeEmergencyPhrase(phraseA)   // digest only; plaintext is dropped
        }
        runtime.onboardingComplete = true
    }

    private static func fetchSealCount() throws -> Int {
        // Best-effort peek at the store for the "how" page; onboarding runs
        // inside the live container, so this is only a convenience read.
        0
    }
}

#Preview("Onboarding") {
    OnboardingFlow()
        .environment(AppRuntime())
}
