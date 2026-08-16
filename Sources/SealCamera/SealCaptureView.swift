import SwiftUI
import AVFoundation
import UIKit

// MARK: - Camera plumbing (shared with the setup flow)

/// Owns one AVCaptureSession + photo output. The session is configured off
/// the main thread; photos come back as a CGImage + EXIF orientation, which is
/// exactly what the feature-print matcher needs.

final class SealCameraController: NSObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()

    var onPhoto: ((CGImage, CGImagePropertyOrientation) -> Void)?

    private let configureQueue = DispatchQueue(label: "miqat.seal.camera")
    private var photoOutput: AVCapturePhotoOutput?

    func start() {
        configureQueue.async { [session, self] in
            guard !session.isRunning else { return }

            session.beginConfiguration()
            defer { session.commitConfiguration() }

            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: device)
            else { return }

            if session.canAddInput(input) { session.addInput(input) }

            let output = AVCapturePhotoOutput()
            if session.canAddOutput(output) {
                output.maxPhotoQualityPriorization = .quality
                session.addOutput(output)
            }
            self.photoOutput = output   // assigned on the same queue we read from in capture()

            if !session.isRunning {
                session.startRunning()   // blocking call: off main by construction
            }
        }
    }

    func stop() {
        configureQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    var isReady: Bool { session.isRunning && photoOutput != nil }

    func capturePhoto() {
        configureQueue.async { [session, photoOutput] in
            guard let output = photoOutput, session.isRunning else { return }
            let settings = AVCapturePhotoSettings()
            output.capturePhoto(with: settings, delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVPhoto,
                     error: Error?) {
        guard let cgImage = photo.cgImageRepresentation() else { return }

        var orientation: CGImagePropertyOrientation = .up
        if let raw = photo.metadata?[kCGImagePropertyOrientation] as? UInt32 {
            orientation = CGImagePropertyOrientation(rawValue: raw) ?? .up
        }

        DispatchQueue.main.async { [self] in
            onPhoto?(cgImage, orientation)
        }
    }
}

/// SwiftUI host for the preview layer. The view's backing layer *is* an
/// AVCaptureVideoPreviewLayer, so there is nothing to re-sync on updates.

struct CameraPreviewLayer: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewHostView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewHostView {
        let view = PreviewHostView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewHostView, context: Context) {}
}

// MARK: - The seal step (after prayer)
/// The lamp names one of the kept objects. Only a live photo of that object —
/// close enough in feature-print distance to cross the threshold — releases
/// the rite. A floor, a wall, another object: "the lamp does not know that."

struct SealCaptureView: View {
    let objects: [SealObject]
    var threshold: Double
    var onComplete: () -> Void

    @State private var controller = SealCameraController()
    @State private var chosen: SealObject?
    @State private var cameraReady = false
    @State private var isDenied = false
    @State private var busy = false
    @State private var rejectionDetail: String?

    private let palette = ChapelPalette.chapelNight   // the locked room does not retheme

    var body: some View {
        VStack(spacing: 16) {
            if let chosen {
                Text("THE LAMP ASKS FOR")
                    .chapelLabel(10, weight: .medium)
                    .foregroundStyle(palette.dim)
                Text(chosen.name)
                    .riteWord(26)
                    .foregroundStyle(palette.text)
            } else {
                Text("…")
                    .riteWord(26)
                    .foregroundStyle(palette.dim)
            }

            ZStack {
                if isDenied {
                    deniedCard
                } else {
                    CameraPreviewLayer(session: controller.session)
                        .frame(height: 230)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(palette.brass.opacity(0.4), lineWidth: 1)
                        )

                    if busy {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(palette.well.opacity(0.55))
                        VStack(spacing: 8) {
                            LampFlameMark(size: 24, settled: false)
                            Text("the lamp is looking…")
                                .chapelLabel(12, weight: .regular)
                                .foregroundStyle(palette.dim)
                        }
                    }
                }
            }

            if let detail = rejectionDetail {
                VStack(spacing: 3) {
                    Text("THE LAMP DOES NOT KNOW THAT.")
                        .chapelLabel(12, weight: .semibold)
                        .foregroundStyle(palette.flame)
                    Text(detail)
                        .chapelLabel(10, weight: .regular)
                        .foregroundStyle(palette.dim.opacity(0.8))
                }
            }

            Button(action: takePhoto) {
                ZStack {
                    Circle()
                        .strokeBorder(palette.brass.opacity(cameraReady && !busy ? 0.9 : 0.35), lineWidth: 2)
                    Circle()
                        .fill(palette.brass.opacity(cameraReady && !busy ? 0.28 : 0.1))
                    Text("TAKE")
                        .chapelLabel(12, weight: .semibold)
                        .foregroundStyle(cameraReady && !busy ? palette.text : palette.dim)
                }
                .frame(width: 74, height: 74)
            }
            .buttonStyle(.plain)
            .disabled(!cameraReady || busy)

            Text("a live photo of that object — the floor is not an object")
                .chapelLabel(10, weight: .regular)
                .foregroundStyle(palette.dim.opacity(0.7))
        }
        .padding(.horizontal, 24)
        .onAppear(perform: begin)
        .onDisappear { controller.stop() }
    }

    private var deniedCard: some View {
        VStack(spacing: 10) {
            Text("The camera is closed to Miqat.")
                .font(Chapel.display(18, weight: .regular))
                .foregroundStyle(palette.text)
            Text("The seal cannot be kept without it. Open Settings → Miqat → Camera, or take the emergency exit at the wick below.")
                .chapelLabel(12, weight: .regular)
                .foregroundStyle(palette.dim)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: 320)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(palette.surface.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(palette.flame.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: Flow

    private func begin() {
        if chosen == nil {
            chosen = objects.randomElement()   // named once per rite; retries keep the same object
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted { startSession() } else { isDenied = true }
                }
            }
        default:
            isDenied = true
        }
    }

    private func startSession() {
        controller.onPhoto = handlePhoto
        controller.start()
        cameraReady = true   // preview appears as the session comes up; capture is gated on readiness
    }

    private func takePhoto() {
        guard let chosen, !busy else { return }
        rejectionDetail = nil
        controller.capturePhoto()
    }

    private func handlePhoto(_ image: CGImage, orientation: CGImagePropertyOrientation) {
        guard let chosen else { return }

        busy = true
        Task { @MainActor in
            let verdict = SealMatchEngine.match(
                storedJPEG: chosen.thumbnailJPEG,
                liveImage: image,
                liveOrientation: orientation,
                threshold: threshold
            )

            busy = false
            if verdict.isMatch {
                onComplete()   // the seal passes; the chapel advances
            } else {
                rejectionDetail = verdict.human   // "0.42 — unknown", or the lamp cannot see at all
            }
        }
    }
}

#Preview("Seal — capture") {
    ZStack {
        ChapelLockBackground().ignoresSafeArea()
        SealCaptureView(objects: [], threshold: 0.28) { }
    }
}
