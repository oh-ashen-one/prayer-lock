import AVFoundation
import Combine
import Dispatch
import Foundation

final class SealCameraController: NSObject, ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var errorText: String?
    @Published private(set) var capturedImageData: Data?

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "Miqat.SealCameraController.session")

    func start() {
        guard !isRunning else { return }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startConfiguration()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.startConfiguration()
                } else {
                    self.updateErrorOnMain("Camera access is not available.")
                }
            }
        default:
            updateErrorOnMain("Camera access is not authorized.")
        }
    }

    func stop() {
        guard isRunning else { return }

        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }

            DispatchQueue.main.async { [weak self] in
                self?.isRunning = false
            }
        }
    }

    func capture() {
        sessionQueue.async { [weak self] in
            guard let self, self.isRunning else { return }

            let settings = AVCapturePhotoSettings()
            settings.flashMode = .off
            self.photoOutput.processPhoto(with: settings, delegate: self)
        }
    }

    private func startConfiguration() {
        sessionQueue.async { [weak self] in
            self?.configureAndStart()
        }
    }

    private func configureAndStart() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let videoDevice = AVCaptureDevice.default(for: .video) else {
            session.commitConfiguration()
            updateErrorOnMain("No camera available on this device.")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: videoDevice)
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                updateErrorOnMain("Could not add camera input.")
                return
            }
            session.addInput(input)
        } catch {
            session.commitConfiguration()
            updateErrorOnMain("Camera input failed: \(error.localizedDescription)")
            return
        }

        guard session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            updateErrorOnMain("Could not add camera output.")
            return
        }
        session.addOutput(photoOutput)

        session.commitConfiguration()

        if session.startRunning() {
            updateIsRunningOnMain(true)
        } else {
            updateErrorOnMain("Could not start the camera session.")
        }
    }

    private func updateIsRunningOnMain(_ value: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.isRunning = value
        }
    }

    private func updateErrorOnMain(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.errorText = message
        }
    }

    deinit {
        session.stopRunning()
    }
}

extension SealCameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let data = photo.fileDataRepresentation() {
            DispatchQueue.main.async { [weak self] in
                self?.capturedImageData = data
            }
        }

        if let error {
            DispatchQueue.main.async { [weak self] in
                self?.errorText = "Photo capture failed: \(error.localizedDescription)"
            }
        }
    }
}
