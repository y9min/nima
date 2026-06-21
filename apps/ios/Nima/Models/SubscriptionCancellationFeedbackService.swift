import Foundation
import Supabase

enum SubscriptionCancellationReason: String, CaseIterable, Identifiable {
    case tooExpensive = "too_expensive"
    case notUsing = "not_using"
    case didNotHelp = "did_not_help"
    case technicalIssue = "technical_issue"
    case missingFeature = "missing_feature"
    case privacyConcern = "privacy_concern"
    case temporaryPause = "temporary_pause"
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tooExpensive:
            return "Too expensive"
        case .notUsing:
            return "Not using it enough"
        case .didNotHelp:
            return "It did not help"
        case .technicalIssue:
            return "Technical issue"
        case .missingFeature:
            return "Missing feature"
        case .privacyConcern:
            return "Privacy concern"
        case .temporaryPause:
            return "Temporary pause"
        case .other:
            return "Other"
        }
    }
}

enum SubscriptionCancellationFeedbackError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Cancellation feedback is unavailable until Supabase is configured."
    }
}

enum SubscriptionCancellationFeedbackService {
    static func submit(reason: SubscriptionCancellationReason, details: String?) async throws {
        guard let supabaseClient else {
            throw SubscriptionCancellationFeedbackError.unavailable
        }

        let session = try await supabaseClient.auth.session
        let normalizedDetails = details
            .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500)) }
            .flatMap { $0.isEmpty ? nil : $0 }

        let payload = SubscriptionCancellationFeedbackInsert(
            userID: session.user.id,
            reason: reason.rawValue,
            details: normalizedDetails
        )

        try await supabaseClient
            .from("subscription_cancellation_feedback")
            .insert(payload)
            .execute()
    }
}

private struct SubscriptionCancellationFeedbackInsert: Encodable {
    let userID: UUID
    let reason: String
    let details: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case reason
        case details
    }
}
