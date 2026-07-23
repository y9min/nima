import AuthenticationServices
import CryptoKit
import Foundation
import GoogleSignIn
import Security
import Supabase
import UIKit

enum NativeAuthError: LocalizedError {
    case unavailable
    case missingAppleIdentityToken
    case missingAppleAuthorizationCode
    case missingGoogleClientID
    case missingGoogleIdentityToken
    case missingPresentationContext
    case nonceGenerationFailed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Sign-in is unavailable until Supabase is configured."
        case .missingAppleIdentityToken:
            return "Apple did not return a valid identity token."
        case .missingAppleAuthorizationCode:
            return "Apple did not return the authorization needed to delete this account."
        case .missingGoogleClientID:
            return "Google sign-in is missing its iOS client ID."
        case .missingGoogleIdentityToken:
            return "Google did not return a valid identity token."
        case .missingPresentationContext:
            return "Could not find an active app window for sign-in."
        case .nonceGenerationFailed:
            return "Could not prepare a secure sign-in request."
        }
    }
}

struct AppleRevocationCredential: Equatable {
    let authorizationCode: String
    let userID: String
}

enum NativeAuthService {
    @MainActor
    static func signInWithApple() async throws -> Session {
        guard let supabaseClient else { throw NativeAuthError.unavailable }

        let rawNonce = try randomNonceString()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.email]
        request.nonce = sha256(rawNonce)

        let authorization = try await AppleAuthorizationCoordinator.perform(request: request)
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityToken = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }) else {
            throw NativeAuthError.missingAppleIdentityToken
        }

        return try await supabaseClient.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .apple,
                idToken: identityToken,
                nonce: rawNonce
            )
        )
    }

    @MainActor
    static func appleRevocationCredential() async throws -> AppleRevocationCredential {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        let authorization = try await AppleAuthorizationCoordinator.perform(request: request)
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let authorizationCode = credential.authorizationCode
                .flatMap({ String(data: $0, encoding: .utf8) }),
              !authorizationCode.isEmpty else {
            throw NativeAuthError.missingAppleAuthorizationCode
        }

        return AppleRevocationCredential(
            authorizationCode: authorizationCode,
            userID: credential.user
        )
    }

    @MainActor
    static func signInWithGoogle() async throws -> Session {
        guard let supabaseClient else { throw NativeAuthError.unavailable }
        guard let clientID = configuredGoogleClientID else {
            throw NativeAuthError.missingGoogleClientID
        }
        guard let presenter = UIApplication.shared.firstKeyWindow?.rootViewController else {
            throw NativeAuthError.missingPresentationContext
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)

        guard let idToken = result.user.idToken?.tokenString else {
            throw NativeAuthError.missingGoogleIdentityToken
        }

        return try await supabaseClient.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .google,
                idToken: idToken
            )
        )
    }

    private static var configuredGoogleClientID: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_IOS_CLIENT_ID") as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }

    private static func randomNonceString(length: Int = 32) throws -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var random: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            guard status == errSecSuccess else {
                throw NativeAuthError.nonceGenerationFailed
            }

            if Int(random) < charset.count {
                result.append(charset[Int(random)])
                remainingLength -= 1
            }
        }

        return result
    }

    private static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
private final class AppleAuthorizationCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private static var current: AppleAuthorizationCoordinator?

    private var continuation: CheckedContinuation<ASAuthorization, Error>?
    private var controller: ASAuthorizationController?

    private init(continuation: CheckedContinuation<ASAuthorization, Error>) {
        self.continuation = continuation
    }

    static func perform(request: ASAuthorizationAppleIDRequest) async throws -> ASAuthorization {
        try await withCheckedThrowingContinuation { continuation in
            let coordinator = AppleAuthorizationCoordinator(continuation: continuation)
            let controller = ASAuthorizationController(authorizationRequests: [request])
            coordinator.controller = controller
            controller.delegate = coordinator
            controller.presentationContextProvider = coordinator
            current = coordinator
            controller.performRequests()
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.firstKeyWindow ?? ASPresentationAnchor()
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        complete(.success(authorization))
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        complete(.failure(error))
    }

    private func complete(_ result: Result<ASAuthorization, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        controller = nil
        Self.current = nil

        switch result {
        case .success(let authorization):
            continuation.resume(returning: authorization)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

private extension UIApplication {
    var firstKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}
