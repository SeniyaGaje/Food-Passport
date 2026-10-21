import AVFoundation
import UIKit

// MARK: - CameraService

/// The back camera, for photographing a meal (AVFoundation).
///
/// Starting the camera and taking photos block for a moment, so every use of the capture session happens on
/// `sessionQueue`, never on the main thread. That rule is what makes `@unchecked Sendable` safe here.
nonisolated final class CameraService: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    enum CameraError: LocalizedError {
        case captureFailed

        var errorDescription: String? {
            "The photo couldn't be taken. Try again."
        }
    }

    /// Shown by `CameraPreview`.
    let session = AVCaptureSession()

    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "FoodPassport.camera")
    private var isConfigured = false
    private var photoContinuation: CheckedContinuation<UIImage, Error>?

    /// False on the simulator and on devices without a back camera.
    static var isAvailable: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    /// Asks for camera permission the first time. Returns whether the camera may be used.
    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        default: false
        }
    }

    func start() {
        sessionQueue.async { [self] in
            if !isConfigured {
                configure()
            }
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    func takePhoto(withFlash isFlashOn: Bool) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                guard session.isRunning, photoContinuation == nil else {
                    continuation.resume(throwing: CameraError.captureFailed)
                    return
                }
                photoContinuation = continuation

                let settings = AVCapturePhotoSettings()
                if photoOutput.supportedFlashModes.contains(.on) {
                    settings.flashMode = isFlashOn ? .on : .off
                }
                photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        if let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: camera),
           session.canAddInput(input) {
            session.addInput(input)
        }
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        session.commitConfiguration()
        isConfigured = true
    }

    // MARK: AVCapturePhotoCaptureDelegate

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let result: Result<UIImage, Error>
        if let error {
            result = .failure(error)
        } else if let data = photo.fileDataRepresentation(), let image = UIImage(data: data) {
            result = .success(image)
        } else {
            result = .failure(CameraError.captureFailed)
        }

        sessionQueue.async { [self] in
            photoContinuation?.resume(with: result)
            photoContinuation = nil
        }
    }
}
