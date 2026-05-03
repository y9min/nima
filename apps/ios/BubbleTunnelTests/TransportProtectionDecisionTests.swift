import XCTest
@testable import BubbleTunnel

final class TransportProtectionDecisionTests: XCTestCase {
    func testBadLenStormAloneDoesNotTrip() {
        let shouldTrip = SOCKSProxyServer.shouldTripFromSevereSignals(
            severeSaturation: false,
            severeTimeoutStorm: false,
            severeBadLenStorm: true,
            severeReclaims: false
        )
        XCTAssertFalse(shouldTrip)
    }

    func testBadLenAndTimeoutStormTrip() {
        let shouldTrip = SOCKSProxyServer.shouldTripFromSevereSignals(
            severeSaturation: false,
            severeTimeoutStorm: true,
            severeBadLenStorm: true,
            severeReclaims: false
        )
        XCTAssertTrue(shouldTrip)
    }

    func testEmergencyReclaimsNeedAdditionalStressSignal() {
        let shouldTripOnlyReclaims = SOCKSProxyServer.shouldTripFromSevereSignals(
            severeSaturation: false,
            severeTimeoutStorm: false,
            severeBadLenStorm: false,
            severeReclaims: true
        )
        XCTAssertFalse(shouldTripOnlyReclaims)

        let shouldTripWithStress = SOCKSProxyServer.shouldTripFromSevereSignals(
            severeSaturation: true,
            severeTimeoutStorm: false,
            severeBadLenStorm: false,
            severeReclaims: true
        )
        XCTAssertTrue(shouldTripWithStress)
    }

    func testLifecycleUnknownStopCanInferCrashFromStaleHeartbeat() {
        let shouldInfer = SOCKSProxyServer.shouldInferCrashFromLifecycle(
            stopSource: "unknown",
            runningMarker: true,
            heartbeatAgeSeconds: 12,
            staleThresholdSeconds: 8
        )
        XCTAssertTrue(shouldInfer)
    }

    func testLifecycleKnownStopDoesNotInferCrash() {
        let shouldInfer = SOCKSProxyServer.shouldInferCrashFromLifecycle(
            stopSource: "stopTunnel",
            runningMarker: true,
            heartbeatAgeSeconds: 100,
            staleThresholdSeconds: 8
        )
        XCTAssertFalse(shouldInfer)
    }

    func testStormModeEffectiveLimitReservesSlots() {
        XCTAssertEqual(
            SOCKSProxyServer.effectiveActiveLimit(baseLimit: 16, reservedSlots: 2, stormMode: true),
            14
        )
        XCTAssertEqual(
            SOCKSProxyServer.effectiveActiveLimit(baseLimit: 16, reservedSlots: 2, stormMode: false),
            16
        )
    }

    func testGlobalUDPRejectOnlyAtAbsoluteHardCap() {
        XCTAssertFalse(
            SOCKSProxyServer.shouldForceGlobalUDPReject(active: 12, queued: 3, maxActive: 12, maxQueued: 4)
        )
        XCTAssertFalse(
            SOCKSProxyServer.shouldForceGlobalUDPReject(active: 11, queued: 4, maxActive: 12, maxQueued: 4)
        )
        XCTAssertTrue(
            SOCKSProxyServer.shouldForceGlobalUDPReject(active: 12, queued: 4, maxActive: 12, maxQueued: 4)
        )
    }
}
