import XCTest

private final class StubConnectionFilter: ConnectionFilter {
    func evaluateConnection(host: String, port: UInt16) -> PolicyDecision {
        PolicyDecision.allow(
            reason: "stub_allow",
            classification: FlowClassification(bucket: .unknown, confidence: 0, reasons: ["stub"]),
            toggles: [:],
            policyVersion: 1,
            appStrategy: "stub",
            trafficClass: .generic
        )
    }

    func evaluateUDP(host: String, port: UInt16, payloadBytes: Int) -> PolicyDecision {
        evaluateConnection(host: host, port: port)
    }

    func evaluateStream(host: String, sni: String?, port: UInt16, bytesDown: Int, connectionAge: TimeInterval, parallelConnections: Int) -> PolicyDecision {
        evaluateConnection(host: sni ?? host, port: port)
    }
}

private final class TikTokDNSHintFilter: ConnectionFilter {
    func evaluateConnection(host: String, port: UInt16) -> PolicyDecision {
        allow(host: host, reason: "stub_allow")
    }

    func evaluateUDP(host: String, port: UInt16, payloadBytes: Int) -> PolicyDecision {
        evaluateStream(host: host, sni: host, port: port, bytesDown: payloadBytes, connectionAge: 0, parallelConnections: 1)
    }

    func evaluateStream(host: String, sni: String?, port: UInt16, bytesDown: Int, connectionAge: TimeInterval, parallelConnections: Int) -> PolicyDecision {
        let domain = (sni ?? host).lowercased()
        if domain.contains("tiktokcdn") || domain.contains("bytecdn") {
            return PolicyDecision(
                action: .blockNow,
                blockAfterBytes: nil,
                classification: FlowClassification(bucket: .tiktokVideo, confidence: 0.99, reasons: ["test_tiktok_dns_hint"]),
                reason: "tiktok_video_block_now",
                toggleSnapshot: ["video_block": true],
                policyVersion: 1,
                intendedAction: nil,
                appStrategy: AppTransportStrategy.hardenedVideo.rawValue,
                trafficClass: .tiktok
            )
        }
        return allow(host: domain, reason: "non_tiktok_traffic")
    }

    private func allow(host: String, reason: String) -> PolicyDecision {
        PolicyDecision.allow(
            reason: reason,
            classification: FlowClassification(bucket: .unknown, confidence: 0, reasons: [reason]),
            toggles: [:],
            policyVersion: 1,
            appStrategy: "stub",
            trafficClass: .generic
        )
    }
}

private final class InstagramDNSHintFilter: ConnectionFilter {
    func evaluateConnection(host: String, port: UInt16) -> PolicyDecision {
        allow(host: host, reason: "stub_allow")
    }

    func evaluateUDP(host: String, port: UInt16, payloadBytes: Int) -> PolicyDecision {
        evaluateStream(host: host, sni: host, port: port, bytesDown: payloadBytes, connectionAge: 0, parallelConnections: 1)
    }

    func evaluateStream(host: String, sni: String?, port: UInt16, bytesDown: Int, connectionAge: TimeInterval, parallelConnections: Int) -> PolicyDecision {
        let domain = (sni ?? host).lowercased()
        if domain.contains("reels-video") || domain.contains("fbvideo.net") {
            return PolicyDecision(
                action: .blockNow,
                blockAfterBytes: nil,
                classification: FlowClassification(bucket: .reels, confidence: 0.99, reasons: ["test_instagram_reels_dns_hint"]),
                reason: "reels_media_block_now",
                toggleSnapshot: ["reels": true],
                policyVersion: 1,
                intendedAction: nil,
                appStrategy: AppTransportStrategy.legacyReels.rawValue,
                trafficClass: .instagram
            )
        }
        return allow(host: domain, reason: "unknown_meta_default_allow")
    }

    private func allow(host: String, reason: String) -> PolicyDecision {
        PolicyDecision.allow(
            reason: reason,
            classification: FlowClassification(bucket: .unknown, confidence: 0, reasons: [reason]),
            toggles: [:],
            policyVersion: 1,
            appStrategy: "stub",
            trafficClass: .generic
        )
    }
}

private final class CountingUDPFilter: ConnectionFilter {
    private(set) var udpEvaluations = 0
    private(set) var streamEvaluations = 0

    func evaluateConnection(host: String, port: UInt16) -> PolicyDecision {
        PolicyDecision.allow(
            reason: "counting_allow",
            classification: FlowClassification(bucket: .unknown, confidence: 0, reasons: ["counting"]),
            toggles: [:],
            policyVersion: 1,
            appStrategy: "stub",
            trafficClass: .generic
        )
    }

    func evaluateUDP(host: String, port: UInt16, payloadBytes: Int) -> PolicyDecision {
        udpEvaluations += 1
        return evaluateConnection(host: host, port: port)
    }

    func evaluateStream(host: String, sni: String?, port: UInt16, bytesDown: Int, connectionAge: TimeInterval, parallelConnections: Int) -> PolicyDecision {
        streamEvaluations += 1
        return evaluateConnection(host: sni ?? host, port: port)
    }
}

final class TransportProtectionDecisionTests: XCTestCase {
    private func protectedTikTokVideoDecision() -> PolicyDecision {
        PolicyDecision(
            action: .blockNow,
            blockAfterBytes: nil,
            classification: FlowClassification(bucket: .tiktokVideo, confidence: 0.99, reasons: ["tiktok_video_domain"]),
            reason: "tiktok_video_block_now",
            toggleSnapshot: ["video_block": true],
            policyVersion: 1,
            intendedAction: nil,
            appStrategy: AppTransportStrategy.hardenedVideo.rawValue,
            trafficClass: .tiktok
        )
    }

    private func genericBlockDecision() -> PolicyDecision {
        PolicyDecision(
            action: .blockNow,
            blockAfterBytes: nil,
            classification: FlowClassification(bucket: .unknown, confidence: 0.10, reasons: ["generic_test"]),
            reason: "generic_test_block",
            toggleSnapshot: [:],
            policyVersion: 1,
            intendedAction: nil,
            appStrategy: AppTransportStrategy.legacyReels.rawValue,
            trafficClass: .generic
        )
    }

    private func lowConfidenceBlockDecision() -> PolicyDecision {
        PolicyDecision(
            action: .blockNow,
            blockAfterBytes: nil,
            classification: FlowClassification(bucket: .unknown, confidence: 0.10, reasons: ["low_confidence_test"]),
            reason: "low_confidence_test_block",
            toggleSnapshot: [:],
            policyVersion: 1,
            intendedAction: nil,
            appStrategy: AppTransportStrategy.legacyReels.rawValue,
            trafficClass: .unknown
        )
    }

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

    func testExtensionPressureClassificationUsesEarlyUDPThresholds() {
        XCTAssertEqual(
            SOCKSProxyServer.extensionPressureLevel(memoryMB: 10, activeUDP: 16, queuedUDP: 0, degradedState: "healthy"),
            .hard
        )
        XCTAssertEqual(
            SOCKSProxyServer.extensionPressureLevel(memoryMB: 10, activeUDP: 0, queuedUDP: 8, degradedState: "healthy"),
            .hard
        )
        XCTAssertEqual(
            SOCKSProxyServer.extensionPressureLevel(memoryMB: 10, activeUDP: 20, queuedUDP: 0, degradedState: "healthy"),
            .critical
        )
        XCTAssertEqual(
            SOCKSProxyServer.extensionPressureLevel(memoryMB: 10, activeUDP: 0, queuedUDP: 12, degradedState: "healthy"),
            .critical
        )
    }

    func testStormModeRequiresAtLeastTwoSignals() {
        XCTAssertFalse(
            SOCKSProxyServer.shouldEnterStormMode(
                recentUDPCreateCount: 25,
                timeoutRate: 0.10,
                reclaimBlockedDelta: 0,
                consecutiveQueuePressureSamples: 1
            )
        )
        XCTAssertTrue(
            SOCKSProxyServer.shouldEnterStormMode(
                recentUDPCreateCount: 25,
                timeoutRate: 0.30,
                reclaimBlockedDelta: 0,
                consecutiveQueuePressureSamples: 1
            )
        )
        XCTAssertTrue(
            SOCKSProxyServer.shouldEnterStormMode(
                recentUDPCreateCount: 10,
                timeoutRate: 0.30,
                reclaimBlockedDelta: 1,
                consecutiveQueuePressureSamples: 1
            )
        )
    }

