import XCTest

final class TrafficStatsSnapshotTests: XCTestCase {
    func testStatsSnapshotDecodesNewTransportFields() throws {
        let json = """
        {
          "totalConns": 10,
          "tcpAllowed": 4,
          "tcpBlocked": 2,
          "udpRelayed": 20,
          "errors": 0,
          "udpActiveStreams": 8,
          "udpStreamsOpened": 30,
          "udpStreamsClosed": 22,
          "udpDecodeBadPrefix": 0,
          "udpDecodeBadLength": 1,
          "udpDecodeBadPayload": 0,
          "udpModePlain": 7,
          "udpModeControlPrefixed": 1,
          "udpDecodeModeDetected": 8,
          "udpDecodeResyncAttempted": 1,
          "udpDecodeResyncSuccess": 1,
          "udpDecodeBadLengthHardFail": 0,
          "udpDecodeRecoveredStreamContinues": 1,
          "udpDecodeCloseAfterFailureThreshold": 0,
          "udpActivePeak": 16,
          "udpTimeoutRate": 0.25,
          "dnsInflight": 2,
          "resolverTimeoutStreakByHost": { "8.8.8.8": 3, "1.1.1.1": 0 },
          "resolverSwitchCount": 4,
          "decoderErrorRate": 0.03,
          "streamCloseReasonCounts": { "global_idle_timeout_reclaim": 5 },
          "tiktokHardeningActions": { "timeout_streak_reclaim": 2 },
          "udpQueueDepth": 12,
          "udpQueueOldestAgeMs": 880,
          "udpReclaimsByReason": { "emergency_reclaim": 3 },
          "udpForcedRejects": 1,
          "udpForcedRejectsByReason": { "degraded_tiktok_udp_reject": 1 },
          "degradedState": "recovering",
          "degradedTransitions": 7,
          "trippedTransitions": 2,
          "trippedSecondsTotal": 12.5,
          "badLenRate": 0.45,
          "recentBadLenHardFails": 9,
          "tokenBucketDrops": 5,
          "streamBlockSuppressed": 9,
          "streamBlockTokenDrops": 4,
          "admissionRejectsByReason": { "udp_drop_fast": 3, "tripped_tiktok_udp_reject": 2 },
          "stateSecondsByMode": { "healthy": 30.5, "degraded": 4.0, "tripped": 12.0 },
          "reconnectBreakerCooldownRemainingSec": 33,
          "reconnectBreakerTrips": 4,
          "reconnectSuppressedByBreaker": 6,
          "reconnectBreakerBackoffStep": 3,
          "maintenanceReclaimBudgetExhaustedCount": 2,
          "stormModeActiveSeconds": 44.0,
          "dnsReservedSlotsInUse": 6,
          "decoderSoftDiscards": 21,
          "decoderErrorDensityCloses": 4,
          "attemptedByBucket": { "tiktok_video": 10 },
          "blockedByBucket": { "tiktok_video": 8 },
          "possibleFalsePositiveRetries": 0,
          "blockedSuppressedTCP": 0,
          "blockedSuppressedUDP": 0,
          "suppressionKeysActive": 0,
          "udpDisabledFastRejects": 1200,
          "udpDisabledFastRejectsSuppressed": 1188,
          "safeModeDNSOverTCP": 44,
          "safeModeDNSFailures": 2,
          "safeModeTargetedUDPBlocks": 8,
          "safeModeUnknownUDPAllowed": 91,
          "safeModeUDPRejectedByPressure": 3,
          "safeModeKnownBadUDPCacheHits": 6,
          "dnsFastLaneRequests": 12,
          "dnsFastLaneResponses": 11,
          "dnsFastLaneFailures": 1,
          "dnsFastLaneParseFailed": 2,
          "dnsFastLaneClose": 13,
          "udpNonDNSRejects": 18,
          "udpQUICRejects": 9,
          "dnsOneShotCloses": 16,
          "dnsTimeoutCloses": 2,
          "dnsMalformedCloses": 3,
          "dnsTrailingFramesDiscarded": 5,
          "startupGraceUDPAccepted": 9,
          "startupGraceUDPQueued": 1,
          "startupGraceUDPRejected": 0,
          "hardPressureUDPReclaims": 4,
          "tiktokDNSHintsAdded": 5,
          "tiktokDNSHintsExpired": 1,
          "tiktokDNSHintsActive": 4,
          "tiktokUDPBlocksFromDNSHints": 7,
          "tiktokIPHintsAdded": 6,
          "tiktokIPHintsExpired": 2,
          "tiktokIPHintsActive": 4,
          "tiktokIPHintBlocks": 8,
          "instagramMediaHintsAdded": 3,
          "instagramMediaHintsExpired": 1,
          "instagramMediaHintBlocks": 9,
          "tcpSNIBlockSuppressed": 320,
          "tcpSNIBlockTokenDrops": 40,
          "protectedBlockSuppressionKeys": 12,
          "udpForwardingMode": "selective_safe_mode",
          "providerLastPhase": "dns_one_shot_close",
          "startupStabilityPhase": "startup_probe_completed",
          "startupProbeCompleted": true,
          "dnsStartupDrainActive": true,
          "dnsStartupDrainCloses": 3,
          "dnsStartupDrainFramesProcessed": 7,
          "earlyReconnectSuppressed": true,
          "iosSafeModeReason": "short_unknown_status_drop_breaker",
          "udpClosePhase": "drain_scheduled",
          "udpDeferredCancels": 4,
          "udpGracefulDNSCloses": 3,
          "udpCancelWatchdogFires": 2,
          "udpStartupSerialModeActive": true,
          "udpCrashGuardActive": true,
          "udpCrashGuardReason": "prior_decoder_recovery_falloff",
          "dnsRecoveredOneShotCloses": 2,
          "dnsRecoveredFramesDiscarded": 6,
          "tcpEarlySNIBlocks": 5,
          "tcpEarlySNIAllows": 7,
          "tcpEarlySNIFallbacks": 2
        }
        """

        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(StatsSnapshot.self, from: data)

        XCTAssertEqual(decoded.udpQueueDepth, 12)
        XCTAssertEqual(decoded.udpQueueOldestAgeMs, 880)
        XCTAssertEqual(decoded.udpReclaimsByReason["emergency_reclaim"], 3)
        XCTAssertEqual(decoded.udpForcedRejects, 1)
        XCTAssertEqual(decoded.udpForcedRejectsByReason["degraded_tiktok_udp_reject"], 1)
        XCTAssertEqual(decoded.degradedState, "recovering")
        XCTAssertEqual(decoded.degradedTransitions, 7)
        XCTAssertEqual(decoded.trippedTransitions, 2)
        XCTAssertEqual(decoded.trippedSecondsTotal, 12.5, accuracy: 0.0001)
        XCTAssertEqual(decoded.badLenRate, 0.45, accuracy: 0.0001)
        XCTAssertEqual(decoded.recentBadLenHardFails, 9)
        XCTAssertEqual(decoded.tokenBucketDrops, 5)
        XCTAssertEqual(decoded.streamBlockSuppressed, 9)
        XCTAssertEqual(decoded.streamBlockTokenDrops, 4)
        XCTAssertEqual(decoded.admissionRejectsByReason["udp_drop_fast"], 3)
        XCTAssertEqual(decoded.stateSecondsByMode["tripped"], 12.0)
        XCTAssertEqual(decoded.reconnectBreakerCooldownRemainingSec, 33)
        XCTAssertEqual(decoded.reconnectBreakerTrips, 4)
        XCTAssertEqual(decoded.reconnectSuppressedByBreaker, 6)
        XCTAssertEqual(decoded.reconnectBreakerBackoffStep, 3)
        XCTAssertEqual(decoded.maintenanceReclaimBudgetExhaustedCount, 2)
        XCTAssertEqual(decoded.stormModeActiveSeconds, 44.0, accuracy: 0.0001)
        XCTAssertEqual(decoded.dnsReservedSlotsInUse, 6)
        XCTAssertEqual(decoded.decoderSoftDiscards, 21)
        XCTAssertEqual(decoded.decoderErrorDensityCloses, 4)
        XCTAssertEqual(decoded.resolverTimeoutStreakByHost["8.8.8.8"], 3)
        XCTAssertEqual(decoded.resolverSwitchCount, 4)
        XCTAssertEqual(decoded.tiktokHardeningActions["timeout_streak_reclaim"], 2)
        XCTAssertEqual(decoded.udpDisabledFastRejects, 1200)
        XCTAssertEqual(decoded.udpDisabledFastRejectsSuppressed, 1188)
        XCTAssertEqual(decoded.safeModeDNSOverTCP, 44)
        XCTAssertEqual(decoded.safeModeDNSFailures, 2)
        XCTAssertEqual(decoded.safeModeTargetedUDPBlocks, 8)
        XCTAssertEqual(decoded.safeModeUnknownUDPAllowed, 91)
        XCTAssertEqual(decoded.safeModeUDPRejectedByPressure, 3)
        XCTAssertEqual(decoded.safeModeKnownBadUDPCacheHits, 6)
        XCTAssertEqual(decoded.dnsFastLaneRequests, 12)
        XCTAssertEqual(decoded.dnsFastLaneResponses, 11)
        XCTAssertEqual(decoded.dnsFastLaneFailures, 1)
        XCTAssertEqual(decoded.dnsFastLaneParseFailed, 2)
        XCTAssertEqual(decoded.dnsFastLaneClose, 13)
        XCTAssertEqual(decoded.udpNonDNSRejects, 18)
        XCTAssertEqual(decoded.udpQUICRejects, 9)
        XCTAssertEqual(decoded.dnsOneShotCloses, 16)
        XCTAssertEqual(decoded.dnsTimeoutCloses, 2)
        XCTAssertEqual(decoded.dnsMalformedCloses, 3)
        XCTAssertEqual(decoded.dnsTrailingFramesDiscarded, 5)
        XCTAssertEqual(decoded.startupGraceUDPAccepted, 9)
        XCTAssertEqual(decoded.startupGraceUDPQueued, 1)
        XCTAssertEqual(decoded.startupGraceUDPRejected, 0)
        XCTAssertEqual(decoded.hardPressureUDPReclaims, 4)
        XCTAssertEqual(decoded.tiktokDNSHintsAdded, 5)
        XCTAssertEqual(decoded.tiktokDNSHintsExpired, 1)
        XCTAssertEqual(decoded.tiktokDNSHintsActive, 4)
        XCTAssertEqual(decoded.tiktokUDPBlocksFromDNSHints, 7)
        XCTAssertEqual(decoded.tiktokIPHintsAdded, 6)
        XCTAssertEqual(decoded.tiktokIPHintsExpired, 2)
        XCTAssertEqual(decoded.tiktokIPHintsActive, 4)
        XCTAssertEqual(decoded.tiktokIPHintBlocks, 8)
        XCTAssertEqual(decoded.instagramMediaHintsAdded, 3)
        XCTAssertEqual(decoded.instagramMediaHintsExpired, 1)
        XCTAssertEqual(decoded.instagramMediaHintBlocks, 9)
        XCTAssertEqual(decoded.tcpSNIBlockSuppressed, 320)
        XCTAssertEqual(decoded.tcpSNIBlockTokenDrops, 40)
        XCTAssertEqual(decoded.protectedBlockSuppressionKeys, 12)
        XCTAssertEqual(decoded.udpForwardingMode, "selective_safe_mode")
        XCTAssertEqual(decoded.providerLastPhase, "dns_one_shot_close")
        XCTAssertEqual(decoded.startupStabilityPhase, "startup_probe_completed")
        XCTAssertTrue(decoded.startupProbeCompleted)
        XCTAssertTrue(decoded.dnsStartupDrainActive)
        XCTAssertEqual(decoded.dnsStartupDrainCloses, 3)
        XCTAssertEqual(decoded.dnsStartupDrainFramesProcessed, 7)
        XCTAssertTrue(decoded.earlyReconnectSuppressed)
        XCTAssertEqual(decoded.iosSafeModeReason, "short_unknown_status_drop_breaker")
        XCTAssertEqual(decoded.udpClosePhase, "drain_scheduled")
        XCTAssertEqual(decoded.udpDeferredCancels, 4)
        XCTAssertEqual(decoded.udpGracefulDNSCloses, 3)
        XCTAssertEqual(decoded.udpCancelWatchdogFires, 2)
        XCTAssertTrue(decoded.udpStartupSerialModeActive)
        XCTAssertTrue(decoded.udpCrashGuardActive)
        XCTAssertEqual(decoded.udpCrashGuardReason, "prior_decoder_recovery_falloff")
        XCTAssertEqual(decoded.dnsRecoveredOneShotCloses, 2)
        XCTAssertEqual(decoded.dnsRecoveredFramesDiscarded, 6)
        XCTAssertEqual(decoded.tcpEarlySNIBlocks, 5)
        XCTAssertEqual(decoded.tcpEarlySNIAllows, 7)
        XCTAssertEqual(decoded.tcpEarlySNIFallbacks, 2)
    }

