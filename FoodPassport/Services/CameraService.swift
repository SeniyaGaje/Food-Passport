import AVFoundation
import UIKit

/// The back camera, for taking a photo of the meal.
/// The camera is slow to start, so all camera work runs on `sessionQueue`, never the main thread.
/// Because everything goes through that one queue, `@unchecked Sendable` is safe here.
nonisolated final class CameraService: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    enum CameraError: LocalizedError {
        case captureFailed

        var errorDescription: String? {
            "The photo couldn't be taken. Try again."
        }
    }

    /// The live picture, shown by `CameraPreview`.
    let session = AVCaptureSession()

    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "FoodPassport.camera")
    private var isConfigured = false
    private var photoContinuation: CheckedContinuation<UIImage, Error>?

    /// False on the simulator, which has no camera.
    static var isAvailable: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    /// Asks for camera permission the first time. Returns true if we can use the camera.
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

    /// Takes a photo and waits for the result.
    func takePhoto(withFlash isFlashOn: Bool) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                // Only one photo at a time.
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

    /// Connects the back camera to the session, once.
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

    // AVCapturePhotoCaptureDelegate

    /// Called by iOS when the photo is ready. Hands it back to `takePhoto`.
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
