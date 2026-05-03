import XCTest
@testable import BubbleTunnel

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
          "suppressionKeysActive": 0
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
    }
}