    func testStormModeExitRequiresSustainedRecovery() {
        XCTAssertFalse(
            SOCKSProxyServer.shouldExitStormMode(
                activeUDP: 9,
                queuedUDP: 3,
                timeoutRate: 0.09,
                stableSeconds: 10
            )
        )
        XCTAssertTrue(
            SOCKSProxyServer.shouldExitStormMode(
                activeUDP: 9,
                queuedUDP: 3,
                timeoutRate: 0.09,
                stableSeconds: 15
            )
        )
    }

    func testUnknownEarlyClassificationStaysUnknownAdmissionLane() {
        let classified = ClassifiedFlow(trafficClass: .unknown, confidence: 0.20, reason: "no_signal")

        XCTAssertEqual(SOCKSProxyServer.admissionTrafficClass(for: classified), .unknown)
    }

    func testGenericEarlyClassificationStaysGenericAdmissionLane() {
        let classified = ClassifiedFlow(trafficClass: .generic, confidence: 0.95, reason: "control_or_dns")

        XCTAssertEqual(SOCKSProxyServer.admissionTrafficClass(for: classified), .generic)
    }

    func testStabilityFirstDefaultsOnWhenStoredValueMissing() {
        XCTAssertTrue(SOCKSProxyServer.resolveStabilityFirstMode(storedValue: nil))
        XCTAssertTrue(SOCKSProxyServer.resolveStabilityFirstMode(storedValue: true))
        XCTAssertFalse(SOCKSProxyServer.resolveStabilityFirstMode(storedValue: false))
    }

    func testSelectiveUDPSafeModeDefaultsOnWhenNoStoredValuesExist() {
        XCTAssertEqual(
            SOCKSProxyServer.resolveUDPForwardingMode(selectiveSafeModeValue: nil, legacyDisabledValue: nil),
            .selectiveSafeMode
        )
        XCTAssertTrue(
            SOCKSProxyServer.migratedUDPSelectiveSafeModeValue(existingSelectiveValue: nil, legacyDisabledValue: nil)
        )
    }

    func testLegacyExplicitUDPOffMigratesToNativeForwardingOffState() {
        XCTAssertEqual(
            SOCKSProxyServer.resolveUDPForwardingMode(selectiveSafeModeValue: nil, legacyDisabledValue: false),
            .nativeForwarding
        )
        XCTAssertFalse(
            SOCKSProxyServer.migratedUDPSelectiveSafeModeValue(existingSelectiveValue: nil, legacyDisabledValue: false)
        )
    }

    func testExplicitSelectiveUDPOffCanUseDiagnosticFastRejectFallback() {
        XCTAssertEqual(
            SOCKSProxyServer.resolveUDPForwardingMode(selectiveSafeModeValue: false, legacyDisabledValue: false),
            .nativeForwarding
        )
        XCTAssertEqual(
            SOCKSProxyServer.resolveUDPForwardingMode(selectiveSafeModeValue: false, legacyDisabledValue: true),
            .nativeForwarding
        )
        XCTAssertEqual(
            SOCKSProxyServer.resolveUDPForwardingMode(
                selectiveSafeModeValue: false,
                legacyDisabledValue: true,
                diagnosticFastRejectValue: true
            ),
            .disabledFastReject
        )
        XCTAssertFalse(
            SOCKSProxyServer.migratedUDPSelectiveSafeModeValue(existingSelectiveValue: false, legacyDisabledValue: true)
        )
    }

    func testDiagnosticFastRejectWinsOverOtherUDPModes() {
        XCTAssertEqual(
            SOCKSProxyServer.resolveUDPForwardingMode(
                selectiveSafeModeValue: true,
                legacyDisabledValue: false,
                diagnosticFastRejectValue: true
            ),
            .disabledFastReject
        )
    }

    func testSelectiveSafeModeRoutesOnlyDNSIntoFastLane() {
        XCTAssertEqual(SOCKSProxyServer.selectiveSafeModeUDPDecision(destinationPort: 53), .dnsFastLane)
        XCTAssertEqual(
            SOCKSProxyServer.selectiveSafeModeUDPDecision(destinationPort: 443),
            .reject(reason: "udp_quic_rejected_safe_mode")
        )
        XCTAssertEqual(
            SOCKSProxyServer.selectiveSafeModeUDPDecision(destinationPort: 123),
            .reject(reason: "udp_non_dns_rejected_safe_mode")
        )
        XCTAssertTrue(SOCKSProxyServer.shouldUseDNSFastLane(mode: .selectiveSafeMode, destinationPort: 53))
        XCTAssertFalse(SOCKSProxyServer.shouldUseGenericUDPRelay(mode: .selectiveSafeMode, destinationPort: 53))
        XCTAssertFalse(SOCKSProxyServer.shouldUseGenericUDPRelay(mode: .selectiveSafeMode, destinationPort: 443))
        XCTAssertTrue(SOCKSProxyServer.shouldUseGenericUDPRelay(mode: .nativeForwarding, destinationPort: 443))
        XCTAssertFalse(SOCKSProxyServer.shouldUseGenericUDPRelay(mode: .disabledFastReject, destinationPort: 53))
    }

    func testDNSFastLanePayloadValidationRejectsMalformedDNS() {
        XCTAssertFalse(SOCKSProxyServer.isValidDNSFastLanePayload(Data(repeating: 0, count: 11)))
        XCTAssertTrue(SOCKSProxyServer.isValidDNSFastLanePayload(Data(repeating: 0, count: 12)))
    }

    func testTun2SocksStartupModeDefaultsToStagedAfterConnect() {
        XCTAssertEqual(Tun2SocksStartupMode.resolve(rawValue: nil), .stagedAfterConnect)
        XCTAssertEqual(Tun2SocksStartupMode.resolve(rawValue: "unknown"), .stagedAfterConnect)
    }

    func testBypassStartupModeDoesNotLaunchTun2Socks() {
        XCTAssertFalse(
            TunnelStartupPlanner.shouldLaunchTun2Socks(mode: .bypassTun2SocksDiagnostic)
        )
        XCTAssertFalse(
            TunnelStartupPlanner.phaseOrder(for: .bypassTun2SocksDiagnostic)
                .contains("tun2socks_launch_scheduled")
        )
        XCTAssertFalse(
            TunnelStartupPlanner.phaseOrder(for: .bypassTun2SocksDiagnostic)
                .contains("tun2socks_run_dispatching")
        )
    }

    func testStagedStartupCallsCompletionBeforeDiagnosticsAndTransportLaunch() throws {
        let phases = TunnelStartupPlanner.phaseOrder(for: .stagedAfterConnect)
        let completionIndex = try XCTUnwrap(phases.firstIndex(of: "vpn_completion_called"))
        let diagnosticsIndex = try XCTUnwrap(phases.firstIndex(of: "post_completion_diagnostics_start"))
        let startupProbeIndex = try XCTUnwrap(phases.firstIndex(of: "startup_probe_completed"))
        let scheduledIndex = try XCTUnwrap(phases.firstIndex(of: "tun2socks_launch_scheduled"))
        let launchIndex = try XCTUnwrap(phases.firstIndex(of: "tun2socks_run_dispatching"))

        XCTAssertLessThan(completionIndex, diagnosticsIndex)
        XCTAssertLessThan(completionIndex, startupProbeIndex)
        XCTAssertLessThan(completionIndex, scheduledIndex)
        XCTAssertLessThan(completionIndex, launchIndex)
    }

    func testSOCKSProductionSnapshotsAreSafeFromInternalQueue() {
        let server = SOCKSProxyServer(filter: StubConnectionFilter())

        XCTAssertTrue(server.testProductionSnapshotAccessFromInternalQueue())
    }

    func testSOCKSStopIsSafeFromInternalQueue() {
        let server = SOCKSProxyServer(filter: StubConnectionFilter())

        XCTAssertTrue(server.testStopFromInternalQueueCompletes())
    }

    func testStartupGraceRaisesUnknownUDPAdmissionLimits() {
        let limits = SOCKSProxyServer.startupGraceAdjustedUDPLimits(
            trafficClass: .unknown,
            maxActive: 4,
            maxQueued: 4,
            globalMaxActive: 24,
            globalMaxQueued: 16,
            graceActive: true
        )

        XCTAssertGreaterThanOrEqual(limits.maxActive, 12)
        XCTAssertGreaterThanOrEqual(limits.maxQueued, 8)
        XCTAssertGreaterThanOrEqual(
            SOCKSProxyServer.startupGraceAdjustedUDPCreateRateCapacity(
                trafficClass: .unknown,
                createRateCapacity: 6,
                globalCreateRateCapacity: 24,
                graceActive: true
            ),
            12
        )
    }

