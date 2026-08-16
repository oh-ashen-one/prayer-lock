import SwiftUI
import UIKit
import SwiftData

struct SealSetupFlow: View {
    @StateObject private var controller = SealCameraController()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(controller.isRunning ? "Camera running." : (controller.errorText ?? "Camera idle."))
                    .font(.headline)

                if let data = controller.capturedImageData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                HStack {
                    Button(controller.isRunning ? "Stop" : "Start", action: toggleCamera)
                        .buttonStyle(.borderedProminent)

                    Button("Capture", action: capturePhoto)
                        .buttonStyle(.bordered)
                        .disabled(!controller.isRunning)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Seal Setup")
        }
    }

    private func toggleCamera() {
        if controller.isRunning {
            controller.stop()
        } else {
            controller.start()
        }
    }

    private func capturePhoto() {
        controller.capture()
    }
}

private func makeSealSetupPreviewContainer() -> ModelContainer {
    do {
        return try ModelContainer(
            for: Schema([Alarm.self, SealObject.self, EmergencyUse.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    } catch {
        fatalError("Failed to create Seal Setup preview container: \(error)")
    }
}

#Preview {
    SealSetupFlow()
        .modelContainer(makeSealSetupPreviewContainer())
}
