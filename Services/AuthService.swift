import Foundation

// MARK: - Auth User Model (Stub for future implementation)

/// Represents an authenticated user.
/// This is a stub for future authentication integration.
struct AuthUser {
    let id: String
    let email: String?
    let displayName: String?
    let isAnonymous: Bool

    /// Creates an anonymous user (default for v0.1)
    static var anonymous: AuthUser {
        AuthUser(id: UUID().uuidString, email: nil, displayName: nil, isAnonymous: true)
    }
}

// MARK: - Auth Error Types (Stub for future implementation)

/// Represents authentication errors.
/// This is a stub for future authentication integration.
enum AuthError: Error {
    case notImplemented
    case invalidCredentials
    case networkError(underlying: Error)
    case userNotFound
    case emailAlreadyInUse
    case weakPassword
    case sessionExpired
    case unknown(message: String)

    var localizedDescription: String {
        switch self {
        case .notImplemented:
            return "Authentication is not implemented in v0.1"
        case .invalidCredentials:
            return "Invalid email or password"
        case .networkError(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        case .userNotFound:
            return "User not found"
        case .emailAlreadyInUse:
            return "Email address is already in use"
        case .weakPassword:
            return "Password is too weak"
        case .sessionExpired:
            return "Session has expired, please log in again"
        case .unknown(let message):
            return message
        }
    }
}

// MARK: - Auth Service Protocol

/// Protocol defining authentication operations for future implementation.
///
/// This is a foundation stub for v0.1 of the For Reference Only app.
/// No actual authentication is implemented - this protocol exists to:
/// 1. Define the interface for future auth integration
/// 2. Allow dependency injection in services that may need auth later
/// 3. Enable easy addition of authentication in future versions
///
/// Future implementations could support:
/// - Email/password authentication
/// - Apple Sign In
/// - Biometric authentication (Face ID / Touch ID)
/// - Cloud sync with user accounts
protocol AuthServiceProtocol {

    // MARK: - Authentication State

    /// The currently authenticated user, or nil if not authenticated.
    var currentUser: AuthUser? { get }

    /// Returns true if a user is currently authenticated.
    var isAuthenticated: Bool { get }

    // MARK: - Authentication Methods

    /// Attempts to sign in with email and password.
    /// - Parameters:
    ///   - email: User's email address
    ///   - password: User's password
    /// - Returns: The authenticated user on success
    /// - Throws: AuthError on failure
    func login(email: String, password: String) async throws -> AuthUser

    /// Signs out the current user.
    /// - Throws: AuthError on failure
    func logout() async throws

    /// Creates a new user account with email and password.
    /// - Parameters:
    ///   - email: User's email address
    ///   - password: User's password
    ///   - displayName: Optional display name
    /// - Returns: The newly created user
    /// - Throws: AuthError on failure
    func signUp(email: String, password: String, displayName: String?) async throws -> AuthUser

    /// Sends a password reset email.
    /// - Parameter email: User's email address
    /// - Throws: AuthError on failure
    func resetPassword(email: String) async throws

    // MARK: - Session Management

    /// Refreshes the current authentication session.
    /// - Throws: AuthError on failure
    func refreshSession() async throws

    /// Returns true if the current session is still valid.
    func isSessionValid() -> Bool
}

// MARK: - Default (No-Op) Implementation for v0.1

/// Default implementation of AuthServiceProtocol that does nothing.
/// This is used in v0.1 where no authentication is required.
/// All users are treated as anonymous local users.
///
/// Feature #79: Auth protocol stubs exist for future integration
/// This class provides a no-op implementation that can be replaced
/// with a real authentication service in future versions.
final class AuthService: AuthServiceProtocol {

    // MARK: - Singleton

    /// Shared instance for app-wide use
    static let shared = AuthService()

    // MARK: - Properties

    /// In v0.1, always returns an anonymous user
    var currentUser: AuthUser? {
        return .anonymous
    }

    /// In v0.1, always returns true (no authentication required)
    var isAuthenticated: Bool {
        return true // All local users are "authenticated" in v0.1
    }

    // MARK: - Initialization

    private init() {
        // Private init for singleton pattern
        print("AuthService: Initialized (v0.1 - no authentication)")
    }

    // MARK: - AuthServiceProtocol Methods

    /// Login is not implemented in v0.1.
    /// - Throws: AuthError.notImplemented
    func login(email: String, password: String) async throws -> AuthUser {
        print("AuthService: login() called - not implemented in v0.1")
        throw AuthError.notImplemented
    }

    /// Logout is not implemented in v0.1.
    /// - Throws: AuthError.notImplemented
    func logout() async throws {
        print("AuthService: logout() called - not implemented in v0.1")
        throw AuthError.notImplemented
    }

    /// Sign up is not implemented in v0.1.
    /// - Throws: AuthError.notImplemented
    func signUp(email: String, password: String, displayName: String?) async throws -> AuthUser {
        print("AuthService: signUp() called - not implemented in v0.1")
        throw AuthError.notImplemented
    }

    /// Password reset is not implemented in v0.1.
    /// - Throws: AuthError.notImplemented
    func resetPassword(email: String) async throws {
        print("AuthService: resetPassword() called - not implemented in v0.1")
        throw AuthError.notImplemented
    }

    /// Session refresh is not implemented in v0.1.
    /// - Throws: AuthError.notImplemented
    func refreshSession() async throws {
        print("AuthService: refreshSession() called - not implemented in v0.1")
        throw AuthError.notImplemented
    }

    /// In v0.1, session is always valid (no authentication).
    func isSessionValid() -> Bool {
        return true // Always valid in v0.1
    }
}
