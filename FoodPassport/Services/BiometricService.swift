import Foundation
import LocalAuthentication

// MARK: - BiometryKind

/// The biometric sensor the device has set up, used for labels such as "Unlock with Touch ID".
enum BiometryKind: Equatable {
    case faceID
    case touchID
    case opticID
    /// No sensor, or no face or fingerprint enrolled.
    case none

    var name: String {
        switch self {
        case .faceID, .none: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        }
    }

    var systemImage: String {
        switch self {
        case .faceID, .none: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        }
    }
}

// MARK: - BiometricService

/// Checks the student's face or fingerprint before showing their passport.
/// `AppState` only talks to this protocol, so unit tests can use the mock instead of a real sensor.
protocol BiometricService {
    var availableBiometry: BiometryKind { get }

    /// Shows the system Face ID / Touch ID prompt. Returns normally on success and throws a `BiometricError` otherwise.
    func authenticate(reason: String) async throws
}

// MARK: - BiometricError

enum BiometricError: LocalizedError, Equatable {
    case notAvailable
    case notEnrolled
    case lockedOut
    /// The student or the system closed the prompt. Not shown as an error.
    case cancelled
    case failed

    var errorDescription: String? {
        switch self {
        case .notAvailable: "This device doesn't support Face ID or Touch ID."
        case .notEnrolled: "Face ID isn't set up on this device. Set it up in Settings → Face ID & Passcode."
        case .lockedOut: "Face ID is locked after too many attempts. Unlock your device with its passcode, then try again."
        case .cancelled: nil
        case .failed: "Face ID didn't recognise you. Try again."
        }
    }
}

// MARK: - LocalBiometricService

/// `BiometricService` backed by Apple's LocalAuthentication framework.
final class LocalBiometricService: BiometricService {
    var availableBiometry: BiometryKind {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return .none }

        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .none
        }
    }

    func authenticate(reason: String) async throws {
        let context = LAContext()
        // Hide the system "Enter Password" button: the lock screen offers "Use account password" instead.
        context.localizedFallbackTitle = ""

        var availabilityError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &availabilityError) else {
            throw Self.biometricError(from: availabilityError)
        }

        do {
            _ = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
        } catch {
            throw Self.biometricError(from: error as NSError)
        }
    }

    private static func biometricError(from error: NSError?) -> BiometricError {
        guard let error, error.domain == LAErrorDomain else { return .failed }

        switch LAError.Code(rawValue: error.code) {
        case .biometryNotAvailable: return .notAvailable
        case .biometryNotEnrolled, .passcodeNotSet: return .notEnrolled
        case .biometryLockout: return .lockedOut
        case .userCancel, .systemCancel, .appCancel, .userFallback, .notInteractive: return .cancelled
        default: return .failed
        }
    }
}

// MARK: - MockBiometricService

/// In-memory `BiometricService` for previews and unit tests.
final class MockBiometricService: BiometricService {
    var availableBiometry: BiometryKind
    /// Set this to make the next prompt fail, e.g. in a unit test.
    var errorToThrow: BiometricError?
    private(set) var promptCount = 0

    init(availableBiometry: BiometryKind = .faceID) {
        self.availableBiometry = availableBiometry
    }

    func authenticate(reason: String) async throws {
        promptCount += 1
        if let errorToThrow { throw errorToThrow }
    }
}
