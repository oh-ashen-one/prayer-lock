import SwiftUI
import SwiftData
import AVFoundation

// MARK: - Keeping the seal
/// Photograph 5–15 household objects. Each capture is downscaled to a ~768px
/// JPEG — that thumbnail is the entire on-disk footprint. The Vision feature
/// print (the "embedding") is computed in-process from it at match time, so
/// there is no ML artifact to persist and none to rot.

struct SealSetupFlow: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var controller = SealCameraController()
    @State private var objects: [SealObject] = []
    @State private var isDenied = false
    @State private var ready = false

    private var palette: ChapelPalette { ChapelPalette.resolve(for: scheme) }
    private var count: Int { objects.count }

    var body: some View {
        ZStack {
            ChapelBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    header
                    cameraArea
                    keepRow

                    if !objects.isEmpty {
                        grid
                    }

                    footer
                }
                .padding(24)
            }
        }
        .onAppear {
            refetch()
            beginCamera()
        }
        .onDisappear {
            controller.stop()
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("KEEP THE SEAL")
                .riteWord(24)
                .foregroundStyle(palette.text)

            Text("Photograph \(SealObject.minimumCount)–\(SealObject.maximumCount) objects of your household. After prayer the lamp will name one; a live photo of that object alone passes.")
                .chapelLabel(12, weight: .regular)
                .foregroundStyle(palette.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var cameraArea: some View {
        if isDenied {
            VStack(spacing: 8) {
                Text("The camera is closed to Miqat.")
                    .font(Chapel.display(16, weight: .regular))
                    .foregroundStyle(palette.text)
                Text("Open Settings → Miqat → Camera, then return.")
                    .chapelLabel(11, weight: .regular)
                    .foregroundStyle(palette.dim)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(palette.surface.opacity(0.6))
            )
        } else {
            CameraPreviewLayer(session: controller.session)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(palette.brass.opacity(0.4), lineWidth: 1)
                )
        }
    }

    private var keepRow: some View {
        HStack(spacing: 16) {
            Button(action: keepObject) {
                ZStack {
                    Circle()
                        .strokeBorder(palette.brass.opacity(ready && count < SealObject.maximumCount ? 0.9 : 0.3), lineWidth: 2)
                    Circle()
                        .fill(palette.brass.opacity(ready && count < SealObject.maximumCount ? 0.25 : 0.08))
                    Text("KEEP")
                        .chapelLabel(12, weight: .semibold)
                        .foregroundStyle(ready && count < SealObject.maximumCount ? palette.text : palette.dim)
                }
                .frame(width: 68, height: 68)
            }
            .buttonStyle(.plain)
            .disabled(!ready || count >= SealObject.maximumCount)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(count) / \(SealObject.maximumCount) kept")
                    .chapelLabel(13, weight: .medium)
                    .foregroundStyle(palette.brass.opacity(0.9))

                if count > 0 {
                    Button("Undo the last") { undoLast() }
                        .chapelLabel(11, weight: .regular)
                        .foregroundStyle(palette.dim.opacity(0.85))
                }
            }

            Spacer()
        }
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                  spacing: 10) {
            ForEach(objects) { object in
                thumbnailCell(object)
            }
        }
    }

    private func thumbnailCell(_ object: SealObject) -> some View {
        Group {
            if let uiImage = UIImage(data: object.thumbnailJPEG) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "square.dashed")
                    .foregroundStyle(palette.dim)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(palette.brass.opacity(0.3), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var footer: some View {
        if count >= SealObject.minimumCount {
            Button(action: dismiss) {
                Text("THE SEAL IS KEPT — DONE")
                    .chapelLabel(13, weight: .semibold)
                    .foregroundStyle(palette == ChapelPalette.candlePaper ? ChapelPalette.candlePaper.text : ChapelPalette.chapelNight.well)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(palette.brass)
                    )
            }
        } else {
            Text("\(SealObject.minimumCount - count) more to keep")
                .chapelLabel(12, weight: .regular)
                .foregroundStyle(palette.dim.opacity(0.85))
        }
    }

    // MARK: Flow

    private func beginCamera() {
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
        controller.onPhoto = { image, _ in
            Task { @MainActor [count] in
                guard count < SealObject.maximumCount,
                      let jpeg = jpegThumbnail(of: image) else { return }

                let object = SealObject(name: "Object \(count + 1)", thumbnailJPEG: jpeg)
                self.context.insert(object)
                try? self.context.save()
                withAnimation(.spring(duration: 0.35)) {
                    self.objects.append(object)
                }
            }
        }
        controller.start()
        ready = true
    }

    private func keepObject() {
        guard ready, count < SealObject.maximumCount else { return }
        controller.capturePhoto()
    }

    private func undoLast() {
        guard !objects.isEmpty else { return }
        let last = objects.removeLast()
        context.delete(last)
        try? context.save()
    }

    private func refetch() {
        var descriptor = FetchDescriptor<SealObject>(
            sortBy: [SortDescriptor(\SealObject.createdAt)]
        )
        objects = (try? context.fetch(descriptor)) ?? []
    }
}

// MARK: - Thumbnailing (private to this flow)

/// Downscale + JPEG-encode a captured photo for storage. Kept deliberately
/// lossy and small: the feature print is a semantic fingerprint, not an archive.
private func jpegThumbnail(of image: CGImage, maxPixel: CGFloat = 768, quality: CGFloat = 0.8) -> Data? {
    let width = image.width
    let height = image.height
    guard width > 0, height > 0 else { return nil }

    let scale = min(1.0, maxPixel / CGFloat(max(width, height)))
    let targetWidth = max(1, Int(CGFloat(width) * scale))
    let targetHeight = max(1, Int(CGFloat(height) * scale))

    guard let context = CGContext(
        data: nil,
        width: targetWidth,
        height: targetHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.interpolationQuality = .medium
    context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

    guard let output = context.makeImage() else { return nil }
    return UIImage(cgImage: output).jpegData(compressionQuality: quality)
}

#Preview("Seal setup") {
    SealSetupFlow()
        .environment(AppRuntime())
        .modelContainer(for: Alarm.self, SealObject.self, EmergencyUse.self, inMemory: true)
}
