import Foundation
import FirebaseAuth

/// Signs the student up, in and out.
/// AppState only uses this protocol, so it can run on Firebase or on the mock (previews and tests).
protocol AuthService {
    /// The signed-in user's ID, or nil when nobody is signed in.
    var currentUserID: String? { get }

    /// Returns the user's ID.
    func signIn(email: String, password: String) async throws -> String

    /// Creates the account and returns the new user's ID.
    func signUp(email: String, password: String) async throws -> String

    func sendPasswordReset(email: String) async throws

    func signOut() throws
}

/// Sign-in problems, in words the student understands.
enum AuthServiceError: LocalizedError, Equatable {
    case invalidCredentials
    case emailAlreadyInUse
    case weakPassword
    case invalidEmail
    case network
    case other(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: "Incorrect email or password."
        case .emailAlreadyInUse: "An account with this email already exists. Try signing in instead."
        case .weakPassword: "Choose a stronger password with at least 8 characters."
        case .invalidEmail: "Enter a valid email address."
        case .network: "You're offline. Check your connection and try again."
        case .other(let message): message
        }
    }
}

/// Email and password sign-in with Firebase Authentication.
/// Only create this after `FirebaseApp.configure()` has run.
final class FirebaseAuthService: AuthService {
    private let auth = Auth.auth()

    var currentUserID: String? {
        auth.currentUser?.uid
    }

    func signIn(email: String, password: String) async throws -> String {
        do {
            let result = try await auth.signIn(withEmail: email, password: password)
            return result.user.uid
        } catch {
            throw Self.friendlyError(from: error)
        }
    }

    func signUp(email: String, password: String) async throws -> String {
        do {
            let result = try await auth.createUser(withEmail: email, password: password)
            return result.user.uid
        } catch {
            throw Self.friendlyError(from: error)
        }
    }

    func sendPasswordReset(email: String) async throws {
        do {
            try await auth.sendPasswordReset(withEmail: email)
        } catch {
            throw Self.friendlyError(from: error)
        }
    }

    func signOut() throws {
        try auth.signOut()
    }

    /// Turns Firebase's error codes into our friendly messages.
    private static func friendlyError(from error: Error) -> AuthServiceError {
        let nsError = error as NSError
        guard nsError.domain == AuthErrorDomain, let code = AuthErrorCode(rawValue: nsError.code) else {
            return .other(error.localizedDescription)
        }

        switch code {
        case .wrongPassword, .invalidCredential, .userNotFound: return .invalidCredentials
        case .emailAlreadyInUse: return .emailAlreadyInUse
        case .weakPassword: return .weakPassword
        case .invalidEmail: return .invalidEmail
        case .networkError: return .network
        default: return .other(error.localizedDescription)
        }
    }
}

/// Fake sign-in for previews, tests and running without Firebase.
/// Any email works as long as the password isn't empty.
final class MockAuthService: AuthService {
    private(set) var currentUserID: String?

    /// Set this in a test to make sign-in or sign-up fail.
    var errorToThrow: AuthServiceError?

    init(signedInUserID: String? = nil) {
        currentUserID = signedInUserID
    }

    func signIn(email: String, password: String) async throws -> String {
        try failIfNeeded()
        guard !email.isEmpty, !password.isEmpty else { throw AuthServiceError.invalidCredentials }
        currentUserID = "mock-user"
        return "mock-user"
    }

    func signUp(email: String, password: String) async throws -> String {
        try failIfNeeded()
        currentUserID = "mock-user"
        return "mock-user"
    }

    func sendPasswordReset(email: String) async throws {
        try failIfNeeded()
    }

    func signOut() throws {
        currentUserID = nil
    }

    private func failIfNeeded() throws {
        if let errorToThrow { throw errorToThrow }
    }
}
