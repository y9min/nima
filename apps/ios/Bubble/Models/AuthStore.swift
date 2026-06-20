import Foundation
import Observation
import Supabase

@Observable
final class AuthStore {
    var isLoggedIn: Bool = false
    var isDemo: Bool = false
    var userID: UUID?
    var userEmail: String = ""

    func login(email: String, demo: Bool = false) {
        isLoggedIn = true
        isDemo = demo
        userID = nil
        userEmail = email
    }

    func loadCurrentSession() async {
        guard !isDemo, let supabaseClient else { return }
        guard let session = try? await supabaseClient.auth.session else {
            isLoggedIn = false
            userID = nil
            userEmail = ""
            return
        }
        apply(session: session)
    }

    func signInWithApple() async throws {
        let session = try await NativeAuthService.signInWithApple()
        apply(session: session)
    }

    func signInWithGoogle() async throws {
        let session = try await NativeAuthService.signInWithGoogle()
        apply(session: session)
    }

    func logout() async {
        if !isDemo {
            try? await supabaseClient?.auth.signOut()
        }
        isLoggedIn = false
        isDemo = false
        userID = nil
        userEmail = ""
    }

    func listenForAuthChanges() async {
        guard let supabaseClient else { return }
        for await state in supabaseClient.auth.authStateChanges {
            if isDemo { continue }
            if [.initialSession, .signedIn, .signedOut].contains(state.event) {
                if let session = state.session {
                    apply(session: session)
                } else {
                    isLoggedIn = false
                    userID = nil
                    userEmail = ""
                }
            }
        }
    }

    private func apply(session: Session) {
        isLoggedIn = true
        isDemo = false
        userID = session.user.id
        userEmail = session.user.email ?? ""
    }
}
