import Foundation

enum BubbleConstants {
    // MARK: - Identifiers
    static let appGroupID = "group.com.yamin.nimademo"
    static let tunnelBundleID = "com.yamin.nimademo.BubbleTunnel"

    // MARK: - Network Settings
    static let tunnelRemoteAddress = "198.18.0.1"
    static let tunnelLocalAddress = "198.18.0.2"
    static let tunnelSubnetMask = "255.255.255.0"
    static let dnsServers = ["8.8.8.8", "1.1.1.1"]
    static let mtu: NSNumber = 9000

    // MARK: - tun2socks Configuration
    static let tun2socksTaskStackSize = 24576
    static let tun2socksTCPBufferSize = 4096
    static let tun2socksConnectTimeout = 5000
    static let tun2socksReadWriteTimeout = 60000

    // MARK: - SOCKS5 Proxy
    static let socksBindAddress = "127.0.0.1"
    static let maxUDPFrameSize = 2048
    static let relayBufferSize = 65536
    static let udpRelayTimeout: TimeInterval = 5.0
    static let tcpRelayTimeout: TimeInterval = 120.0
    static let maxConnections = 500
    static let statsInterval: TimeInterval = 10.0
    static let udpDecodeFailureCloseThreshold = 3
    static let udpDecodeFailureWindowSeconds: TimeInterval = 4.0
    static let udpDecodeBadLenSoftFailureLimit = 6
    static let maxActiveUDPControlStreams = 12
    static let maxQueuedUDPControlStreams = 4
    static let udpAdmissionCreateRatePerSecond = 4.0
    static let udpAdmissionCreateRateCapacity = 5
    static let dnsDedupWindow: TimeInterval = 0.5
    static let dnsTimeoutStreakForFailover = 3
    static let tiktokHardeningIdleTimeout: TimeInterval = 12.0
    static let tiktokHardeningMaxLifetime: TimeInterval = 90.0
    static let tiktokHardeningSweepInterval: TimeInterval = 2.0
    static let tiktokHardeningTimeoutStreakCloseThreshold = 3
    static let tiktokHardeningMaxPendingFramesPerStream = 128
    static let tiktokHardeningDNSDedupWindow: TimeInterval = 1.5
    static let tiktokHardeningUDPTimeoutRateThreshold = 0.35
    static let udpGlobalIdleTimeout: TimeInterval = 6.0
    static let udpGlobalMaxLifetime: TimeInterval = 30.0
    static let udpGlobalTimeoutStreakCloseThreshold = 3
    static let udpProcessingWatchdogTimeout: TimeInterval = 8.0
    static let udpProcessingWatchdogTimeoutDegraded: TimeInterval = 5.0
    static let udpQueuedStreamMaxAge: TimeInterval = 2.5
    static let udpEmergencyReclaimBatchSize = 2
    static let udpEmergencyReclaimMinInterval: TimeInterval = 0.75
    static let dnsInflightMaxAge: TimeInterval = 6.0
    static let resolverSwitchCooldown: TimeInterval = 5.0
    static let degradedEnterQueueDepth = 24
    static let degradedRecoverQueueDepth = 8
    static let degradedTimeoutRateEnter = 0.45
    static let degradedTimeoutRateRecover = 0.15
    static let trippedEnterQueueDepth = 28
    static let trippedEnterTimeoutRate = 0.60
    static let trippedEnterEmergencyReclaims = 8
    static let trippedEnterMinDegradedSeconds: TimeInterval = 8.0
    static let trippedWindowSeconds: TimeInterval = 20.0
    static let trippedRecoverStabilizationSeconds: TimeInterval = 30.0
    static let trippedRecoverQueueDepth = 4
    static let trippedRecoverTimeoutRate = 0.10
    static let degradedBadLenRateEnter = 0.35
    static let degradedBadLenRateRecover = 0.10
    static let trippedBadLenRateEnter = 0.55
    static let trippedBadLenRateRecover = 0.12
    static let badLenRateWindowSeconds: TimeInterval = 20.0
    static let degradedRecoverStabilizationSeconds: TimeInterval = 12.0
    static let degradedTikTokUDPRejectQueueDepth = 12
    static let stabilityFirstStartupGraceSeconds: TimeInterval = 30.0
    static let stabilityFirstRecoveryGraceSeconds: TimeInterval = 20.0
    static let reclaimReasonCooldownSeconds: TimeInterval = 3.0
    static let selectiveReclaimMinIdleSeconds: TimeInterval = 3.0
    static let selectiveReclaimMinLifetimeSeconds: TimeInterval = 6.0
    static let selectiveReclaimMaxPerSweep = 2
    static let transportPressureDiagnosticsInterval: TimeInterval = 5.0
    static let trippedCriticalDwellSeconds: TimeInterval = 12.0
    static let dnsFailoverScoreThreshold = 3
    static let dnsFailoverReturnDelaySeconds: TimeInterval = 15.0
    static let dnsFailoverScoreDecayPerSuccess = 2
    static let hostCooldownDropSeconds: TimeInterval = 10.0

    // MARK: - Logging
    static let appLogFileName = "app_diagnostic_log.txt"
    static let logFileName = "tunnel_log.txt"
    static let maxLogSizeBytes = 512 * 1024
    static let maxStatusLogEntries = 200
    static let logSubsystem = "com.yamin.nimademo.BubbleTunnel"
    static let statsFileName = "traffic_stats.json"