    func testStartupGraceDoesNotRaiseTikTokUDPAdmissionLimits() {
        let limits = SOCKSProxyServer.startupGraceAdjustedUDPLimits(
            trafficClass: .tiktok,
            maxActive: 4,
            maxQueued: 4,
            globalMaxActive: 24,
            globalMaxQueued: 16,
            graceActive: true
        )

        XCTAssertEqual(limits.maxActive, 4)
        XCTAssertEqual(limits.maxQueued, 4)
    }

    func testSafeModeClampsStartupGraceUDPAdmissionLimits() {
        let limits = SOCKSProxyServer.startupGraceAdjustedUDPLimits(
            trafficClass: .unknown,
            maxActive: 12,
            maxQueued: 8,
            globalMaxActive: 24,
            globalMaxQueued: 16,
            graceActive: true,
            safeMode: true
        )

        XCTAssertEqual(limits.maxActive, BubbleConstants.safeModeMaxActiveUDPControlStreams)
        XCTAssertEqual(limits.maxQueued, BubbleConstants.safeModeMaxQueuedUDPControlStreams)
        XCTAssertEqual(
            SOCKSProxyServer.startupGraceAdjustedUDPCreateRateCapacity(
                trafficClass: .unknown,
                createRateCapacity: 24,
                globalCreateRateCapacity: 24,
                graceActive: true,
                safeMode: true
            ),
            BubbleConstants.safeModeUDPAdmissionCreateRateCapacity
        )
    }

    func testSafeModeEffectiveMaxIgnoresStormBoostedGlobalLimit() {
        XCTAssertEqual(
            SOCKSProxyServer.effectiveMaxActiveUDPStreams(stormMode: false, safeMode: true),
            BubbleConstants.safeModeMaxActiveUDPControlStreams
        )
        XCTAssertEqual(
            SOCKSProxyServer.effectiveMaxActiveUDPStreams(stormMode: true, safeMode: true),
            BubbleConstants.safeModeMaxActiveUDPControlStreams
        )
    }

    func testDNSOneShotClosesAfterResponseEvenWithQueuedTrailingFrames() {
        XCTAssertTrue(SOCKSProxyServer.shouldCloseDNSOneShot(lastPort: 53, pendingFrameCount: 0, processingFrame: false))
        XCTAssertTrue(SOCKSProxyServer.shouldCloseDNSOneShot(lastPort: 53, pendingFrameCount: 1, processingFrame: false))
        XCTAssertFalse(SOCKSProxyServer.shouldCloseDNSOneShot(lastPort: 53, pendingFrameCount: 0, processingFrame: true))
        XCTAssertFalse(SOCKSProxyServer.shouldCloseDNSOneShot(lastPort: 443, pendingFrameCount: 0, processingFrame: false))
    }

    func testDNSResponseCloseDoesNotBypassStartupGraceDuringGuards() {
        XCTAssertTrue(SOCKSProxyServer.shouldBypassGraceForDNSClose(lastPort: 53, reason: "dns_response_one_shot_retire"))
        XCTAssertFalse(
            SOCKSProxyServer.shouldBypassGraceForDNSClose(
                lastPort: 53,
                reason: "dns_response_one_shot_retire",
                startupGuardActive: true
            )
        )
        XCTAssertFalse(
            SOCKSProxyServer.shouldBypassGraceForDNSClose(
                lastPort: 53,
                reason: "dns_response_one_shot_retire",
                crashGuardActive: true
            )
        )
        XCTAssertTrue(SOCKSProxyServer.shouldBypassGraceForDNSClose(lastPort: 53, reason: "dns_timeout_one_shot_retire"))
        XCTAssertTrue(SOCKSProxyServer.shouldBypassGraceForDNSClose(lastPort: 53, reason: "dns_malformed_one_shot_retire"))
        XCTAssertTrue(SOCKSProxyServer.shouldBypassGraceForDNSClose(lastPort: 53, reason: "control_stream_completed"))
        XCTAssertFalse(SOCKSProxyServer.shouldBypassGraceForDNSClose(lastPort: 443, reason: "dns_response_one_shot_retire"))
        XCTAssertFalse(SOCKSProxyServer.shouldBypassGraceForDNSClose(lastPort: 53, reason: "global_idle_timeout_reclaim"))
    }

    func testDNSStartupDrainOnlyRunsDuringStartupProtection() {
        XCTAssertTrue(
            SOCKSProxyServer.shouldUseDNSStartupDrain(
                stabilityFirstModeEnabled: true,
                startupDrainWindowActive: true,
                startupGraceActive: true,
                startupGuardActive: false,
                crashGuardActive: false,
                lastPort: 53,
                reason: "dns_response_one_shot_retire"
            )
        )
        XCTAssertTrue(
            SOCKSProxyServer.shouldUseDNSStartupDrain(
                stabilityFirstModeEnabled: true,
                startupDrainWindowActive: true,
                startupGraceActive: false,
                startupGuardActive: true,
                crashGuardActive: false,
                lastPort: 53,
                reason: "dns_response_one_shot_retire"
            )
        )
        XCTAssertFalse(
            SOCKSProxyServer.shouldUseDNSStartupDrain(
                stabilityFirstModeEnabled: true,
                startupDrainWindowActive: false,
                startupGraceActive: true,
                startupGuardActive: true,
                crashGuardActive: true,
                lastPort: 53,
                reason: "dns_response_one_shot_retire"
            )
        )
        XCTAssertFalse(
            SOCKSProxyServer.shouldUseDNSStartupDrain(
                stabilityFirstModeEnabled: true,
                startupDrainWindowActive: true,
                startupGraceActive: true,
                startupGuardActive: true,
                crashGuardActive: true,
                lastPort: 443,
                reason: "dns_response_one_shot_retire"
            )
        )
        XCTAssertFalse(
            SOCKSProxyServer.shouldUseDNSStartupDrain(
                stabilityFirstModeEnabled: true,
                startupDrainWindowActive: true,
                startupGraceActive: true,
                startupGuardActive: true,
                crashGuardActive: true,
                lastPort: 53,
                reason: "dns_response_one_shot_retire",
                dnsFastLane: true
            )
        )
    }

    func testStartupGuardSaturationAllowsLowConfidenceNonDNSReclaimDuringGrace() {
        XCTAssertTrue(
            SOCKSProxyServer.shouldBypassGraceForStartupGuardLowConfidenceReclaim(
                reason: "global_idle_timeout_reclaim",
                startupGuardActive: true,
                queueDepth: BubbleConstants.safeModeMaxQueuedUDPControlStreams,
                trafficClass: .unknown,
                lastPort: 443,
                preservesMessagingControl: false
            )
        )
        XCTAssertTrue(
            SOCKSProxyServer.shouldBypassGraceForStartupGuardLowConfidenceReclaim(
                reason: "stuck_processing_reclaim",
                startupGuardActive: true,
                queueDepth: BubbleConstants.safeModeMaxQueuedUDPControlStreams + 1,
                trafficClass: .generic,
                lastPort: 3478,
                preservesMessagingControl: false
            )
        )
        XCTAssertFalse(
            SOCKSProxyServer.shouldBypassGraceForStartupGuardLowConfidenceReclaim(
                reason: "global_max_lifetime_reclaim",
                startupGuardActive: true,
                queueDepth: BubbleConstants.safeModeMaxQueuedUDPControlStreams - 1,
                trafficClass: .generic,
                lastPort: 443,
                preservesMessagingControl: false
            )
        )
        XCTAssertFalse(
            SOCKSProxyServer.shouldBypassGraceForStartupGuardLowConfidenceReclaim(
                reason: "global_idle_timeout_reclaim",
                startupGuardActive: true,
                queueDepth: BubbleConstants.safeModeMaxQueuedUDPControlStreams,
                trafficClass: .unknown,
                lastPort: 53,
                preservesMessagingControl: false
            )
        )
    }

