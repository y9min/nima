import XCTest
@testable import Nima

final class AccountDeletionServiceTests: XCTestCase {
    func testDeletionRequestUsesExpectedEndpointAndBearerToken() throws {
        let request = try AccountDeletionService.deletionRequest(
            accountDeletionURL: try XCTUnwrap(URL(string: "https://project.supabase.co/functions/v1/delete-account")),
            accessToken: "access-token",
            publishableKey: "publishable-key"
        )

        XCTAssertEqual(request.url?.absoluteString, "https://project.supabase.co/functions/v1/delete-account")
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "publishable-key")
        XCTAssertNil(request.httpBody)
    }

    func testDeletionRequestIncludesAppleAuthorizationCode() throws {
        let request = try AccountDeletionService.deletionRequest(
            accountDeletionURL: try XCTUnwrap(URL(string: "https://project.supabase.co/functions/v1/delete-account")),
            accessToken: "access-token",
            publishableKey: "publishable-key",
            appleAuthorizationCode: "single-use-code"
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(object, ["apple_authorization_code": "single-use-code"])
    }

    func testDemoAccountDoesNotCallBackend() async throws {
        var didRequest = false

        try await AccountDeletionService.deleteCurrentUser(
            isDemo: true,
            accountDeletionURL: try XCTUnwrap(URL(string: "https://project.supabase.co/functions/v1/delete-account")),
            accessTokenProvider: {
                XCTFail("Demo deletion should not request an access token.")
                return "token"
            },
            requestExecutor: { _ in
                didRequest = true
                return (Data(), URLResponse())
            }
        )

        XCTAssertFalse(didRequest)
    }

    func testMissingFunctionURLFailsBeforeRequestingToken() async {
        do {
            try await AccountDeletionService.deleteCurrentUser(
                isDemo: false,
                accountDeletionURL: nil,
                accessTokenProvider: {
                    XCTFail("Missing function URL should fail before token lookup.")
                    return "token"
                },
                requestExecutor: { _ in
                    XCTFail("Missing function URL should fail before request execution.")
                    return (Data(), URLResponse())
                }
            )
            XCTFail("Expected missing function URL error.")
        } catch {
            XCTAssertEqual(error as? AccountDeletionError, .missingFunctionURL)
        }
    }

    func testBackendFailureThrowsWithoutReportingSuccess() async throws {
        let response = try XCTUnwrap(HTTPURLResponse(
            url: try XCTUnwrap(URL(string: "https://project.supabase.co/functions/v1/delete-account")),
            statusCode: 500,
            httpVersion: nil,
            headerFields: nil
        ))

        do {
            try await AccountDeletionService.deleteCurrentUser(
                isDemo: false,
                accountDeletionURL: try XCTUnwrap(URL(string: "https://project.supabase.co/functions/v1/delete-account")),
                accessTokenProvider: { "token" },
                requestExecutor: { _ in
                    (#"{"error":"cleanup failed"}"#.data(using: .utf8) ?? Data(), response)
                }
            )
            XCTFail("Expected backend failure.")
        } catch {
            XCTAssertEqual(error as? AccountDeletionError, .backend(statusCode: 500, message: "cleanup failed"))
        }
    }

    func testSuccessfulDeletionCompletes() async throws {
        let response = try XCTUnwrap(HTTPURLResponse(
            url: try XCTUnwrap(URL(string: "https://project.supabase.co/functions/v1/delete-account")),
            statusCode: 204,
            httpVersion: nil,
            headerFields: nil
        ))

        try await AccountDeletionService.deleteCurrentUser(
            isDemo: false,
            accountDeletionURL: try XCTUnwrap(URL(string: "https://project.supabase.co/functions/v1/delete-account")),
            accessTokenProvider: { "token" },
            requestExecutor: { request in
                XCTAssertEqual(request.url?.absoluteString, "https://project.supabase.co/functions/v1/delete-account")
                return (Data(), response)
            }
        )
    }

    func testAppleDeletionForwardsAuthorizationCode() async throws {
        let response = try XCTUnwrap(HTTPURLResponse(
            url: try XCTUnwrap(URL(string: "https://project.supabase.co/functions/v1/delete-account")),
            statusCode: 204,
            httpVersion: nil,
            headerFields: nil
        ))

        try await AccountDeletionService.deleteCurrentUser(
            isDemo: false,
            appleAuthorizationCode: "single-use-code",
            accountDeletionURL: try XCTUnwrap(URL(string: "https://project.supabase.co/functions/v1/delete-account")),
            accessTokenProvider: { "token" },
            requestExecutor: { request in
                let body = try XCTUnwrap(request.httpBody)
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
                XCTAssertEqual(object["apple_authorization_code"], "single-use-code")
                return (Data(), response)
            }
        )
    }
}
