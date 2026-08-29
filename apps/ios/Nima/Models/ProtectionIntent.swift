import Foundation

struct ProtectionIntent: Equatable, Sendable {
    let vpnRequired: Bool
    let manualRecoveryRequired: Bool
    let source: String
    let revision: Int
}

struct VPNProfileDesiredState: Equatable, Sendable {
    let profileEnabled: Bool
    let onDemandEnabled: Bool
    let disconnectOnSleep: Bool

    static func resolve(intent: ProtectionIntent, rolloutEligible: Bool) -> VPNProfileDesiredState {
        VPNProfileDesiredState(
            profileEnabled: true,
            onDemandEnabled: intent.vpnRequired && rolloutEligible,
            disconnectOnSleep: false
        )
    }
}

struct RuntimeFeatureFlag: Codable, Equatable, Sendable {
    let key: String
    let enabled: Bool
    let rolloutPercentage: Int
    let minimumBuild: Int
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case key
        case enabled
        case rolloutPercentage = "rollout_percentage"
        case minimumBuild = "minimum_build"
        case updatedAt = "updated_at"
    }
}

enum OnDemandRolloutPolicy {
    static let featureKey = "ios_vpn_on_demand_recovery"

    static func isValid(flag: RuntimeFeatureFlag) -> Bool {
        flag.key == featureKey &&
            (0...100).contains(flag.rolloutPercentage) &&
            flag.minimumBuild >= 0
    }

    static func bucket(for installationID: UUID) -> Int {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in installationID.uuidString.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Int(hash % 100)
    }

    static func isEligible(flag: RuntimeFeatureFlag?, build: Int, bucket: Int) -> Bool {
        guard let flag,
              isValid(flag: flag),
              flag.enabled,
              flag.rolloutPercentage > 0,
              build >= flag.minimumBuild else {
            return false
        }
        return bucket < min(100, max(0, flag.rolloutPercentage))
    }
}