    func testDNSResponseClosePlanUsesGracefulDeferredWatchdog() {
        let plan = SOCKSProxyServer.udpControlClosePlan(lastPort: 53, reason: "dns_response_one_shot_retire")

        XCTAssertEqual(plan.phase, .retiring)
        XCTAssertTrue(plan.sendWithConnectionCompletion)
        XCTAssertTrue(plan.discardTrailingFrames)
        XCTAssertTrue(plan.deferDrainUntilCancel)
        XCTAssertTrue(plan.cancelAsWatchdog)
        XCTAssertEqual(plan.cancelDelaySeconds, BubbleConstants.udpDNSResponseCancelWatchdogDelaySeconds)
    }

    func testDNSTimeoutMalformedClosePlanDiscardsAndDefersCancel() {
        let timeout = SOCKSProxyServer.udpControlClosePlan(lastPort: 53, reason: "dns_timeout_one_shot_retire")
        let malformed = SOCKSProxyServer.udpControlClosePlan(lastPort: 53, reason: "dns_malformed_one_shot_retire")

        XCTAssertTrue(timeout.discardTrailingFrames)
        XCTAssertFalse(timeout.sendWithConnectionCompletion)
        XCTAssertEqual(timeout.cancelDelaySeconds, BubbleConstants.udpDNSDeferredCancelDelaySeconds)
        XCTAssertTrue(malformed.discardTrailingFrames)
        XCTAssertEqual(malformed.cancelDelaySeconds, BubbleConstants.udpDNSDeferredCancelDelaySeconds)
    }

    func testDNSStartupDrainClosePlanDiscardsAndDefersCancel() {
        let idle = SOCKSProxyServer.udpControlClosePlan(lastPort: 53, reason: "dns_startup_drain_idle_retire")

        XCTAssertTrue(idle.discardTrailingFrames)
        XCTAssertFalse(idle.sendWithConnectionCompletion)
        XCTAssertEqual(idle.cancelDelaySeconds, BubbleConstants.udpDNSDeferredCancelDelaySeconds)
        XCTAssertTrue(idle.deferDrainUntilCancel)
        XCTAssertFalse(idle.cancelAsWatchdog)
    }

    func testNonDNSClosePlanDefersCancelAndDrainWithoutChangingRelayPolicy() {
        let plan = SOCKSProxyServer.udpControlClosePlan(lastPort: 443, reason: "global_idle_timeout_reclaim")

        XCTAssertEqual(plan.phase, .retiring)
        XCTAssertFalse(plan.sendWithConnectionCompletion)
        XCTAssertFalse(plan.discardTrailingFrames)
        XCTAssertTrue(plan.deferDrainUntilCancel)
        XCTAssertFalse(plan.cancelAsWatchdog)
        XCTAssertEqual(plan.cancelDelaySeconds, 0)
    }

    func testRecoveredDNSDiscardPlanProcessesOneAndDropsTrailingFrames() {
        let plan = SOCKSProxyServer.dnsFrameDiscardPlan(
            pendingFrameCount: 3,
            recoveredFramesPending: 2,
            processingRecoveredDNSFrame: true
        )

        XCTAssertEqual(plan.trailingDiscarded, 3)
        XCTAssertEqual(plan.recoveredDiscarded, 2)
        XCTAssertTrue(plan.recoveredOneShotClose)
    }

    func testCrashGuardActivatesForPriorStatusDropInUDPStartupPhase() {
        XCTAssertTrue(
            SOCKSProxyServer.shouldActivateUDPStartupCrashGuard(
                previousStopCause: "status_drop_without_stop_callback",
                lastProviderPhase: "dns_one_shot_close",
                lastDecoderEventJSON: ""
            )
        )
        XCTAssertEqual(
            SOCKSProxyServer.udpStartupCrashGuardReason(
                previousStopCause: "status_drop_without_stop_callback",
                lastProviderPhase: "dns_one_shot_close",
                lastDecoderEventJSON: ""
            ),
            "prior_dns_udp_close_falloff"
        )
        XCTAssertTrue(
            SOCKSProxyServer.shouldActivateUDPStartupCrashGuard(
                previousStopCause: "status_drop_without_stop_callback",
                lastProviderPhase: "dns_fast_lane_response_sent",
                lastDecoderEventJSON: ""
            )
        )
        XCTAssertEqual(
            SOCKSProxyServer.udpStartupCrashGuardReason(
                previousStopCause: "status_drop_without_stop_callback",
                lastProviderPhase: "dns_fast_lane_close",
                lastDecoderEventJSON: ""
            ),
            "prior_dns_udp_close_falloff"
        )
        XCTAssertFalse(
            SOCKSProxyServer.shouldActivateUDPStartupCrashGuard(
                previousStopCause: "app_requested_stop",
                lastProviderPhase: "dns_one_shot_close",
                lastDecoderEventJSON: ""
            )
        )
    }

    func testStartupGuardEscapeHatchSkipsProtectedTraffic() {
        XCTAssertFalse(
            SOCKSProxyServer.shouldTriggerUDPStartupGuardEscapeHatch(
                startupGuardActive: true,
                activeUDPStreams: 1,
                queueDepth: BubbleConstants.safeModeMaxQueuedUDPControlStreams,
                trafficClass: .unknown,
                lastPort: 443,
                preservesMessagingControl: false
            )
        )
        XCTAssertTrue(
            SOCKSProxyServer.shouldTriggerUDPStartupGuardEscapeHatch(
                startupGuardActive: true,
                activeUDPStreams: BubbleConstants.udpStartupSerialMaxActiveStreams,
                queueDepth: BubbleConstants.safeModeMaxQueuedUDPControlStreams,
                trafficClass: .unknown,
                lastPort: 443,
                preservesMessagingControl: false
            )
        )
        XCTAssertFalse(
            SOCKSProxyServer.shouldTriggerUDPStartupGuardEscapeHatch(
                startupGuardActive: true,
                activeUDPStreams: 1,
                queueDepth: BubbleConstants.safeModeMaxQueuedUDPControlStreams,
                trafficClass: .tiktok,
                lastPort: 443,
                preservesMessagingControl: false
            )
        )
        XCTAssertFalse(
            SOCKSProxyServer.shouldTriggerUDPStartupGuardEscapeHatch(
                startupGuardActive: true,
                activeUDPStreams: 1,
                queueDepth: BubbleConstants.safeModeMaxQueuedUDPControlStreams,
                trafficClass: .instagram,
                lastPort: 443,
                preservesMessagingControl: false
            )
        )
    }

    func testStartupGuardDrainLimitReturnsToNormalSafeModeAfterExpiry() {
        XCTAssertEqual(
            SOCKSProxyServer.drainActiveLimitDuringStartupGuard(
                startupGuardActive: true,
                stormMode: false,
                safeMode: true
            ),
            BubbleConstants.udpStartupSerialMaxActiveStreams
        )
        XCTAssertEqual(
            SOCKSProxyServer.drainActiveLimitDuringStartupGuard(
                startupGuardActive: false,
                stormMode: false,
                safeMode: true
            ),
            BubbleConstants.safeModeMaxActiveUDPControlStreams
        )
    }

    func testHardPressurePrioritizesDNSAsReclaimableLowConfidenceTraffic() {
        let dnsPriority = SOCKSProxyServer.reclaimPriority(
            criticalPressure: false,
            degradedOrCriticalPressure: true,
            hardeningEnabled: false,
            hardeningBucket: nil,
            trafficClass: .generic,
            preservesMessagingControl: true,
            lastPort: 53
        )
        let protectedPriority = SOCKSProxyServer.reclaimPriority(
            criticalPressure: false,
            degradedOrCriticalPressure: true,
            hardeningEnabled: false,
            hardeningBucket: nil,
            trafficClass: .tiktok,
            preservesMessagingControl: false,
            lastPort: 443
        )

        XCTAssertLessThan(dnsPriority, protectedPriority)
    }

    func testHardPressureBatchReclaimsDownTowardSafeActiveTarget() {
        XCTAssertEqual(
            SOCKSProxyServer.pressureReclaimBatchSize(activeUDP: 18, candidateCount: 10, pressureLevel: .hard, stormMode: false),
            8
        )
        XCTAssertEqual(
            SOCKSProxyServer.pressureReclaimBatchSize(activeUDP: 18, candidateCount: 3, pressureLevel: .hard, stormMode: false),
            3
        )
    }

