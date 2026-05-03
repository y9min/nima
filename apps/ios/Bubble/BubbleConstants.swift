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
    static let maxUDPFrameSize = 9000
    static let relayBufferSize = 65536
    static let udpRelayTimeout: TimeInterval = 5.0
    static let tcpRelayTimeout: TimeInterval = 120.0
    static let maxConnections = 500
    static let statsInterval: TimeInterval = 10.0

    // MARK: - Logging
    static let appLogFileName = "app_diagnostic_log.txt"
    static let logFileName = "tunnel_log.txt"
    static let maxLogSizeBytes = 512 * 1024
    static let maxStatusLogEntries = 200
    static let logSubsystem = "com.yamin.nimademo.BubbleTunnel"
    static let statsFileName = "traffic_stats.json"

    // MARK: - Stream Blocking
    static let streamBlockDefaultThreshold = 512 * 1024  // 0.5 MB

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
    static let vpnLifecycleTransportDegradedKey = "vpnLifecycle.transport_degraded"
    static let vpnLifecycleTransportDegradedReasonKey = "vpnLifecycle.transport_degraded_reason"
    static let vpnLifecycleTransportDegradedTSKey = "vpnLifecycle.transport_degraded_ts"

    // MARK: - Reconnect breaker
    static let reconnectBreakerShortSessionSeconds: TimeInterval = 30.0
    static let reconnectBreakerHealthySessionResetSeconds: TimeInterval = 60.0
    static let reconnectBreakerFailureScoreThreshold = 3
    static let reconnectBreakerBaseCooldownSeconds: TimeInterval = 8.0
    static let reconnectBreakerMaxCooldownSeconds: TimeInterval = 120.0
    static let reconnectBreakerJitterFraction = 0.20
    static let lifecycleHeartbeatStaleSeconds: TimeInterval = 8.0
    static let transportProbeReconnectDelaySeconds: Double = 8.0
    static let transportProbeReconnectMinIntervalSeconds: TimeInterval = 30.0

    // MARK: - VPN
    static let vpnDescription = "Bubble Blocker"
    static let vpnServerAddress = "bubble"
}