    // MARK: - Stream Blocking
    static let streamBlockDefaultThreshold = 512 * 1024  // 0.5 MB
    static let maxSNIProbePackets = 6

    // MARK: - UserDefaults Keys
    static let strictUDPBlockEnabledKey = "strictUDPBlockEnabled"
    static let featurePolicyKey = "featurePolicyV1"
    static let classifierTuningKey = "classifierTuningV1"
    static let vpnLifecycleLastStartTSKey = "vpnLifecycle.last_start_ts"
    static let vpnLifecycleLastStopTSKey = "vpnLifecycle.last_stop_ts"
    static let vpnLifecycleStopReasonKey = "vpnLifecycle.stop_reason"
    static let vpnLifecycleLastExitCodeKey = "vpnLifecycle.last_exit_code"
    static let vpnLifecycleLastHeartbeatTSKey = "vpnLifecycle.last_heartbeat_ts"
    static let vpnLifecycleUnexpectedExitKey = "vpnLifecycle.unexpected_exit"
    static let manualOffRequestedKey = "vpnLifecycle.manual_off_requested"
    static let vpnLifecycleLastPathStatusKey = "vpnLifecycle.last_path_status"
    static let vpnLifecycleLastPathUnsatisfiedReasonKey = "vpnLifecycle.last_path_unsatisfied_reason"
    static let vpnLifecycleLastPathInterfacesKey = "vpnLifecycle.last_path_interfaces"
    static let vpnLifecycleLastPathIsExpensiveKey = "vpnLifecycle.last_path_is_expensive"
    static let vpnLifecycleLastPathIsConstrainedKey = "vpnLifecycle.last_path_is_constrained"
    static let vpnLifecycleLastPathUpdateTSKey = "vpnLifecycle.last_path_update_ts"
    static let vpnLifecycleStopSourceKey = "vpnLifecycle.stop_source"
    static let vpnLifecycleStopReasonRawKey = "vpnLifecycle.stop_reason_raw"
    static let vpnLifecycleTransportDegradedKey = "vpnLifecycle.transport_degraded"
    static let vpnLifecycleTransportDegradedReasonKey = "vpnLifecycle.transport_degraded_reason"
    static let vpnLifecycleTransportDegradedTSKey = "vpnLifecycle.transport_degraded_ts"
    static let vpnLifecycleReconnectBreakerUntilTSKey = "vpnLifecycle.reconnect_breaker_until_ts"
    static let vpnLifecycleReconnectBreakerTripsKey = "vpnLifecycle.reconnect_breaker_trips"
    static let vpnLifecycleReconnectBreakerRecentDisconnectsKey = "vpnLifecycle.reconnect_breaker_recent_disconnects"
    static let vpnLifecycleReconnectSuppressedByBreakerKey = "vpnLifecycle.reconnect_suppressed_by_breaker"
    static let vpnLifecycleReconnectBreakerFailureScoreKey = "vpnLifecycle.reconnect_breaker_failure_score"
    static let vpnLifecycleReconnectBreakerBackoffStepKey = "vpnLifecycle.reconnect_breaker_backoff_step"
    static let vpnLifecycleRunningMarkerKey = "vpnLifecycle.running_marker"
    static let vpnLifecycleInferredCrashKey = "vpnLifecycle.inferred_crash"
    static let vpnLifecycleResolvedStopClassKey = "vpnLifecycle.resolved_stop_class"
    static let vpnLifecycleInferredCrashReasonKey = "vpnLifecycle.inferred_crash_reason"
    static let transportProtectionV2StabilityFirstKey = "transportProtectionV2StabilityFirst"

    // MARK: - Retry suppression and token bucket
    static let blockSuppressionCooldown: TimeInterval = 1.5
    static let aggressiveBlockSuppressionCooldown: TimeInterval = 15.0
    static let aggressiveBlockSuppressionStormCooldown: TimeInterval = 45.0
    static let tiktokRetryTokenBucketCapacity = 2.0
    static let tiktokRetryTokenBucketRefillPerSecond = 1.0 / 12.0

    // MARK: - Reconnect breaker policy
    static let reconnectBreakerShortSessionSeconds: TimeInterval = 30.0
    static let reconnectBreakerHealthySessionResetSeconds: TimeInterval = 60.0
    static let reconnectBreakerFailureScoreThreshold = 3
    static let reconnectBreakerBaseCooldownSeconds: TimeInterval = 8.0
    static let reconnectBreakerMaxCooldownSeconds: TimeInterval = 120.0
    static let reconnectBreakerJitterFraction = 0.20
    static let lifecycleHeartbeatStaleSeconds: TimeInterval = 8.0

    // MARK: - Storm mode protection
    static let udpStormReservedSlots = 4
    static let udpStormQueueMaxAge: TimeInterval = 0.5
    static let udpMaintenanceReclaimWindowSeconds: TimeInterval = 6.0
    static let udpMaintenanceReclaimBudgetPerWindow = 1

    // MARK: - VPN
    static let vpnDescription = "Bubble Blocker"
    static let vpnServerAddress = "bubble"
}