    func testDNSResponseCreatesTikTokHintAndBlocksMatchingUDP443() {
        let response = Self.dnsResponse(
            question: "v16.tiktokcdn-us.com",
            answerNamePointerToQuestion: true,
            ttl: 30,
            ip: [203, 0, 113, 44]
        )
        let server = SOCKSProxyServer(filter: TikTokDNSHintFilter())

        server.testRecordTikTokDNSHints(response: response)
        let hints = SOCKSProxyServer.testParseDNSAddressAnswers(response)
        let decision = server.testEvaluateUDPPolicy(host: "203.0.113.44", port: 443)
        let counters = server.testDNSHintCounterSnapshot()

        XCTAssertEqual(hints.first?.domain, "v16.tiktokcdn-us.com")
        XCTAssertEqual(hints.first?.ip, "203.0.113.44")
        XCTAssertEqual(decision.action, "block_now")
        XCTAssertEqual(decision.reason, "tiktok_video_block_now")
        XCTAssertEqual(decision.source, "dns_hint")
        XCTAssertEqual(counters.added, 1)
        XCTAssertEqual(counters.active, 1)
        XCTAssertEqual(counters.udpBlocks, 1)
    }

    func testSelectiveUDPPolicyAllowsDNSAndUnknownUDP() {
        let server = SOCKSProxyServer(filter: TikTokDNSHintFilter())

        let dnsDecision = server.testEvaluateUDPPolicy(host: "8.8.8.8", port: 53, selectiveSafeMode: true)
        let unknownDecision = server.testEvaluateUDPPolicy(host: "198.51.100.10", port: 443, selectiveSafeMode: true)

        XCTAssertEqual(dnsDecision.action, "allow")
        XCTAssertNil(dnsDecision.source)
        XCTAssertEqual(unknownDecision.action, "allow")
        XCTAssertNil(unknownDecision.source)
    }

    func testSelectiveUDPPolicyBlocksDirectTikTokVideoHostAndCachesIt() {
        let server = SOCKSProxyServer(filter: TikTokDNSHintFilter())

        let firstDecision = server.testEvaluateUDPPolicy(
            host: "v16.tiktokcdn-us.com",
            port: 443,
            selectiveSafeMode: true
        )
        let secondDecision = server.testEvaluateUDPPolicy(
            host: "v16.tiktokcdn-us.com",
            port: 443,
            selectiveSafeMode: true
        )

        XCTAssertEqual(firstDecision.action, "block_now")
        XCTAssertEqual(firstDecision.reason, "tiktok_video_block_now")
        XCTAssertEqual(firstDecision.source, "direct_host")
        XCTAssertEqual(secondDecision.action, "block_now")
        XCTAssertEqual(secondDecision.source, "known_bad_cache")
        XCTAssertTrue(secondDecision.knownBadCacheHit)
        XCTAssertEqual(server.testKnownBadUDPCacheHitCount(), 1)
    }

    func testKnownBadUDPCacheBypassesPolicyEvaluation() {
        let filter = CountingUDPFilter()
        let server = SOCKSProxyServer(filter: filter)
        let decision = protectedTikTokVideoDecision()

        server.testSeedKnownBadUDPCache(
            host: "203.0.113.77",
            port: 443,
            decision: decision,
            expiresAt: Date().addingTimeInterval(30)
        )
        let cachedDecision = server.testEvaluateUDPPolicy(
            host: "203.0.113.77",
            port: 443,
            selectiveSafeMode: true
        )

        XCTAssertEqual(cachedDecision.action, "block_now")
        XCTAssertEqual(cachedDecision.source, "known_bad_cache")
        XCTAssertEqual(filter.udpEvaluations, 0)
        XCTAssertEqual(filter.streamEvaluations, 0)
    }

    func testDNSResponseCreatesInstagramReelsHintAndBlocksMatchingUDP443() {
        let response = Self.dnsResponse(
            question: "reels-video-lhr8-1.cdninstagram.com",
            answerNamePointerToQuestion: true,
            ttl: 30,
            ip: [203, 0, 113, 55]
        )
        let server = SOCKSProxyServer(filter: InstagramDNSHintFilter())

        server.testRecordInstagramDNSHints(response: response)
        let decision = server.testEvaluateUDPPolicy(host: "203.0.113.55", port: 443)
        let counters = server.testDNSHintCounterSnapshot()

        XCTAssertEqual(decision.action, "block_now")
        XCTAssertEqual(decision.reason, "reels_media_block_now")
        XCTAssertEqual(decision.source, "dns_hint")
        XCTAssertEqual(counters.instagramAdded, 1)
        XCTAssertEqual(counters.instagramActive, 1)
        XCTAssertEqual(counters.instagramUDPBlocks, 1)
        XCTAssertEqual(counters.added, 0)
    }

    func testUnknownInstagramCDNAnswerDoesNotCreateHint() {
        let response = Self.dnsResponse(
            question: "scontent-lhr8-1.cdninstagram.com",
            answerNamePointerToQuestion: true,
            ttl: 30,
            ip: [203, 0, 113, 56]
        )
        let server = SOCKSProxyServer(filter: InstagramDNSHintFilter())

        server.testRecordInstagramDNSHints(response: response)
        let decision = server.testEvaluateUDPPolicy(host: "203.0.113.56", port: 443)
        let counters = server.testDNSHintCounterSnapshot()

        XCTAssertEqual(decision.action, "allow")
        XCTAssertNil(decision.source)
        XCTAssertEqual(counters.instagramAdded, 0)
        XCTAssertEqual(counters.instagramActive, 0)
    }

    func testExpiredTikTokDNSHintDoesNotBlock() {
        let server = SOCKSProxyServer(filter: TikTokDNSHintFilter())
        server.testSeedDNSHint(
            ip: "203.0.113.44",
            domain: "v16.tiktokcdn-us.com",
            expiresAt: Date().addingTimeInterval(-1)
        )

        let decision = server.testEvaluateUDPPolicy(host: "203.0.113.44", port: 443)
        let counters = server.testDNSHintCounterSnapshot()

        XCTAssertEqual(decision.action, "allow")
        XCTAssertNil(decision.source)
        XCTAssertEqual(counters.expired, 1)
        XCTAssertEqual(counters.active, 0)
    }

    func testUnknownIPWithoutDNSHintRemainsAllowed() {
        let server = SOCKSProxyServer(filter: TikTokDNSHintFilter())

        let decision = server.testEvaluateUDPPolicy(host: "198.51.100.10", port: 443)

        XCTAssertEqual(decision.action, "allow")
        XCTAssertNil(decision.source)
    }

    func testMalformedDNSResponseDoesNotCreateHints() {
        let hints = SOCKSProxyServer.testParseDNSAddressAnswers(Data([0x12, 0x34, 0x81]))

        XCTAssertTrue(hints.isEmpty)
    }

    func testEarlySNIBlockUsesProtectionGateForRepeatedTikTokSNI() {
        let server = SOCKSProxyServer(filter: StubConnectionFilter())
        let decision = protectedTikTokVideoDecision()
        let sni = "sf16-ies-music-va.tiktokcdn.com"

        XCTAssertEqual(
            server.testRecordTCPSNIBlockForProtectionOnly(sni: sni, port: 443, decision: decision),
            "allow"
        )
        XCTAssertEqual(
            server.testRecordTCPSNIBlockForProtectionOnly(sni: sni, port: 443, decision: decision),
            "suppress"
        )

        let counters = server.testProtectionCounterSnapshot()
        XCTAssertEqual(counters.statsBlocked, 1)
        XCTAssertEqual(counters.tcpEarlySNIBlocks, 1)
        XCTAssertEqual(counters.blockedSuppressedTCP, 1)
        XCTAssertEqual(counters.tcpSNIBlockSuppressed, 1)
        XCTAssertEqual(counters.protectedBlockSuppressionKeys, 1)
    }

    private static func dnsResponse(question: String, answerNamePointerToQuestion: Bool, ttl: UInt32, ip: [UInt8]) -> Data {
        var bytes: [UInt8] = [
            0x12, 0x34,
            0x81, 0x80,
            0x00, 0x01,
            0x00, 0x01,
            0x00, 0x00,
            0x00, 0x00,
        ]
        bytes.append(contentsOf: dnsName(question))
        bytes.append(contentsOf: [0x00, 0x01, 0x00, 0x01])
        if answerNamePointerToQuestion {
            bytes.append(contentsOf: [0xC0, 0x0C])
        } else {
            bytes.append(contentsOf: dnsName(question))
        }
        bytes.append(contentsOf: [0x00, 0x01, 0x00, 0x01])
        bytes.append(UInt8((ttl >> 24) & 0xFF))
        bytes.append(UInt8((ttl >> 16) & 0xFF))
        bytes.append(UInt8((ttl >> 8) & 0xFF))
        bytes.append(UInt8(ttl & 0xFF))
        bytes.append(contentsOf: [0x00, 0x04])
        bytes.append(contentsOf: ip)
        return Data(bytes)
    }

