import Foundation
import Supabase

@MainActor
final class OnDemandRolloutService {
    private let defaults: UserDefaults?
    private(set) var cachedFlag: RuntimeFeatureFlag?
    private(set) var fetchedAt: Date?
    private(set) var installationID: UUID

    init(defaults: UserDefaults? = UserDefaults(suiteName: NimaConstants.appGroupID)) {
        self.defaults = defaults
        if let rawID = defaults?.string(forKey: NimaConstants.onDemandInstallationIDKey),
           let existingID = UUID(uuidString: rawID) {
            installationID = existingID
        } else {
            let newID = UUID()
            installationID = newID
            defaults?.set(newID.uuidString, forKey: NimaConstants.onDemandInstallationIDKey)
        }

        if let data = defaults?.data(forKey: NimaConstants.onDemandRolloutFlagCacheKey) {
            cachedFlag = try? JSONDecoder().decode(RuntimeFeatureFlag.self, from: data)
        }
        if let timestamp = defaults?.object(forKey: NimaConstants.onDemandRolloutFlagFetchedAtKey) as? TimeInterval {
            fetchedAt = Date(timeIntervalSince1970: timestamp)
        }
        persistEligibility()
    }

    var buildNumber: Int {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return Int(raw ?? "") ?? 0
    }

    var rolloutBucket: Int {
        OnDemandRolloutPolicy.bucket(for: installationID)
    }

    var isEligible: Bool {
        OnDemandRolloutPolicy.isEligible(
            flag: cachedFlag,
            build: buildNumber,
            bucket: rolloutBucket
        )
    }

    var cacheAge: TimeInterval? {
        fetchedAt.map { max(0, Date().timeIntervalSince($0)) }
    }

    func refresh() async {
        guard let supabaseClient else {
            persistEligibility()
            return
        }

        do {
            let response: RuntimeFeatureFlag = try await supabaseClient
                .from("runtime_feature_flags")
                .select()
                .eq("key", value: OnDemandRolloutPolicy.featureKey)
                .single()
                .execute()
                .value
            guard OnDemandRolloutPolicy.isValid(flag: response) else {
                throw NSError(
                    domain: "Nima.OnDemandRollout",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Remote rollout configuration was invalid"]
                )
            }
            cachedFlag = response
            fetchedAt = Date()
            if let data = try? JSONEncoder().encode(response) {
                defaults?.set(data, forKey: NimaConstants.onDemandRolloutFlagCacheKey)
            }
            defaults?.set(fetchedAt?.timeIntervalSince1970, forKey: NimaConstants.onDemandRolloutFlagFetchedAtKey)
        } catch {
            AppDiagnosticsLogger.log("ON_DEMAND_ROLLOUT refresh_failed cached=\(cachedFlag != nil) error=\(error.localizedDescription)")
        }
        persistEligibility()
    }

    private func persistEligibility() {
        defaults?.set(isEligible, forKey: NimaConstants.onDemandRolloutEligibleKey)
    }
}
