import Foundation
import Observation
import Supabase

enum AuthSessionState: Equatable {
    case idle
    case loading
    case authenticated
    case unauthenticated
    case failed(String)
}

enum SubscriptionIdentity: Equatable {
    case none
    case demo(email: String)
    case authenticated(userID: UUID, email: String)
}

@Observable
final class AuthStore {
    static let emailAuthRedirectURL = URL(string: "nima://auth-callback")!
    private static let annualDemoAccountEmails: Set<String> = [
        "ya@nima.so",
        "review@nima.so",
    ]
    private static let persistedDemoEmailKey = "auth.persistedDemoEmail"

    var isLoggedIn: Bool = false
    var isDemo: Bool = false
    var userID: UUID?
    var userEmail: String = ""
    var appleUserID: String?
    var sessionState: AuthSessionState = .idle

    var isAppleAccount: Bool {
        appleUserID != nil
    }

    var subscriptionIdentity: SubscriptionIdentity {
        if isDemo {
            return .demo(email: Self.normalizedEmail(userEmail))
        }
        guard isLoggedIn, let userID else {
            return .none
        }
        return .authenticated(userID: userID, email: Self.normalizedEmail(userEmail))
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard
            let email = defaults.string(forKey: Self.persistedDemoEmailKey),
            Self.isAnnualDemoAccount(email: email)
        else {
            return
        }

        isLoggedIn = true
        isDemo = true
        userEmail = Self.normalizedEmail(email)
        sessionState = .authenticated
    }

    func login(email: String, demo: Bool = false) {
        isLoggedIn = true
        isDemo = demo
        userID = nil
        userEmail = Self.normalizedEmail(email)
        appleUserID = nil
        sessionState = .authenticated
        if demo {
            defaults.set(userEmail, forKey: Self.persistedDemoEmailKey)
        } else {
            defaults.removeObject(forKey: Self.persistedDemoEmailKey)
        }
    }

    func loadCurrentSession() async {
        guard !isDemo, let supabaseClient else { return }
        sessionState = .loading
        do {
            let session = try await supabaseClient.auth.session
            apply(session: session)
        } catch AuthError.sessionMissing {
            clearSession()
        } catch {
            // A network/token refresh failure is not proof that the user signed out.
            // Keep the last known identity until Supabase emits a definitive auth event.
            sessionState = .failed(error.localizedDescription)
        }
    }

    func signInWithApple() async throws {
        let session = try await NativeAuthService.signInWithApple()
        apply(session: session)
    }

    func signInWithGoogle() async throws {
        let session = try await NativeAuthService.signInWithGoogle()
        apply(session: session)
    }

    func sendEmailMagicLink(to email: String) async throws {
        guard let supabaseClient else {
            throw EmailAuthError.unavailable
        }
        try await supabaseClient.auth.signInWithOTP(
            email: email,
            redirectTo: Self.emailAuthRedirectURL,
            shouldCreateUser: true
        )
    }

    func handleEmailMagicLink(_ url: URL) async throws -> Bool {
        guard url.scheme == Self.emailAuthRedirectURL.scheme else {
            return false
        }
        guard let supabaseClient else {
            throw EmailAuthError.unavailable
        }
        let session = try await supabaseClient.auth.session(from: url)
        apply(session: session)
        return true
    }

    func logout() async {
        if !isDemo {
            try? await supabaseClient?.auth.signOut()
        }
        defaults.removeObject(forKey: Self.persistedDemoEmailKey)
        clearSession()
    }

    func listenForAuthChanges() async {
        guard let supabaseClient else { return }
        for await state in supabaseClient.auth.authStateChanges {
            if isDemo { continue }
            if let session = state.session {
                apply(session: session)
            } else if state.event == .initialSession || state.event == .signedOut {
                clearSession()
            }
        }
    }

    private func apply(session: Session) {
        defaults.removeObject(forKey: Self.persistedDemoEmailKey)
        isLoggedIn = true
        isDemo = false
        userID = session.user.id
        userEmail = Self.normalizedEmail(session.user.email ?? "")
        appleUserID = session.user.identities?
            .first { $0.provider.caseInsensitiveCompare("apple") == .orderedSame }?
            .id
        sessionState = .authenticated
    }

    private func clearSession() {
        isLoggedIn = false
        isDemo = false
        userID = nil
        userEmail = ""
        appleUserID = nil
        sessionState = .unauthenticated
    }

    static func isAnnualDemoAccount(email: String) -> Bool {
        annualDemoAccountEmails.contains(normalizedEmail(email))
    }

    static func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum EmailAuthError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Email login is unavailable right now."
        }
    }
}