    private static func dnsName(_ domain: String) -> [UInt8] {
        var bytes: [UInt8] = []
        for label in domain.split(separator: ".") {
            let labelBytes = Array(label.utf8)
            bytes.append(UInt8(labelBytes.count))
            bytes.append(contentsOf: labelBytes)
        }
        bytes.append(0)
        return bytes
    }

    func testEarlySNIBlockTokenDropsDoNotIncrementVisibleBlockedCount() {
        let server = SOCKSProxyServer(filter: StubConnectionFilter())
        let decision = protectedTikTokVideoDecision()
        let sni = "v16.tiktokcdn-us.com"

        XCTAssertEqual(server.testRecordTCPSNIBlockForProtectionOnly(sni: sni, port: 443, decision: decision), "allow")
        XCTAssertEqual(server.testRecordTCPSNIBlockForProtectionOnly(sni: sni, port: 443, decision: decision), "suppress")
        XCTAssertEqual(server.testRecordTCPSNIBlockForProtectionOnly(sni: sni, port: 443, decision: decision), "drop_fast")

        let counters = server.testProtectionCounterSnapshot()
        XCTAssertEqual(counters.statsBlocked, 1)
        XCTAssertEqual(counters.tcpEarlySNIBlocks, 1)
        XCTAssertEqual(counters.blockedSuppressedTCP, 2)
        XCTAssertEqual(counters.tcpSNIBlockSuppressed, 2)
        XCTAssertEqual(counters.tcpSNIBlockTokenDrops, 1)
    }

    func testGenericTrafficIsNotSuppressedByProtectedRetryStormLogic() {
        let server = SOCKSProxyServer(filter: StubConnectionFilter())
        let decision = genericBlockDecision()

        XCTAssertEqual(server.testRecordTCPSNIBlockForProtectionOnly(sni: "news.example.com", port: 443, decision: decision), "allow")
        XCTAssertEqual(server.testRecordTCPSNIBlockForProtectionOnly(sni: "news.example.com", port: 443, decision: decision), "allow")

        let counters = server.testProtectionCounterSnapshot()
        XCTAssertEqual(counters.statsBlocked, 2)
        XCTAssertEqual(counters.blockedSuppressedTCP, 0)
        XCTAssertEqual(counters.tcpSNIBlockSuppressed, 0)
        XCTAssertEqual(counters.protectedBlockSuppressionKeys, 0)
    }

    func testProtectedFailOpenOnlyAppliesToLowConfidenceBlocks() {
        let server = SOCKSProxyServer(filter: StubConnectionFilter())
        let decision = lowConfidenceBlockDecision()

        for _ in 0..<(BubbleConstants.protectedBlockFailOpenTriggerCount - 1) {
            XCTAssertEqual(
                server.testRecordTCPSNIBlockForProtectionOnly(sni: "unknown.example.com", port: 443, decision: decision),
                "allow"
            )
        }

        XCTAssertEqual(
            server.testRecordTCPSNIBlockForProtectionOnly(sni: "unknown.example.com", port: 443, decision: decision),
            "fail_open"
        )
    }

    func testKnownVideoBlocksDoNotUseProtectedFailOpen() {
        let server = SOCKSProxyServer(filter: StubConnectionFilter())
        let decision = protectedTikTokVideoDecision()
        var results: [String] = []

        for _ in 0..<BubbleConstants.protectedBlockFailOpenTriggerCount {
            results.append(server.testRecordTCPSNIBlockForProtectionOnly(sni: "v16.tiktokcdn-us.com", port: 443, decision: decision))
        }

        XCTAssertFalse(results.contains("fail_open"))
    }

    func testLowConfidenceTargetFallsToUnknownNotGeneric() {
        let classified = ClassifiedFlow(trafficClass: .tiktok, confidence: 0.20, reason: "weak_hint")

        XCTAssertEqual(SOCKSProxyServer.admissionTrafficClass(for: classified), .unknown)
    }

    func testStopAttributionWindowDelaysFinalization() {
        let snapshot = TunnelLifecycleDiagnostics.StopAttributionSnapshot(
            eventStart: 100,
            appRequestedTS: 0,
            osStopTS: 0,
            osStopRaw: "",
            osStopName: "",
            tun2socksExitTS: 0,
            tun2socksExitCode: nil,
            providerDeinitTS: 0,
            statusDropTS: 100.2
        )
        let decision = TunnelLifecycleDiagnostics.resolveStopAttribution(
            snapshot: snapshot,
            nowTS: 101,
            windowSeconds: 1.5
        )
        XCTAssertNil(decision)
    }

    func testStopAttributionPrefersFreshAppIntentOverOSReason() throws {
        let snapshot = TunnelLifecycleDiagnostics.StopAttributionSnapshot(
            eventStart: 100,
            appRequestedTS: 100.05,
            osStopTS: 100.10,
            osStopRaw: "provider_reason_1",
            osStopName: "userInitiated",
            tun2socksExitTS: 0,
            tun2socksExitCode: nil,
            providerDeinitTS: 0,
            statusDropTS: 100.02
        )
        let decision = try XCTUnwrap(
            TunnelLifecycleDiagnostics.resolveStopAttribution(
                snapshot: snapshot,
                nowTS: 101.6,
                windowSeconds: 1.5
            )
        )
        XCTAssertEqual(decision.final, "app_requested_stop")
        XCTAssertEqual(decision.confidence, "high")
    }

    func testStopAttributionStaleAppIntentDoesNotWin() throws {
        let snapshot = TunnelLifecycleDiagnostics.StopAttributionSnapshot(
            eventStart: 300,
            appRequestedTS: 250,
            osStopTS: 300.05,
            osStopRaw: "provider_reason_1",
            osStopName: "userInitiated",
            tun2socksExitTS: 0,
            tun2socksExitCode: nil,
            providerDeinitTS: 0,
            statusDropTS: 300.01
        )
        let decision = try XCTUnwrap(
            TunnelLifecycleDiagnostics.resolveStopAttribution(
                snapshot: snapshot,
                nowTS: 301.6,
                windowSeconds: 1.5
            )
        )
        XCTAssertEqual(decision.final, "os_stop_reason_provider_reason_1")
    }

    func testStopAttributionFallsBackToStatusDrop() throws {
        let snapshot = TunnelLifecycleDiagnostics.StopAttributionSnapshot(
            eventStart: 400,
            appRequestedTS: 0,
            osStopTS: 0,
            osStopRaw: "",
            osStopName: "",
            tun2socksExitTS: 0,
            tun2socksExitCode: nil,
            providerDeinitTS: 0,
            statusDropTS: 400.05
        )
        let decision = try XCTUnwrap(
            TunnelLifecycleDiagnostics.resolveStopAttribution(
                snapshot: snapshot,
                nowTS: 401.6,
                windowSeconds: 1.5
            )
        )
        XCTAssertEqual(decision.final, "status_drop_without_stop_callback")
        XCTAssertEqual(decision.confidence, "low")
        XCTAssertTrue(decision.evidence.contains("terminal_callback_observed=false"))
        XCTAssertTrue(decision.evidence.contains("hold_window_elapsed_ms="))
    }

    func testReconnectBreakerSuppressesSecondShortUnknownStatusDrop() {
        let decision = TunnelLifecycleDiagnostics.reconnectBreakerShortUnknownDropDecision(
            recentDropTimestamps: [1_000],
            nowTS: 1_030,
            shortLivedSession: true,
            finalCause: "status_drop_without_stop_callback"
        )

        XCTAssertTrue(decision.shouldSuppress)
        XCTAssertEqual(decision.retainedTimestamps.count, 2)
    }

