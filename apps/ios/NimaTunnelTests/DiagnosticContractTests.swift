import XCTest

final class DiagnosticContractTests: XCTestCase {
    func testDiagnosticLifecycleKeysRemainStable() {
        let keys = [
            NimaConstants.vpnLifecycleResolvedStopClassKey,
            NimaConstants.vpnLifecycleTransportDegradedKey,
            NimaConstants.vpnLifecycleTransportDegradedReasonKey,
            NimaConstants.vpnLifecycleReconnectSuppressedByBreakerKey,
            NimaConstants.vpnLifecycleExternalKillSignatureKey,
            NimaConstants.vpnLifecycleExternalKillSignatureTierKey,
            NimaConstants.vpnLifecycleExternalKillReconnectAttemptsInWindowKey,
            NimaConstants.vpnLifecycleDiagnosticHoldCompletedKey,
            NimaConstants.vpnLifecycleExtensionPressureLastSampleTSKey,
            NimaConstants.vpnLifecycleAppLifecycleLastEventKey,
            NimaConstants.vpnLifecycleLastBreadcrumbKey,
            NimaConstants.vpnLifecycleLastBreadcrumbTSKey,
            NimaConstants.vpnLifecycleLastBreadcrumbDetailsKey,
            NimaConstants.vpnLifecycleProviderLastPhaseKey,
            NimaConstants.vpnLifecycleProviderLastPhaseTSKey,
            NimaConstants.vpnLifecycleProviderHeartbeatSnapshotJSONKey,
            NimaConstants.providerPhaseRingJSONKey,
            NimaConstants.udpLastControlStreamJSONKey,
            NimaConstants.udpLastDNSCloseJSONKey,
            NimaConstants.udpLastDecoderEventJSONKey,
            NimaConstants.tun2socksLastStatsJSONKey,
            NimaConstants.udpCrashGuardUntilKey,
            NimaConstants.udpCrashGuardReasonKey,
            NimaConstants.udpCrashGuardHitsKey,
            NimaConstants.vpnLifecycleLastReconnectDelaySecondsKey,
            NimaConstants.vpnLifecycleStartupStabilityPhaseKey,
            NimaConstants.vpnLifecycleStartupProbeCompletedKey,
            NimaConstants.vpnLifecycleStartupProbeCompletedTSKey,
            NimaConstants.tun2socksStartupModeKey,
            NimaConstants.vpnLifecycleTransportReadyKey,
            NimaConstants.vpnLifecycleTransportReadyTSKey,
            NimaConstants.vpnLifecycleDNSStartupDrainActiveKey,
            NimaConstants.vpnLifecycleDNSStartupDrainClosesKey,
            NimaConstants.vpnLifecycleDNSStartupDrainFramesProcessedKey,
            NimaConstants.vpnLifecycleEarlyReconnectSuppressedKey,
            NimaConstants.vpnLifecycleIOSSafeModeReasonKey,
            NimaConstants.scheduleDesiredVPNOnKey,
            NimaConstants.scheduleDesiredUntilTSKey,
            NimaConstants.scheduleManualOffUntilTSKey,
            NimaConstants.scheduleActiveAppIDsKey,
            NimaConstants.scheduleActiveWindowIDsKey,
            NimaConstants.scheduleLastInterruptionTSKey,
            NimaConstants.scheduleLastRepairResultKey,
        ]

        for key in keys {
            XCTAssertTrue(
                key.hasPrefix("vpnLifecycle.") ||
                    key.hasPrefix("schedule.") ||
                    key.hasSuffix("_json") ||
                    key.hasPrefix("udp_crash_guard_"),
                "key drifted from diagnostic contract: \(key)"
            )
            XCTAssertFalse(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    func testStatsSnapshotContractHasQueueAndClassCounters() throws {
        let json = """
        {
          "totalConns": 1,
          "tcpAllowed": 1,
          "tcpBlocked": 0,
          "udpRelayed": 0,
          "errors": 0,
          "udpQueueDepth": 4,
          "udpQueueOldestAgeMs": 120,
          "udpQueueP95AgeMs": 240,
          "admissionRejectsByReason": { "udp_admission_unknown_rate_limit": 2 },
          "udpForcedRejects": 1,
          "udpDisabledFastRejects": 9,
          "udpDisabledFastRejectsSuppressed": 7,
          "safeModeDNSOverTCP": 11,
          "safeModeDNSFailures": 1,
          "safeModeTargetedUDPBlocks": 4,
          "safeModeUnknownUDPAllowed": 22,
          "safeModeUDPRejectedByPressure": 2,
          "safeModeKnownBadUDPCacheHits": 3,
          "dnsFastLaneRequests": 5,
          "dnsFastLaneResponses": 4,
          "dnsFastLaneFailures": 1,
          "dnsFastLaneParseFailed": 1,
          "dnsFastLaneClose": 6,
          "udpNonDNSRejects": 8,
          "udpQUICRejects": 3,
          "dnsOneShotCloses": 6,
          "dnsTrailingFramesDiscarded": 2,
          "tiktokIPHintsAdded": 4,
          "tiktokIPHintsExpired": 1,
          "tiktokIPHintsActive": 3,
          "tiktokIPHintBlocks": 7,
          "instagramMediaHintsAdded": 2,
          "instagramMediaHintsExpired": 1,
          "instagramMediaHintBlocks": 5,
          "tcpSNIBlockSuppressed": 3,
          "tcpSNIBlockTokenDrops": 1,
          "protectedBlockSuppressionKeys": 2,
          "udpForwardingMode": "native_forwarding",
          "providerLastPhase": "dns_one_shot_close",
          "startupStabilityPhase": "startup_probe_completed",
          "startupProbeCompleted": true,
          "dnsStartupDrainActive": true,
          "dnsStartupDrainCloses": 2,
          "dnsStartupDrainFramesProcessed": 5,
          "earlyReconnectSuppressed": true,
          "iosSafeModeReason": "short_unknown_status_drop_breaker",
          "udpClosePhase": "cancel_scheduled",
          "udpDeferredCancels": 3,
          "udpGracefulDNSCloses": 2,
          "udpCancelWatchdogFires": 1,
          "udpStartupSerialModeActive": true,
          "udpCrashGuardActive": true,
          "udpCrashGuardReason": "prior_dns_udp_close_falloff",
          "dnsRecoveredOneShotCloses": 1,
          "dnsRecoveredFramesDiscarded": 2,
          "degradedState": "healthy",
          "reconnectSuppressedByBreaker": 0
        }
        """

        let snapshot = try JSONDecoder().decode(StatsSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.udpQueueDepth, 4)
        XCTAssertEqual(snapshot.udpQueueOldestAgeMs, 120)
        XCTAssertEqual(snapshot.udpQueueP95AgeMs, 240)
        XCTAssertEqual(snapshot.admissionRejectsByReason["udp_admission_unknown_rate_limit"], 2)
        XCTAssertEqual(snapshot.udpForcedRejects, 1)
        XCTAssertEqual(snapshot.udpDisabledFastRejects, 9)
        XCTAssertEqual(snapshot.udpDisabledFastRejectsSuppressed, 7)
        XCTAssertEqual(snapshot.safeModeDNSOverTCP, 11)
        XCTAssertEqual(snapshot.safeModeDNSFailures, 1)
        XCTAssertEqual(snapshot.safeModeTargetedUDPBlocks, 4)
        XCTAssertEqual(snapshot.safeModeUnknownUDPAllowed, 22)
        XCTAssertEqual(snapshot.safeModeUDPRejectedByPressure, 2)
        XCTAssertEqual(snapshot.safeModeKnownBadUDPCacheHits, 3)
        XCTAssertEqual(snapshot.dnsFastLaneRequests, 5)
        XCTAssertEqual(snapshot.dnsFastLaneResponses, 4)
        XCTAssertEqual(snapshot.dnsFastLaneFailures, 1)
        XCTAssertEqual(snapshot.dnsFastLaneParseFailed, 1)
        XCTAssertEqual(snapshot.dnsFastLaneClose, 6)
        XCTAssertEqual(snapshot.udpNonDNSRejects, 8)
        XCTAssertEqual(snapshot.udpQUICRejects, 3)
        XCTAssertEqual(snapshot.dnsOneShotCloses, 6)
        XCTAssertEqual(snapshot.dnsTrailingFramesDiscarded, 2)
        XCTAssertEqual(snapshot.tiktokIPHintsAdded, 4)
        XCTAssertEqual(snapshot.tiktokIPHintsExpired, 1)
        XCTAssertEqual(snapshot.tiktokIPHintsActive, 3)
        XCTAssertEqual(snapshot.tiktokIPHintBlocks, 7)
        XCTAssertEqual(snapshot.instagramMediaHintsAdded, 2)
        XCTAssertEqual(snapshot.instagramMediaHintsExpired, 1)
        XCTAssertEqual(snapshot.instagramMediaHintBlocks, 5)
        XCTAssertEqual(snapshot.tcpSNIBlockSuppressed, 3)
        XCTAssertEqual(snapshot.tcpSNIBlockTokenDrops, 1)
        XCTAssertEqual(snapshot.protectedBlockSuppressionKeys, 2)
        XCTAssertEqual(snapshot.udpForwardingMode, "native_forwarding")
        XCTAssertEqual(snapshot.providerLastPhase, "dns_one_shot_close")
        XCTAssertEqual(snapshot.startupStabilityPhase, "startup_probe_completed")
        XCTAssertTrue(snapshot.startupProbeCompleted)
        XCTAssertTrue(snapshot.dnsStartupDrainActive)
        XCTAssertEqual(snapshot.dnsStartupDrainCloses, 2)
        XCTAssertEqual(snapshot.dnsStartupDrainFramesProcessed, 5)
        XCTAssertTrue(snapshot.earlyReconnectSuppressed)
        XCTAssertEqual(snapshot.iosSafeModeReason, "short_unknown_status_drop_breaker")
        XCTAssertEqual(snapshot.udpClosePhase, "cancel_scheduled")
        XCTAssertEqual(snapshot.udpDeferredCancels, 3)
        XCTAssertEqual(snapshot.udpGracefulDNSCloses, 2)
        XCTAssertEqual(snapshot.udpCancelWatchdogFires, 1)
        XCTAssertTrue(snapshot.udpStartupSerialModeActive)
        XCTAssertTrue(snapshot.udpCrashGuardActive)
        XCTAssertEqual(snapshot.udpCrashGuardReason, "prior_dns_udp_close_falloff")
        XCTAssertEqual(snapshot.dnsRecoveredOneShotCloses, 1)
        XCTAssertEqual(snapshot.dnsRecoveredFramesDiscarded, 2)
        XCTAssertEqual(snapshot.degradedState, "healthy")
        XCTAssertEqual(snapshot.reconnectSuppressedByBreaker, 0)
    }

    func testAdmissionContractForUnknownDoesNotMapToGeneric() {
        let classified = ClassifiedFlow(trafficClass: .unknown, confidence: 0.20, reason: "contract_check")
        let admission = SOCKSProxyServer.admissionTrafficClass(for: classified)
        XCTAssertEqual(admission, .unknown)
    }

    func testProviderHeartbeatSnapshotFieldsRemainStable() {
        let fields = SOCKSProxyServer.providerHeartbeatSnapshotFields(
            """
            {"active_udp":1,"app_lifecycle":"background","dns_fast_lane_close":8,"dns_fast_lane_failures":2,"dns_fast_lane_parse_failed":1,"dns_fast_lane_requests":4,"dns_fast_lane_responses":3,"dns_startup_drain_active":true,"dns_startup_drain_closes":2,"dns_startup_drain_frames_processed":5,"early_reconnect_suppressed":true,"ios_safe_mode_reason":"short_unknown_status_drop_breaker","last_decoder_event":{"reason":"decoder_density"},"last_dns_close":{"reason":"dns_response_one_shot_retire"},"last_udp_close_phase":"grace_close_blocked","memory_mb":51,"path_state":{"status":"satisfied","unsatisfied_reason":"none"},"provider_phase":"udp_accept","proxy_ready":true,"queued_udp":8,"startup_probe_completed":true,"startup_stability_phase":"startup_probe_completed","ts":10,"tun2socks_down_packets":"34","tun2socks_up_packets":"21","udp_non_dns_rejects":6,"udp_quic_rejects":5}
            """
        )

        XCTAssertEqual(fields["provider_phase"], "udp_accept")
        XCTAssertEqual(fields["startup_stability_phase"], "startup_probe_completed")
        XCTAssertEqual(fields["startup_probe_completed"], "true")
        XCTAssertEqual(fields["proxy_ready"], "true")
        XCTAssertEqual(fields["memory_mb"], "51")
        XCTAssertEqual(fields["tun2socks_up_packets"], "21")
        XCTAssertEqual(fields["tun2socks_down_packets"], "34")
        XCTAssertEqual(fields["active_udp"], "1")
        XCTAssertEqual(fields["queued_udp"], "8")
        XCTAssertEqual(fields["last_udp_close_phase"], "grace_close_blocked")
        XCTAssertEqual(fields["dns_startup_drain_active"], "true")
        XCTAssertEqual(fields["dns_startup_drain_closes"], "2")
        XCTAssertEqual(fields["dns_startup_drain_frames_processed"], "5")
        XCTAssertEqual(fields["dns_fast_lane_requests"], "4")
        XCTAssertEqual(fields["dns_fast_lane_responses"], "3")
        XCTAssertEqual(fields["dns_fast_lane_failures"], "2")
        XCTAssertEqual(fields["dns_fast_lane_parse_failed"], "1")
        XCTAssertEqual(fields["dns_fast_lane_close"], "8")
        XCTAssertEqual(fields["udp_non_dns_rejects"], "6")
        XCTAssertEqual(fields["udp_quic_rejects"], "5")
        XCTAssertEqual(fields["early_reconnect_suppressed"], "true")
        XCTAssertEqual(fields["ios_safe_mode_reason"], "short_unknown_status_drop_breaker")
        XCTAssertEqual(fields["app_lifecycle"], "background")
        XCTAssertEqual(fields["path_status"], "satisfied")
        XCTAssertEqual(fields["path_unsatisfied_reason"], "none")
        XCTAssertTrue(fields["last_decoder_event"]?.contains("\"reason\":\"decoder_density\"") == true)
        XCTAssertTrue(fields["last_dns_close"]?.contains("\"reason\":\"dns_response_one_shot_retire\"") == true)
    }
}