    func testStatsSnapshotBackCompatDefaultsWhenFieldsMissing() throws {
        let json = """
        {
          "totalConns": 1,
          "tcpAllowed": 1,
          "tcpBlocked": 0,
          "udpRelayed": 0,
          "errors": 0
        }
        """

        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(StatsSnapshot.self, from: data)

        XCTAssertEqual(decoded.udpQueueDepth, 0)
        XCTAssertEqual(decoded.udpQueueOldestAgeMs, 0)
        XCTAssertEqual(decoded.udpReclaimsByReason, [:])
        XCTAssertEqual(decoded.udpForcedRejects, 0)
        XCTAssertEqual(decoded.udpForcedRejectsByReason, [:])
        XCTAssertEqual(decoded.degradedState, "healthy")
        XCTAssertEqual(decoded.degradedTransitions, 0)
        XCTAssertEqual(decoded.trippedTransitions, 0)
        XCTAssertEqual(decoded.trippedSecondsTotal, 0)
        XCTAssertEqual(decoded.badLenRate, 0)
        XCTAssertEqual(decoded.recentBadLenHardFails, 0)
        XCTAssertEqual(decoded.tokenBucketDrops, 0)
        XCTAssertEqual(decoded.streamBlockSuppressed, 0)
        XCTAssertEqual(decoded.streamBlockTokenDrops, 0)
        XCTAssertEqual(decoded.admissionRejectsByReason, [:])
        XCTAssertEqual(decoded.stateSecondsByMode, [:])
        XCTAssertEqual(decoded.reconnectBreakerCooldownRemainingSec, 0)
        XCTAssertEqual(decoded.reconnectBreakerTrips, 0)
        XCTAssertEqual(decoded.reconnectSuppressedByBreaker, 0)
        XCTAssertEqual(decoded.reconnectBreakerBackoffStep, 0)
        XCTAssertEqual(decoded.maintenanceReclaimBudgetExhaustedCount, 0)
        XCTAssertEqual(decoded.stormModeActiveSeconds, 0, accuracy: 0.0001)
        XCTAssertEqual(decoded.dnsReservedSlotsInUse, 0)
        XCTAssertEqual(decoded.decoderSoftDiscards, 0)
        XCTAssertEqual(decoded.decoderErrorDensityCloses, 0)
        XCTAssertEqual(decoded.resolverTimeoutStreakByHost, [:])
        XCTAssertEqual(decoded.resolverSwitchCount, 0)
        XCTAssertEqual(decoded.udpDisabledFastRejects, 0)
        XCTAssertEqual(decoded.udpDisabledFastRejectsSuppressed, 0)
        XCTAssertEqual(decoded.safeModeDNSOverTCP, 0)
        XCTAssertEqual(decoded.safeModeDNSFailures, 0)
        XCTAssertEqual(decoded.safeModeTargetedUDPBlocks, 0)
        XCTAssertEqual(decoded.safeModeUnknownUDPAllowed, 0)
        XCTAssertEqual(decoded.safeModeUDPRejectedByPressure, 0)
        XCTAssertEqual(decoded.safeModeKnownBadUDPCacheHits, 0)
        XCTAssertEqual(decoded.dnsFastLaneRequests, 0)
        XCTAssertEqual(decoded.dnsFastLaneResponses, 0)
        XCTAssertEqual(decoded.dnsFastLaneFailures, 0)
        XCTAssertEqual(decoded.dnsFastLaneParseFailed, 0)
        XCTAssertEqual(decoded.dnsFastLaneClose, 0)
        XCTAssertEqual(decoded.udpNonDNSRejects, 0)
        XCTAssertEqual(decoded.udpQUICRejects, 0)
        XCTAssertEqual(decoded.dnsOneShotCloses, 0)
        XCTAssertEqual(decoded.dnsTimeoutCloses, 0)
        XCTAssertEqual(decoded.dnsMalformedCloses, 0)
        XCTAssertEqual(decoded.dnsTrailingFramesDiscarded, 0)
        XCTAssertEqual(decoded.startupGraceUDPAccepted, 0)
        XCTAssertEqual(decoded.startupGraceUDPQueued, 0)
        XCTAssertEqual(decoded.startupGraceUDPRejected, 0)
        XCTAssertEqual(decoded.hardPressureUDPReclaims, 0)
        XCTAssertEqual(decoded.tiktokDNSHintsAdded, 0)
        XCTAssertEqual(decoded.tiktokDNSHintsExpired, 0)
        XCTAssertEqual(decoded.tiktokDNSHintsActive, 0)
        XCTAssertEqual(decoded.tiktokUDPBlocksFromDNSHints, 0)
        XCTAssertEqual(decoded.tiktokIPHintsAdded, 0)
        XCTAssertEqual(decoded.tiktokIPHintsExpired, 0)
        XCTAssertEqual(decoded.tiktokIPHintsActive, 0)
        XCTAssertEqual(decoded.tiktokIPHintBlocks, 0)
        XCTAssertEqual(decoded.instagramMediaHintsAdded, 0)
        XCTAssertEqual(decoded.instagramMediaHintsExpired, 0)
        XCTAssertEqual(decoded.instagramMediaHintBlocks, 0)
        XCTAssertEqual(decoded.tcpSNIBlockSuppressed, 0)
        XCTAssertEqual(decoded.tcpSNIBlockTokenDrops, 0)
        XCTAssertEqual(decoded.protectedBlockSuppressionKeys, 0)
        XCTAssertEqual(decoded.udpForwardingMode, "unknown")
        XCTAssertEqual(decoded.providerLastPhase, "unknown")
        XCTAssertEqual(decoded.startupStabilityPhase, "unknown")
        XCTAssertFalse(decoded.startupProbeCompleted)
        XCTAssertFalse(decoded.dnsStartupDrainActive)
        XCTAssertEqual(decoded.dnsStartupDrainCloses, 0)
        XCTAssertEqual(decoded.dnsStartupDrainFramesProcessed, 0)
        XCTAssertFalse(decoded.earlyReconnectSuppressed)
        XCTAssertEqual(decoded.iosSafeModeReason, "")
        XCTAssertEqual(decoded.udpClosePhase, "none")
        XCTAssertEqual(decoded.udpDeferredCancels, 0)
        XCTAssertEqual(decoded.udpGracefulDNSCloses, 0)
        XCTAssertEqual(decoded.udpCancelWatchdogFires, 0)
        XCTAssertFalse(decoded.udpStartupSerialModeActive)
        XCTAssertFalse(decoded.udpCrashGuardActive)
        XCTAssertEqual(decoded.udpCrashGuardReason, "")
        XCTAssertEqual(decoded.dnsRecoveredOneShotCloses, 0)
        XCTAssertEqual(decoded.dnsRecoveredFramesDiscarded, 0)
        XCTAssertEqual(decoded.tcpEarlySNIBlocks, 0)
        XCTAssertEqual(decoded.tcpEarlySNIAllows, 0)
        XCTAssertEqual(decoded.tcpEarlySNIFallbacks, 0)
    }
}