    func testReconnectBreakerIgnoresHealthyOrKnownCauseDrops() {
        let healthy = TunnelLifecycleDiagnostics.reconnectBreakerShortUnknownDropDecision(
            recentDropTimestamps: [1_000],
            nowTS: 1_030,
            shortLivedSession: false,
            finalCause: "status_drop_without_stop_callback"
        )
        let known = TunnelLifecycleDiagnostics.reconnectBreakerShortUnknownDropDecision(
            recentDropTimestamps: [1_000],
            nowTS: 1_030,
            shortLivedSession: true,
            finalCause: "tun2socks_exit"
        )

        XCTAssertFalse(healthy.shouldSuppress)
        XCTAssertEqual(healthy.retainedTimestamps, [1_000])
        XCTAssertFalse(known.shouldSuppress)
        XCTAssertEqual(known.retainedTimestamps, [1_000])
    }

    func testLifecycleFalloffClassifiesDNSCloseAsIOSSafeChurn() {
        let classification = SOCKSProxyServer.classifyLifecycleFalloff(
            finalCause: "status_drop_without_stop_callback",
            providerLastPhase: "dns_one_shot_close",
            tun2socksExitObserved: false,
            lastDecoderEventJSON: ""
        )
        XCTAssertEqual(classification, "suspected_ios_watchdog_or_external_kill_after_udp_dns_churn")
    }

    func testLifecycleFalloffClassifiesFastLaneCloseAsIOSSafeChurn() {
        let classification = SOCKSProxyServer.classifyLifecycleFalloff(
            finalCause: "status_drop_without_stop_callback",
            providerLastPhase: "dns_fast_lane_close",
            tun2socksExitObserved: false,
            lastDecoderEventJSON: ""
        )
        XCTAssertEqual(classification, "suspected_ios_watchdog_or_external_kill_after_udp_dns_churn")
    }

    func testLifecycleFalloffClassifiesDecoderRecoveryAsIOSSafeChurn() {
        let classification = SOCKSProxyServer.classifyLifecycleFalloff(
            finalCause: "status_drop_without_stop_callback",
            providerLastPhase: "decoder_recovery",
            tun2socksExitObserved: false,
            lastDecoderEventJSON: "{\"reason\":\"bad_len\"}"
        )
        XCTAssertEqual(classification, "suspected_ios_watchdog_or_external_kill_after_udp_dns_churn")
    }

    func testLifecycleFalloffClassifiesHeartbeatDNSDrainPhaseAsIOSSafeChurn() {
        let classification = SOCKSProxyServer.classifyLifecycleFalloff(
            finalCause: "status_drop_without_stop_callback",
            providerLastPhase: "udp_accept",
            tun2socksExitObserved: false,
            lastDecoderEventJSON: "",
            lastHeartbeatSnapshotJSON: #"{"provider_phase":"dns_startup_drain_close","queued_udp":0,"last_udp_close_phase":"cancel_scheduled"}"#
        )
        XCTAssertEqual(classification, "suspected_ios_watchdog_or_external_kill_after_udp_dns_churn")
    }

    func testLifecycleFalloffClassifiesTun2SocksNativeExit() {
        let classification = SOCKSProxyServer.classifyLifecycleFalloff(
            finalCause: "status_drop_without_stop_callback",
            providerLastPhase: "dns_one_shot_close",
            tun2socksExitObserved: true,
            lastDecoderEventJSON: ""
        )
        XCTAssertEqual(classification, "tun2socks_native_exit")
    }

    func testLifecycleFalloffClassifiesStartupGuardSaturation() {
        let classification = SOCKSProxyServer.classifyLifecycleFalloff(
            finalCause: "status_drop_without_stop_callback",
            providerLastPhase: "udp_accept",
            tun2socksExitObserved: false,
            lastDecoderEventJSON: "",
            lastHeartbeatSnapshotJSON: """
            {"active_udp":1,"app_lifecycle":"background","last_decoder_event":{},"last_dns_close":{},"last_udp_close_phase":"grace_close_blocked","memory_mb":41,"path_state":{"status":"satisfied","unsatisfied_reason":"none"},"provider_phase":"udp_accept","queued_udp":8,"ts":1,"tun2socks_down_packets":"12","tun2socks_up_packets":"21"}
            """
        )
        XCTAssertEqual(classification, "suspected_udp_startup_guard_saturation")
    }

    func testStopAttributionEvidenceMarksTerminalCallbackObserved() throws {
        let snapshot = TunnelLifecycleDiagnostics.StopAttributionSnapshot(
            eventStart: 500,
            appRequestedTS: 0,
            osStopTS: 500.05,
            osStopRaw: "provider_reason_1",
            osStopName: "userInitiated",
            tun2socksExitTS: 0,
            tun2socksExitCode: nil,
            providerDeinitTS: 0,
            statusDropTS: 500.01
        )
        let decision = try XCTUnwrap(
            TunnelLifecycleDiagnostics.resolveStopAttribution(
                snapshot: snapshot,
                nowTS: 501.6,
                windowSeconds: 1.5
            )
        )
        XCTAssertTrue(decision.evidence.contains("terminal_callback_observed=true"))
    }

    func testExternalKillSignatureRequiresHoldTerminalGapAndCadence() {
        XCTAssertTrue(
            TunnelLifecycleDiagnostics.isExternalKillSignature(
                finalCause: "status_drop_without_stop_callback",
                evidence: "terminal_callback_observed=false;hold_window_elapsed_ms=5037",
                diagnosticHoldSeconds: 5.0,
                dropCadenceSeconds: 35.0
            )
        )
        XCTAssertFalse(
            TunnelLifecycleDiagnostics.isExternalKillSignature(
                finalCause: "status_drop_without_stop_callback",
                evidence: "terminal_callback_observed=true",
                diagnosticHoldSeconds: 5.0,
                dropCadenceSeconds: 35.0
            )
        )
        XCTAssertFalse(
            TunnelLifecycleDiagnostics.isExternalKillSignature(
                finalCause: "tun2socks_exit",
                evidence: "terminal_callback_observed=false",
                diagnosticHoldSeconds: 5.0,
                dropCadenceSeconds: 35.0
            )
        )
        XCTAssertFalse(
            TunnelLifecycleDiagnostics.isExternalKillSignature(
                finalCause: "status_drop_without_stop_callback",
                evidence: "terminal_callback_observed=false",
                diagnosticHoldSeconds: 1.5,
                dropCadenceSeconds: 35.0
            )
        )
        XCTAssertTrue(
            TunnelLifecycleDiagnostics.isExternalKillSignature(
                finalCause: "status_drop_without_stop_callback",
                evidence: "terminal_callback_observed=false",
                diagnosticHoldSeconds: 5.0,
                dropCadenceSeconds: 22.0
            )
        )
        XCTAssertFalse(
            TunnelLifecycleDiagnostics.isExternalKillSignature(
                finalCause: "status_drop_without_stop_callback",
                evidence: "terminal_callback_observed=false",
                diagnosticHoldSeconds: 5.0,
                dropCadenceSeconds: 301.0
            )
        )
    }

    func testDropCadenceUsesRecentMedianInterval() throws {
        let cadence = try XCTUnwrap(
            TunnelLifecycleDiagnostics.dropCadenceSeconds(
                from: [100, 135, 170],
                nowTS: 171,
                windowSeconds: 300
            )
        )
        XCTAssertEqual(cadence, 35, accuracy: 0.01)
        XCTAssertNil(TunnelLifecycleDiagnostics.dropCadenceSeconds(from: [100], nowTS: 101, windowSeconds: 300))
    }

    func testExternalKillReconnectGateCapsFourthRetryInWindow() {
        let gate = TunnelLifecycleDiagnostics.externalKillReconnectGate(
            attemptTimestamps: [100, 130, 160],
            nowTS: 180,
            windowSeconds: 120,
            maxAttempts: 3
        )
        XCTAssertFalse(gate.allowed)
        XCTAssertEqual(gate.attemptsInWindow, 3)
        XCTAssertEqual(gate.nextAllowedTS, 220)

        let recovered = TunnelLifecycleDiagnostics.externalKillReconnectGate(
            attemptTimestamps: [100, 130, 160],
            nowTS: 221,
            windowSeconds: 120,
            maxAttempts: 3
        )
        XCTAssertTrue(recovered.allowed)
        XCTAssertEqual(recovered.attemptsInWindow, 2)
    }

