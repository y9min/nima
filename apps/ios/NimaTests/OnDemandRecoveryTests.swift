import XCTest
@testable import Nima

final class OnDemandRecoveryTests: XCTestCase {
    func testManualProtectionAndEligibleRolloutEnableOnDemand() {
        let intent = ProtectionIntent(
            vpnRequired: true,
            manualRecoveryRequired: true,
            source: "test",
            revision: 1
        )

        let desired = VPNProfileDesiredState.resolve(intent: intent, rolloutEligible: true)

        XCTAssertTrue(desired.profileEnabled)
        XCTAssertTrue(desired.onDemandEnabled)
        XCTAssertFalse(desired.disconnectOnSleep)
    }

    func testManualProtectionWithoutEligibleRolloutLeavesOnDemandOff() {
        let intent = ProtectionIntent(
            vpnRequired: true,
            manualRecoveryRequired: true,
            source: "test",
            revision: 1
        )

        XCTAssertFalse(
            VPNProfileDesiredState.resolve(intent: intent, rolloutEligible: false).onDemandEnabled
        )
    }

    func testScheduledProtectionAloneNeverEnablesOnDemand() {
        let intent = ProtectionIntent(
            vpnRequired: true,
            manualRecoveryRequired: false,
            source: "time_windows",
            revision: 2
        )

        XCTAssertTrue(intent.vpnRequired)
        XCTAssertFalse(
            VPNProfileDesiredState.resolve(intent: intent, rolloutEligible: true).onDemandEnabled
        )
    }

    func testManualDisableDuringScheduleKeepsVPNRequiredButDisablesOnDemand() {
        let intent = ProtectionIntent(
            vpnRequired: true,
            manualRecoveryRequired: false,
            source: "manual_disabled_schedule_active",
            revision: 3
        )
        let desired = VPNProfileDesiredState.resolve(intent: intent, rolloutEligible: true)

        XCTAssertTrue(intent.vpnRequired)
        XCTAssertFalse(desired.onDemandEnabled)
    }

    func testRolloutEligibilityHonorsEnabledPercentageAndMinimumBuild() {
        let flag = RuntimeFeatureFlag(
            key: OnDemandRolloutPolicy.featureKey,
            enabled: true,
            rolloutPercentage: 20,
            minimumBuild: 10,
            updatedAt: Date()
        )

        XCTAssertTrue(OnDemandRolloutPolicy.isEligible(flag: flag, build: 10, bucket: 19))
        XCTAssertFalse(OnDemandRolloutPolicy.isEligible(flag: flag, build: 10, bucket: 20))
        XCTAssertFalse(OnDemandRolloutPolicy.isEligible(flag: flag, build: 9, bucket: 0))
    }

    func testDisabledOrMissingRolloutFlagFailsClosed() {
        let disabled = RuntimeFeatureFlag(
            key: OnDemandRolloutPolicy.featureKey,
            enabled: false,
            rolloutPercentage: 100,
            minimumBuild: 0,
            updatedAt: Date()
        )

        XCTAssertFalse(OnDemandRolloutPolicy.isEligible(flag: disabled, build: 99, bucket: 0))
        XCTAssertFalse(OnDemandRolloutPolicy.isEligible(flag: nil, build: 99, bucket: 0))
    }

    func testInvalidRolloutConfigurationFailsClosed() {
        let invalid = RuntimeFeatureFlag(
            key: OnDemandRolloutPolicy.featureKey,
            enabled: true,
            rolloutPercentage: 101,
            minimumBuild: 0,
            updatedAt: Date()
        )

        XCTAssertFalse(OnDemandRolloutPolicy.isValid(flag: invalid))
        XCTAssertFalse(OnDemandRolloutPolicy.isEligible(flag: invalid, build: 99, bucket: 0))
    }

    func testInstallationBucketIsStableAndBounded() {
        let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let first = OnDemandRolloutPolicy.bucket(for: id)
        let second = OnDemandRolloutPolicy.bucket(for: id)

        XCTAssertEqual(first, second)
        XCTAssertTrue((0..<100).contains(first))
    }
}