    func testExtensionPressurePolicyLevels() {
        XCTAssertEqual(
            SOCKSProxyServer.extensionPressureLevel(memoryMB: 20, activeUDP: 1, queuedUDP: 0, degradedState: "healthy"),
            .normal
        )
        XCTAssertEqual(
            SOCKSProxyServer.extensionPressureLevel(memoryMB: BubbleConstants.extensionPressureSoftMemoryMB, activeUDP: 1, queuedUDP: 0, degradedState: "healthy"),
            .soft
        )
        XCTAssertEqual(
            SOCKSProxyServer.extensionPressureLevel(memoryMB: BubbleConstants.extensionPressureHardMemoryMB, activeUDP: 1, queuedUDP: 0, degradedState: "healthy"),
            .hard
        )
        XCTAssertEqual(
            SOCKSProxyServer.extensionPressureLevel(memoryMB: BubbleConstants.extensionPressureCriticalMemoryMB, activeUDP: 1, queuedUDP: 0, degradedState: "healthy"),
            .critical
        )
        XCTAssertEqual(
            SOCKSProxyServer.extensionPressureLevel(memoryMB: nil, activeUDP: BubbleConstants.maxActiveUDPControlStreams, queuedUDP: 0, degradedState: "healthy"),
            .critical
        )
    }

    func testCriticalExtensionPressureBypassesGraceGate() {
        XCTAssertTrue(
            SOCKSProxyServer.shouldBypassGraceForExtensionPressure(reason: "extension_pressure", pressureLevel: .critical)
        )
        XCTAssertFalse(
            SOCKSProxyServer.shouldBypassGraceForExtensionPressure(reason: "extension_pressure", pressureLevel: .hard)
        )
        XCTAssertFalse(
            SOCKSProxyServer.shouldBypassGraceForExtensionPressure(reason: "maintenance", pressureLevel: .critical)
        )
    }

    func testMessagingAndControlTrafficRemainsPreserved() {
        XCTAssertTrue(
            SOCKSProxyServer.isMessagingOrControlPreserving(
                reason: "tiktok_messages_allow",
                bucket: .tiktokControl,
                port: 443
            )
        )
        XCTAssertTrue(
            SOCKSProxyServer.isMessagingOrControlPreserving(
                reason: "messages_allow",
                bucket: .messages,
                port: 443
            )
        )
        XCTAssertTrue(
            SOCKSProxyServer.isMessagingOrControlPreserving(
                reason: nil,
                bucket: nil,
                port: 53
            )
        )
        XCTAssertFalse(
            SOCKSProxyServer.isMessagingOrControlPreserving(
                reason: "tiktok_video_block_now",
                bucket: .tiktokVideo,
                port: 443
            )
        )
    }

    func testSelectiveGraceBypassOnlyAppliesToCriticalHardenedBlockedStreams() {
        XCTAssertTrue(
            SOCKSProxyServer.shouldBypassGraceForStreamUnderPressure(
                criticalPressure: true,
                hardeningEnabled: true,
                hardeningBucket: .tiktokVideo,
                preservesMessagingControl: false,
                lastPort: 443
            )
        )
        XCTAssertFalse(
            SOCKSProxyServer.shouldBypassGraceForStreamUnderPressure(
                criticalPressure: false,
                hardeningEnabled: true,
                hardeningBucket: .tiktokVideo,
                preservesMessagingControl: false,
                lastPort: 443
            )
        )
        XCTAssertFalse(
            SOCKSProxyServer.shouldBypassGraceForStreamUnderPressure(
                criticalPressure: true,
                hardeningEnabled: false,
                hardeningBucket: nil,
                preservesMessagingControl: false,
                lastPort: 443
            )
        )
        XCTAssertFalse(
            SOCKSProxyServer.shouldBypassGraceForStreamUnderPressure(
                criticalPressure: true,
                hardeningEnabled: true,
                hardeningBucket: .tiktokVideo,
                preservesMessagingControl: true,
                lastPort: 443
            )
        )
        XCTAssertFalse(
            SOCKSProxyServer.shouldBypassGraceForStreamUnderPressure(
                criticalPressure: true,
                hardeningEnabled: true,
                hardeningBucket: .tiktokVideo,
                preservesMessagingControl: false,
                lastPort: 53
            )
        )
    }

    func testCriticalPressurePrioritizesHardenedBlockedReclaimBeforeLowConfidence() {
        let hardenedPriority = SOCKSProxyServer.reclaimPriority(
            criticalPressure: true,
            degradedOrCriticalPressure: true,
            hardeningEnabled: true,
            hardeningBucket: .tiktokVideo,
            trafficClass: .tiktok,
            preservesMessagingControl: false,
            lastPort: 443
        )
        let lowConfidencePriority = SOCKSProxyServer.reclaimPriority(
            criticalPressure: true,
            degradedOrCriticalPressure: true,
            hardeningEnabled: false,
            hardeningBucket: nil,
            trafficClass: .unknown,
            preservesMessagingControl: false,
            lastPort: 443
        )
        let preservedPriority = SOCKSProxyServer.reclaimPriority(
            criticalPressure: true,
            degradedOrCriticalPressure: true,
            hardeningEnabled: false,
            hardeningBucket: nil,
            trafficClass: .tiktok,
            preservesMessagingControl: true,
            lastPort: 443
        )

        XCTAssertLessThan(hardenedPriority, lowConfidencePriority)
        XCTAssertGreaterThan(preservedPriority, lowConfidencePriority)
    }

    func testNormalPressureStillPrefersLowConfidenceBeforeHardenedBlocked() {
        let lowConfidencePriority = SOCKSProxyServer.reclaimPriority(
            criticalPressure: false,
            degradedOrCriticalPressure: false,
            hardeningEnabled: false,
            hardeningBucket: nil,
            trafficClass: .generic,
            preservesMessagingControl: false,
            lastPort: 443
        )
        let hardenedPriority = SOCKSProxyServer.reclaimPriority(
            criticalPressure: false,
            degradedOrCriticalPressure: false,
            hardeningEnabled: true,
            hardeningBucket: .tiktokVideo,
            trafficClass: .tiktok,
            preservesMessagingControl: false,
            lastPort: 443
        )

        XCTAssertLessThan(lowConfidencePriority, hardenedPriority)
    }

    func testBlockedStormRetirementRequiresPressureAndRepeatedBlockedDecisions() {
        XCTAssertTrue(
            SOCKSProxyServer.shouldRetireBlockedStormStream(
                blockedDecisionCount: BubbleConstants.blockedStormRetireThreshold,
                secondsSinceLastSuccess: BubbleConstants.blockedStormRetireNoProgressSeconds + 1,
                noProgressSeconds: BubbleConstants.blockedStormRetireNoProgressSeconds + 1,
                degradedOrCriticalPressure: true,
                stormMode: false,
                hardeningEnabled: true,
                hardeningBucket: .tiktokVideo,
                preservesMessagingControl: false
            )
        )
        XCTAssertFalse(
            SOCKSProxyServer.shouldRetireBlockedStormStream(
                blockedDecisionCount: 1,
                secondsSinceLastSuccess: BubbleConstants.blockedStormRetireNoProgressSeconds + 1,
                noProgressSeconds: BubbleConstants.blockedStormRetireNoProgressSeconds + 1,
                degradedOrCriticalPressure: true,
                stormMode: false,
                hardeningEnabled: true,
                hardeningBucket: .tiktokVideo,
                preservesMessagingControl: false
            )
        )
        XCTAssertFalse(
            SOCKSProxyServer.shouldRetireBlockedStormStream(
                blockedDecisionCount: BubbleConstants.blockedStormRetireThreshold,
                secondsSinceLastSuccess: BubbleConstants.blockedStormRetireNoProgressSeconds + 1,
                noProgressSeconds: BubbleConstants.blockedStormRetireNoProgressSeconds + 1,
                degradedOrCriticalPressure: false,
                stormMode: false,
                hardeningEnabled: true,
                hardeningBucket: .tiktokVideo,
                preservesMessagingControl: false
            )
        )
        XCTAssertFalse(
            SOCKSProxyServer.shouldRetireBlockedStormStream(
                blockedDecisionCount: BubbleConstants.blockedStormRetireThreshold,
                secondsSinceLastSuccess: BubbleConstants.blockedStormRetireNoProgressSeconds + 1,
                noProgressSeconds: BubbleConstants.blockedStormRetireNoProgressSeconds + 1,
                degradedOrCriticalPressure: true,
                stormMode: false,
                hardeningEnabled: true,
                hardeningBucket: .tiktokVideo,
                preservesMessagingControl: true
            )
        )
    }
}
