import Foundation

enum NimaConstants {
    // MARK: - Identifiers
    static let appGroupID = "group.so.nima.app"
    static let tunnelBundleID = "so.nima.app.NimaTunnel"
    static let instagramFamilySelectionKey = "instagram.client.family_selection"
    static let instagramShieldPendingDestinationKey = "instagram.shield.pending_destination"
    static let instagramProtectionEnabledKey = "instagram.client.protection_enabled"
    static let tiktokFamilySelectionKey = "tiktok.client.family_selection"
    static let tiktokProtectionEnabledKey = "tiktok.client.protection_enabled"
    static let xFamilySelectionKey = "x.client.family_selection"
    static let xProtectionEnabledKey = "x.client.protection_enabled"
    static let shieldPendingDestinationKey = "shield.pending_destination"
    static let screenTimeAppConnectionsKey = "screen_time.app_connections"

    // MARK: - Network Settings
    static let tunnelRemoteAddress = "198.18.0.1"
    static let tunnelLocalAddress = "198.18.0.2"
    static let tunnelSubnetMask = "255.255.255.0"
    static let dnsServers = ["8.8.8.8", "1.1.1.1"]
    static let mtu: NSNumber = 1500

    // MARK: - tun2socks Configuration
    static let tun2socksTaskStackSize = 65536
    static let tun2socksTCPBufferSize = 4096
    static let tun2socksConnectTimeout = 5000
    static let tun2socksReadWriteTimeout = 60000
    static let tun2socksPostConnectLaunchDelaySeconds: TimeInterval = 1.0
    static let tun2socksStartupModeStagedAfterConnect = "staged_after_connect"
    static let tun2socksStartupModeBypassDiagnostic = "bypass_tun2socks_diagnostic"

    // MARK: - SOCKS5 Proxy
    static let socksBindAddress = "127.0.0.1"
    static let maxUDPFrameSize = 9000
    static let relayBufferSize = 65536
    static let udpRelayTimeout: TimeInterval = 5.0
    static let tcpRelayTimeout: TimeInterval = 120.0
    static let maxConnections = 500
    static let statsInterval: TimeInterval = 10.0
    static let safeModeMaxActiveUDPControlStreams = 12
    static let safeModeMaxQueuedUDPControlStreams = 8

    // MARK: - Logging
    static let appLogFileName = "app_diagnostic_log.txt"
    static let logFileName = "tunnel_log.txt"
    static let maxLogSizeBytes = 512 * 1024
    static let maxStatusLogEntries = 200
    static let logSubsystem = "so.nima.app.NimaTunnel"
    static let statsFileName = "traffic_stats.json"
    static let onDemandRolloutFlagCacheKey = "vpnLifecycle.on_demand_rollout_flag_cache"
    static let onDemandRolloutFlagFetchedAtKey = "vpnLifecycle.on_demand_rollout_flag_fetched_at"
    static let onDemandInstallationIDKey = "vpnLifecycle.on_demand_installation_id"
    static let onDemandRolloutEligibleKey = "vpnLifecycle.on_demand_rollout_eligible"
    static let onDemandDesiredKey = "vpnLifecycle.on_demand_desired"
    static let onDemandActualKey = "vpnLifecycle.on_demand_actual"
    static let onDemandRuleCountKey = "vpnLifecycle.on_demand_rule_count"
    static let onDemandInterfaceKey = "vpnLifecycle.on_demand_interface"
    static let onDemandLastProfileRevisionKey = "vpnLifecycle.on_demand_last_profile_revision"
    static let onDemandLastProfileResultKey = "vpnLifecycle.on_demand_last_profile_result"
    static let onDemandLastProfileErrorKey = "vpnLifecycle.on_demand_last_profile_error"
    static let onDemandDisableBeforeStopVerifiedKey = "vpnLifecycle.on_demand_disable_before_stop_verified"
    static let onDemandExplicitStartTSKey = "vpnLifecycle.on_demand_explicit_start_ts"
    static let onDemandInferredRecoveryCountKey = "vpnLifecycle.on_demand_inferred_recovery_count"
    static let onDemandInferredRecoveryDurationKey = "vpnLifecycle.on_demand_inferred_recovery_duration"
    static let previousSessionSnapshotJSONKey = "vpnLifecycle.previous_session_json"
    static let vpnProfileCleanupPendingKey = "vpnLifecycle.profile_cleanup_pending"
    static let vpnProfileRemovalPendingStandardKey = "vpnLifecycle.profile_removal_pending_after_account_deletion"

    // MARK: - Stream Blocking
    static let streamBlockDefaultThreshold = 512 * 1024  // 0.5 MB

    // MARK: - UserDefaults Keys
    static let strictUDPBlockEnabledKey = "strictUDPBlockEnabled"
    static let udpForwardingDisabledKey = "udpForwardingDisabled"
    static let udpDisabledFastRejectEnabledKey = "udpDisabledFastRejectEnabled"
    static let udpSelectiveSafeModeEnabledKey = "udpSelectiveSafeModeEnabled"
    static let udpSelectiveSafeModeMigratedKey = "udpSelectiveSafeModeMigrated"
    static let udpForwardingDefaultV2MigratedKey = "udpForwardingDefaultV2Migrated"
    static let tun2socksStartupModeKey = "vpnLifecycle.tun2socks_startup_mode"
    static let transportProtectionV2StabilityFirstKey = "transportProtectionV2StabilityFirst"
    static let transportProtectionV2StabilityFirstDefaultMigratedKey = "transportProtectionV2StabilityFirstDefaultMigrated"
    static let featurePolicyKey = "featurePolicyV1"
    static let manualFeaturePolicyKey = "manualFeaturePolicyV1"
    static let streakDaysKey = "streakDaysV1"
    static let displayNameKey = "settings.display_name"
    static let windowsNotificationsEnabledKey = "settings.windows_notifications_enabled"
    static let streakRemindersEnabledKey = "settings.streak_reminders_enabled"
    static let streakReminderHourKey = "settings.streak_reminder_hour"
    static let streakReminderMinuteKey = "settings.streak_reminder_minute"
    static let pauseIntervalMinutesKey = "settings.pause_interval_minutes"
    static let pauseModeAppIDsKey = "pause_mode.app_ids"
    static let pauseModeExpiresAtKey = "pause_mode.expires_at"
    static let pauseModeWindowIDsKey = "pause_mode.window_ids"
    static let paywallBlockingSuspendedKey = "blocking.paywall_suspended"
    static let hardModeEnabledKey = "hard_mode.enabled"
    static let hardModeOffAppIDsKey = "hard_mode.off_app_ids"
    static let hardModePauseExpiriesKey = "hard_mode.pause_expiries"
    static let hardModePauseRuleExpiriesKey = "hard_mode.pause_rule_expiries"
    static let onboardingStateKey = "onboardingStateV1"
    static let onboardingCompletedKey = "onboardingCompletedV1"
    static let guidedOnboardingSeenKey = "guidedOnboardingSeenV1"
    static let guidedPracticeCompletedKey = "guidedPracticeCompletedV1"
    static let guidedPracticeReturnPendingKey = "guidedPracticeReturnPendingV1"
    static let guidedPracticeStepKey = "guidedPracticeStepV1"
    static let guidedPracticeIntroSlideIndexKey = "guidedPracticeIntroSlideIndexV1"
    static let guidedPracticeSelectedAppIDsKey = "guidedPracticeSelectedAppIDsV1"
    static let guidedPracticeFamilySelectionKey = "guidedPracticeFamilySelectionV1"
    static let guidedPracticeAppConnectionsKey = "guidedPracticeAppConnectionsV1"
    static let guidedWindowsDraftKey = "guidedWindowsDraftV1"
    static let guidedWindowsOnboardingCompletedKey = "guidedWindowsOnboardingCompletedV1"
    static let guidedPracticeReviewPromptedUserIDsKey = "guidedPracticeReviewPromptedUserIDsV1"
    static let instagramLoginIntroSeenKey = "instagramLoginIntroSeenV1"
    static let xLoginIntroSeenKey = "xLoginIntroSeenV1"
    static let timeWindowsKey = "timeWindowsV1"
    static let timeWindowsPauseAllKey = "timeWindows.pause_all"
    static let timeWindowsPauseExpiresAtKey = "timeWindows.pause_expires_at"
    static let timeWindowsEndedUntilKey = "timeWindows.ended_until"
    static let legacyTimeWindowOccurrenceDecisionsKey = "timeWindows.occurrence_decisions_v1"
    static let scheduleDesiredVPNOnKey = "schedule.desired_vpn_on"
    static let scheduleDesiredReasonKey = "schedule.desired_reason"
    static let scheduleDesiredSourceKey = "schedule.desired_source"
    static let scheduleDesiredUntilTSKey = "schedule.desired_until_ts"
    static let scheduleActiveAppIDsKey = "schedule.active_app_ids"
    static let scheduleActiveWindowIDsKey = "schedule.active_window_ids"
    static let scheduleManualOffUntilTSKey = "schedule.manual_off_until_ts"
    static let scheduleLastInterruptionTSKey = "schedule.last_interruption_ts"
    static let scheduleLastRepairResultKey = "schedule.last_repair_result"
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
    static let vpnLifecyclePendingStopIDKey = "vpnLifecycle.pending_stop_id"
    static let vpnLifecyclePendingStopSourceKey = "vpnLifecycle.pending_stop_source"
    static let vpnLifecyclePendingStopTSKey = "vpnLifecycle.pending_stop_ts"
    static let vpnLifecycleLastStopObservedPendingIDKey = "vpnLifecycle.last_stop_observed_pending_id"
    static let vpnLifecycleLastStopOriginKey = "vpnLifecycle.last_stop_origin"
    static let vpnLifecycleSessionIDKey = "vpnLifecycle.session_id"
    static let vpnLifecycleStopEventIDKey = "vpnLifecycle.stop_event_id"
    static let vpnLifecycleStopEventStartTSKey = "vpnLifecycle.stop_event_start_ts"
    static let vpnLifecycleStopCauseFinalKey = "vpnLifecycle.stop_cause_final"
    static let vpnLifecycleStopCauseConfidenceKey = "vpnLifecycle.stop_cause_confidence"
    static let vpnLifecycleStopCauseEvidenceKey = "vpnLifecycle.stop_cause_evidence"
    static let vpnLifecycleStopCauseSignalOrderKey = "vpnLifecycle.stop_signal_order"
    static let vpnLifecycleStopCauseFinalizedTSKey = "vpnLifecycle.stop_cause_finalized_ts"
    static let vpnLifecycleStopSignalAppRequestedTSKey = "vpnLifecycle.stop_signal_app_requested_ts"
    static let vpnLifecycleStopSignalOSStopTSKey = "vpnLifecycle.stop_signal_os_stop_ts"
    static let vpnLifecycleStopSignalOSStopReasonRawKey = "vpnLifecycle.stop_signal_os_stop_reason_raw"
    static let vpnLifecycleStopSignalOSStopReasonNameKey = "vpnLifecycle.stop_signal_os_stop_reason_name"
    static let vpnLifecycleStopSignalTun2SocksExitTSKey = "vpnLifecycle.stop_signal_tun2socks_exit_ts"
    static let vpnLifecycleStopSignalTun2SocksExitCodeKey = "vpnLifecycle.stop_signal_tun2socks_exit_code"
    static let vpnLifecycleStopSignalProviderDeinitTSKey = "vpnLifecycle.stop_signal_provider_deinit_ts"
    static let vpnLifecycleStopSignalStatusDropTSKey = "vpnLifecycle.stop_signal_status_drop_ts"
    static let vpnLifecycleLastCompletedStopEventIDKey = "vpnLifecycle.last_completed_stop_event_id"
    static let vpnLifecycleLastCompletedStopCauseFinalKey = "vpnLifecycle.last_completed_stop_cause_final"
    static let vpnLifecycleLastCompletedStopCauseConfidenceKey = "vpnLifecycle.last_completed_stop_cause_confidence"
    static let vpnLifecycleLastCompletedStopCauseEvidenceKey = "vpnLifecycle.last_completed_stop_cause_evidence"
    static let vpnLifecycleLastCompletedStopSignalOrderKey = "vpnLifecycle.last_completed_stop_signal_order"
    static let vpnLifecycleLastCompletedStopFinalizedTSKey = "vpnLifecycle.last_completed_stop_finalized_ts"
    static let vpnLifecycleLastCompletedStopSeqKey = "vpnLifecycle.last_completed_stop_seq"
    static let vpnLifecycleDiagnosticHoldEnabledKey = "vpnLifecycle.diagnostic_hold_enabled"
    static let vpnLifecycleDiagnosticHoldSecondsKey = "vpnLifecycle.diagnostic_hold_seconds"
    static let vpnLifecycleDiagnosticProfileEnabledKey = "vpnLifecycle.diagnostic_profile_enabled"
    static let vpnLifecycleDiagnosticModeSourceKey = "vpnLifecycle.diagnostic_mode_source"
    static let vpnLifecycleDiagnosticAutoEnabledUntilTSKey = "vpnLifecycle.diagnostic_auto_enabled_until_ts"
    static let vpnLifecycleDropLoopCountKey = "vpnLifecycle.drop_loop_count"
    static let vpnLifecycleDropLoopWindowStartTSKey = "vpnLifecycle.drop_loop_window_start_ts"
    static let vpnLifecycleDiagnosticCompletenessKey = "vpnLifecycle.diagnostic_complete"
    static let vpnLifecycleRemediationPathKey = "vpnLifecycle.remediation_path"
    static let vpnLifecycleNextActionKey = "vpnLifecycle.next_action"
    static let vpnLifecycleDropBoundaryAppStateKey = "vpnLifecycle.drop_boundary_app_state"
    static let vpnLifecycleDropBoundaryLockSleepHintKey = "vpnLifecycle.drop_boundary_lock_sleep_hint"
    static let vpnLifecycleDropBoundaryTSKey = "vpnLifecycle.drop_boundary_ts"
    static let vpnLifecycleDropBoundaryLifecycleEventKey = "vpnLifecycle.drop_boundary_lifecycle_event"
    static let vpnLifecycleDropBoundaryProtectedDataAvailableKey = "vpnLifecycle.drop_boundary_protected_data_available"
    static let vpnLifecycleDropBoundaryThermalStateKey = "vpnLifecycle.drop_boundary_thermal_state"
    static let vpnLifecycleDropBoundaryMemoryWarningAgeSecondsKey = "vpnLifecycle.drop_boundary_memory_warning_age_seconds"
    static let vpnLifecycleDropBoundaryProfileOpDeltaMSKey = "vpnLifecycle.drop_boundary_profile_op_delta_ms"
    static let vpnLifecycleStopTerminalSeenStopTunnelTSKey = "vpnLifecycle.stop_terminal_seen_stop_tunnel_ts"
    static let vpnLifecycleStopTerminalSeenTun2SocksExitTSKey = "vpnLifecycle.stop_terminal_seen_tun2socks_exit_ts"
    static let vpnLifecycleStopTerminalSeenProviderDeinitTSKey = "vpnLifecycle.stop_terminal_seen_provider_deinit_ts"
    static let vpnLifecycleProfileLoadAllTSKey = "vpnLifecycle.profile_load_all_ts"
    static let vpnLifecycleProfileLoadTSKey = "vpnLifecycle.profile_load_ts"
    static let vpnLifecycleProfileSaveTSKey = "vpnLifecycle.profile_save_ts"
    static let vpnLifecycleProfileReloadTSKey = "vpnLifecycle.profile_reload_ts"
    static let vpnLifecycleProfileConfigSignatureKey = "vpnLifecycle.profile_config_signature"
    static let vpnLifecycleAppStateKey = "vpnLifecycle.app_state"
    static let vpnLifecycleAppLifecycleLastEventKey = "vpnLifecycle.app_lifecycle_last_event"
    static let vpnLifecycleAppLifecycleLastEventTSKey = "vpnLifecycle.app_lifecycle_last_event_ts"
    static let vpnLifecycleLastBreadcrumbKey = "vpnLifecycle.last_breadcrumb"
    static let vpnLifecycleLastBreadcrumbTSKey = "vpnLifecycle.last_breadcrumb_ts"
    static let vpnLifecycleLastBreadcrumbDetailsKey = "vpnLifecycle.last_breadcrumb_details"
    static let vpnLifecycleProviderLastPhaseKey = "vpnLifecycle.provider_last_phase"
    static let vpnLifecycleProviderLastPhaseTSKey = "vpnLifecycle.provider_last_phase_ts"
    static let vpnLifecycleProviderHeartbeatSnapshotJSONKey = "vpnLifecycle.provider_last_heartbeat_snapshot_json"
    static let providerPhaseRingJSONKey = "provider_phase_ring_json"
    static let udpLastControlStreamJSONKey = "udp_last_control_stream_json"
    static let udpLastDNSCloseJSONKey = "udp_last_dns_close_json"
    static let udpLastDecoderEventJSONKey = "udp_last_decoder_event_json"
    static let tun2socksLastStatsJSONKey = "tun2socks_last_stats_json"
    static let udpCrashGuardUntilKey = "udp_crash_guard_until"
    static let udpCrashGuardReasonKey = "udp_crash_guard_reason"
    static let udpCrashGuardHitsKey = "udp_crash_guard_hits"
    static let vpnLifecycleAppLastActiveTSKey = "vpnLifecycle.app_last_active_ts"
    static let vpnLifecycleAppLastInactiveTSKey = "vpnLifecycle.app_last_inactive_ts"
    static let vpnLifecycleAppLastBackgroundTSKey = "vpnLifecycle.app_last_background_ts"
    static let vpnLifecycleAppLastForegroundTSKey = "vpnLifecycle.app_last_foreground_ts"
    static let vpnLifecycleProtectedDataAvailableKey = "vpnLifecycle.protected_data_available"
    static let vpnLifecycleProtectedDataAvailableTSKey = "vpnLifecycle.protected_data_available_ts"
    static let vpnLifecycleProtectedDataUnavailableTSKey = "vpnLifecycle.protected_data_unavailable_ts"
    static let vpnLifecycleAppMemoryWarningTSKey = "vpnLifecycle.app_memory_warning_ts"
    static let vpnLifecycleAppThermalStateKey = "vpnLifecycle.app_thermal_state"
    static let vpnLifecycleAppThermalStateTSKey = "vpnLifecycle.app_thermal_state_ts"
    static let vpnLifecycleStatusDropHistoryTSKey = "vpnLifecycle.status_drop_history_ts"
    static let vpnLifecycleExternalKillSignatureKey = "vpnLifecycle.external_kill_signature"
    static let vpnLifecycleExternalKillSignatureTierKey = "vpnLifecycle.external_kill_signature_tier"
    static let vpnLifecycleExternalKillDetectedTSKey = "vpnLifecycle.external_kill_detected_ts"
    static let vpnLifecycleExternalKillCadenceSecondsKey = "vpnLifecycle.external_kill_cadence_seconds"
    static let vpnLifecycleExternalKillDropCadenceWindowCountKey = "vpnLifecycle.external_kill_drop_cadence_window_count"
    static let vpnLifecycleExternalKillHeartbeatStaleSecondsAtDropKey = "vpnLifecycle.external_kill_heartbeat_stale_seconds_at_drop"
    static let vpnLifecycleExternalKillReclaimBlockedCountLastWindowKey = "vpnLifecycle.external_kill_reclaim_blocked_count_last_window"
    static let vpnLifecycleExternalKillPressureCriticalDurationSecondsKey = "vpnLifecycle.external_kill_pressure_critical_duration_seconds"
    static let vpnLifecycleExternalKillReconnectAttemptTSKey = "vpnLifecycle.external_kill_reconnect_attempt_ts"
    static let vpnLifecycleExternalKillReconnectAttemptsInWindowKey = "vpnLifecycle.external_kill_reconnect_attempts_in_window"
    static let vpnLifecycleExternalKillReconnectCapActiveKey = "vpnLifecycle.external_kill_reconnect_cap_active"
    static let vpnLifecycleExternalKillReconnectNextAllowedTSKey = "vpnLifecycle.external_kill_reconnect_next_allowed_ts"
    static let vpnLifecycleExternalKillReconnectSuppressionStateKey = "vpnLifecycle.external_kill_reconnect_suppression_state"
    static let vpnLifecycleLastReconnectDelaySecondsKey = "vpnLifecycle.last_reconnect_delay_seconds"
    static let vpnLifecycleDiagnosticHoldElapsedMSKey = "vpnLifecycle.diagnostic_hold_elapsed_ms"
    static let vpnLifecycleDiagnosticHoldCompletedKey = "vpnLifecycle.diagnostic_hold_completed"
    static let vpnLifecycleExtensionPressureLastSampleTSKey = "vpnLifecycle.extension_pressure_last_sample_ts"
    static let vpnLifecycleExtensionPressureRuntimeSecondsKey = "vpnLifecycle.extension_pressure_runtime_seconds"
    static let vpnLifecycleExtensionPressureLevelKey = "vpnLifecycle.extension_pressure_level"
    static let vpnLifecycleExtensionPressureMemoryMBKey = "vpnLifecycle.extension_pressure_memory_mb"
    static let vpnLifecycleExtensionPressureCPUPercentKey = "vpnLifecycle.extension_pressure_cpu_percent"
    static let vpnLifecycleExtensionPressureUDPActiveKey = "vpnLifecycle.extension_pressure_udp_active"
    static let vpnLifecycleExtensionPressureUDPQueuedKey = "vpnLifecycle.extension_pressure_udp_queued"
    static let vpnLifecycleExtensionPressureDegradedStateKey = "vpnLifecycle.extension_pressure_degraded_state"
    static let vpnLifecycleExtensionPressureActionKey = "vpnLifecycle.extension_pressure_action"
    static let vpnLifecycleExtensionPressureTun2SocksUpPacketsKey = "vpnLifecycle.extension_pressure_tun2socks_up_packets"
    static let vpnLifecycleExtensionPressureTun2SocksDownPacketsKey = "vpnLifecycle.extension_pressure_tun2socks_down_packets"
    static let vpnLifecycleExtensionPressureAppLifecycleKey = "vpnLifecycle.extension_pressure_app_lifecycle"
    static let vpnLifecycleExtensionPressureReclaimBlockedCountKey = "vpnLifecycle.extension_pressure_reclaim_blocked_count"
    static let vpnLifecycleStartupStabilityPhaseKey = "vpnLifecycle.startup_stability_phase"
    static let vpnLifecycleStartupProbeCompletedKey = "vpnLifecycle.startup_probe_completed"
    static let vpnLifecycleStartupProbeCompletedTSKey = "vpnLifecycle.startup_probe_completed_ts"
    static let vpnLifecycleTransportReadyKey = "vpnLifecycle.transport_ready"
    static let vpnLifecycleTransportReadyTSKey = "vpnLifecycle.transport_ready_ts"
    static let vpnLifecycleDNSStartupDrainActiveKey = "vpnLifecycle.dns_startup_drain_active"
    static let vpnLifecycleDNSStartupDrainClosesKey = "vpnLifecycle.dns_startup_drain_closes"
    static let vpnLifecycleDNSStartupDrainFramesProcessedKey = "vpnLifecycle.dns_startup_drain_frames_processed"
    static let vpnLifecycleEarlyReconnectSuppressedKey = "vpnLifecycle.early_reconnect_suppressed"
    static let vpnLifecycleIOSSafeModeReasonKey = "vpnLifecycle.ios_safe_mode_reason"
    static let vpnLifecycleAttributionWindowSeconds: TimeInterval = 1.5
    static let vpnLifecycleDiagnosticHoldDefaultSeconds: TimeInterval = 5.0
    static let vpnLifecycleDiagnosticAutoEnableWindowSeconds: TimeInterval = 300.0
    static let vpnLifecycleDiagnosticAutoEnableMinDrops = 3
    static let vpnLifecyclePolicyReconcileDebounceSeconds: TimeInterval = 2.0
    static let vpnLifecycleExternalKillCadenceMinSeconds: TimeInterval = 20.0
    static let vpnLifecycleExternalKillCadenceMaxSeconds: TimeInterval = 240.0
    static let vpnLifecycleExternalKillDropHistoryWindowSeconds: TimeInterval = 300.0
    static let vpnLifecycleExternalKillMinDropCountForSupportSignal = 2
    static let vpnLifecycleExternalKillStaleHeartbeatSeconds: TimeInterval = 20.0
    static let vpnLifecycleExternalKillSupportSignalWindowSeconds: TimeInterval = 300.0
    static let vpnLifecycleExternalKillReconnectMinDelaySeconds: TimeInterval = 30.0
    static let vpnLifecycleExternalKillReconnectMaxDelaySeconds: TimeInterval = 60.0
    static let vpnLifecycleExternalKillReconnectWindowSeconds: TimeInterval = 300.0
    static let vpnLifecycleExternalKillReconnectMaxAttemptsPerWindow = 2
    static let vpnLifecycleStartupProbeDelaySeconds: TimeInterval = 1.0
    static let extensionPressureSamplerStartSeconds: TimeInterval = 1.0

    // MARK: - Reconnect breaker
    static let reconnectBreakerShortSessionSeconds: TimeInterval = 15.0
    static let reconnectBreakerHealthySessionResetSeconds: TimeInterval = 60.0
    static let reconnectBreakerFailureScoreThreshold = 4
    static let reconnectBreakerShortUnknownDropThreshold = 2
    static let reconnectBreakerShortUnknownDropWindowSeconds: TimeInterval = 120.0
    static let reconnectBreakerMinCooldownSeconds: TimeInterval = 30.0
    static let reconnectBreakerBaseCooldownSeconds: TimeInterval = 30.0
    static let reconnectBreakerMaxCooldownSeconds: TimeInterval = 60.0
    static let reconnectBreakerJitterFraction = 0.20
    static let lifecycleHeartbeatStaleSeconds: TimeInterval = 8.0
    static let transportProbeReconnectDelaySeconds: Double = 1.0
    static let transportProbeReconnectMinIntervalSeconds: TimeInterval = 30.0
    static let autoReconnectFastPathMaxDelaySeconds: TimeInterval = 4.0
    static let udpStartupSerialModeSeconds: TimeInterval = 3.0
    static let udpStartupSerialMaxActiveStreams = 2
    static let udpCrashGuardSerialModeSeconds: TimeInterval = 30.0
    static let udpDNSResponseCancelWatchdogDelaySeconds: TimeInterval = 0.35
    static let udpDNSDeferredCancelDelaySeconds: TimeInterval = 0.05
    static let dnsStartupDrainWindowSeconds: TimeInterval = 5.0
    static let dnsStartupDrainIdleSeconds: TimeInterval = 0.20
    static let dnsStartupDrainMaxAgeSeconds: TimeInterval = 1.25

    // MARK: - VPN
    static let vpnDescription = "Nima Blocker"
    static let vpnServerAddress = "nima"
}

enum PauseModeState {
    static func pausedAppIDs(defaults: UserDefaults?, now: Date = Date()) -> Set<String> {
        guard let expiresAt = defaults?.object(forKey: NimaConstants.pauseModeExpiresAtKey) as? Date,
              expiresAt > now else { return [] }
        return Set(defaults?.stringArray(forKey: NimaConstants.pauseModeAppIDsKey) ?? [])
    }

    static func isPaused(_ appID: String, defaults: UserDefaults?, now: Date = Date()) -> Bool {
        pausedAppIDs(defaults: defaults, now: now).contains(appID)
    }

    static func start(appIDs: Set<String>, windowIDs: Set<String> = [], minutes: Int, defaults: UserDefaults?, now: Date = Date()) -> Date? {
        guard !appIDs.isEmpty, [5, 10, 15].contains(minutes), let defaults else { return nil }
        let expiresAt = now.addingTimeInterval(TimeInterval(minutes * 60))
        defaults.set(appIDs.sorted(), forKey: NimaConstants.pauseModeAppIDsKey)
        defaults.set(windowIDs.sorted(), forKey: NimaConstants.pauseModeWindowIDsKey)
        defaults.set(expiresAt, forKey: NimaConstants.pauseModeExpiresAtKey)
        return expiresAt
    }

    static func exclude(_ appID: String, defaults: UserDefaults?, now: Date = Date()) {
        var appIDs = pausedAppIDs(defaults: defaults, now: now)
        guard appIDs.remove(appID) != nil else { return }
        defaults?.set(appIDs.sorted(), forKey: NimaConstants.pauseModeAppIDsKey)
    }

    static func clear(defaults: UserDefaults?) {
        defaults?.removeObject(forKey: NimaConstants.pauseModeAppIDsKey)
        defaults?.removeObject(forKey: NimaConstants.pauseModeWindowIDsKey)
        defaults?.removeObject(forKey: NimaConstants.pauseModeExpiresAtKey)
    }
}

enum HardModeProtectionState {
    static func isEnabled(defaults: UserDefaults?) -> Bool {
        defaults?.bool(forKey: NimaConstants.hardModeEnabledKey) ?? false
    }

    static func setEnabled(_ enabled: Bool, defaults: UserDefaults?) {
        defaults?.set(enabled, forKey: NimaConstants.hardModeEnabledKey)
    }

    static func isScheduleSuppressed(_ appID: String, defaults: UserDefaults?) -> Bool {
        Set(defaults?.stringArray(forKey: NimaConstants.hardModeOffAppIDsKey) ?? []).contains(appID)
    }

    static func markProtectionOn(_ appID: String, defaults: UserDefaults?, now: Date = Date()) {
        var offAppIDs = offOverrideAppIDs(defaults: defaults)
        offAppIDs.remove(appID)
        persistOffOverrideAppIDs(offAppIDs, defaults: defaults)
        clearPause(for: appID, defaults: defaults, now: now)
    }

    static func markProtectionOff(_ appID: String, defaults: UserDefaults?) {
        var offAppIDs = offOverrideAppIDs(defaults: defaults)
        offAppIDs.insert(appID)
        persistOffOverrideAppIDs(offAppIDs, defaults: defaults)
    }

    static func effectivelyScheduled(
        _ appID: String,
        scheduled: Bool,
        defaults: UserDefaults?
    ) -> Bool {
        scheduled && !isScheduleSuppressed(appID, defaults: defaults)
    }

    @discardableResult
    static func pause(
        appIDs: Set<String>,
        ruleIDs: Set<String> = [],
        minutes: Int,
        defaults: UserDefaults?,
        now: Date = Date()
    ) -> Date? {
        guard !appIDs.isEmpty || !ruleIDs.isEmpty,
              [5, 10, 15].contains(minutes),
              let defaults else { return nil }
        let expiry = now.addingTimeInterval(TimeInterval(minutes * 60))
        var appExpiries = pauseExpiries(defaults: defaults, now: now)
        var ruleExpiries = pauseRuleExpiries(defaults: defaults, now: now)
        for appID in appIDs {
            appExpiries[appID] = expiry
        }
        for ruleID in ruleIDs {
            ruleExpiries[ruleID] = expiry
        }
        persistPauseExpiries(appExpiries, ruleExpiries: ruleExpiries, defaults: defaults)
        return expiry
    }

    static func isPaused(_ appID: String, defaults: UserDefaults?, now: Date = Date()) -> Bool {
        pauseExpiries(defaults: defaults, now: now)[appID] != nil
    }

    static func isRulePaused(_ ruleID: String, defaults: UserDefaults?, now: Date = Date()) -> Bool {
        pauseRuleExpiries(defaults: defaults, now: now)[ruleID] != nil
    }

    static func pausedUntil(_ appID: String, defaults: UserDefaults?, now: Date = Date()) -> Date? {
        pauseExpiries(defaults: defaults, now: now)[appID]
    }

    static func nextPauseExpiry(defaults: UserDefaults?, now: Date = Date()) -> Date? {
        let appDates = pauseExpiries(defaults: defaults, now: now).values
        let ruleDates = pauseRuleExpiries(defaults: defaults, now: now).values
        return (Array(appDates) + Array(ruleDates)).min()
    }

    static func purgeExpiredPauses(defaults: UserDefaults?, now: Date = Date()) {
        guard let defaults else { return }
        let currentApps = pauseExpiries(defaults: defaults, now: now)
        let currentRules = pauseRuleExpiries(defaults: defaults, now: now)
        let storedApps = appPauseTimestamps(defaults: defaults)
        let storedRules = rulePauseTimestamps(defaults: defaults)
        if storedApps.count != currentApps.count || storedRules.count != currentRules.count {
            persistPauseExpiries(currentApps, ruleExpiries: currentRules, defaults: defaults)
        }
    }

    static func clearPause(for appID: String, defaults: UserDefaults?, now: Date = Date()) {
        var appExpiries = pauseExpiries(defaults: defaults, now: now)
        guard appExpiries.removeValue(forKey: appID) != nil else { return }
        persistPauseExpiries(
            appExpiries,
            ruleExpiries: pauseRuleExpiries(defaults: defaults, now: now),
            defaults: defaults
        )
    }

    static func removePauses(
        appIDs: Set<String>,
        ruleIDs: Set<String>,
        defaults: UserDefaults?,
        now: Date = Date()
    ) {
        var appExpiries = pauseExpiries(defaults: defaults, now: now)
        var ruleExpiries = pauseRuleExpiries(defaults: defaults, now: now)
        for appID in appIDs {
            appExpiries.removeValue(forKey: appID)
        }
        for ruleID in ruleIDs {
            ruleExpiries.removeValue(forKey: ruleID)
        }
        persistPauseExpiries(appExpiries, ruleExpiries: ruleExpiries, defaults: defaults)
    }

    static func reset(defaults: UserDefaults?) {
        defaults?.removeObject(forKey: NimaConstants.hardModeEnabledKey)
        defaults?.removeObject(forKey: NimaConstants.hardModeOffAppIDsKey)
        defaults?.removeObject(forKey: NimaConstants.hardModePauseExpiriesKey)
        defaults?.removeObject(forKey: NimaConstants.hardModePauseRuleExpiriesKey)
    }

    private static func offOverrideAppIDs(defaults: UserDefaults?) -> Set<String> {
        Set(defaults?.stringArray(forKey: NimaConstants.hardModeOffAppIDsKey) ?? [])
    }

    private static func persistOffOverrideAppIDs(_ appIDs: Set<String>, defaults: UserDefaults?) {
        if appIDs.isEmpty {
            defaults?.removeObject(forKey: NimaConstants.hardModeOffAppIDsKey)
        } else {
            defaults?.set(appIDs.sorted(), forKey: NimaConstants.hardModeOffAppIDsKey)
        }
    }

    private static func appPauseTimestamps(defaults: UserDefaults?) -> [String: TimeInterval] {
        defaults?.dictionary(forKey: NimaConstants.hardModePauseExpiriesKey) as? [String: TimeInterval] ?? [:]
    }

    private static func rulePauseTimestamps(defaults: UserDefaults?) -> [String: TimeInterval] {
        defaults?.dictionary(forKey: NimaConstants.hardModePauseRuleExpiriesKey) as? [String: TimeInterval] ?? [:]
    }

    private static func pauseExpiries(defaults: UserDefaults?, now: Date) -> [String: Date] {
        appPauseTimestamps(defaults: defaults).reduce(into: [:]) { result, item in
            let date = Date(timeIntervalSince1970: item.value)
            if date > now {
                result[item.key] = date
            }
        }
    }

    private static func pauseRuleExpiries(defaults: UserDefaults?, now: Date) -> [String: Date] {
        rulePauseTimestamps(defaults: defaults).reduce(into: [:]) { result, item in
            let date = Date(timeIntervalSince1970: item.value)
            if date > now {
                result[item.key] = date
            }
        }
    }

    private static func persistPauseExpiries(
        _ appExpiries: [String: Date],
        ruleExpiries: [String: Date],
        defaults: UserDefaults?
    ) {
        let appTimestamps = appExpiries.reduce(into: [String: TimeInterval]()) {
            $0[$1.key] = $1.value.timeIntervalSince1970
        }
        let ruleTimestamps = ruleExpiries.reduce(into: [String: TimeInterval]()) {
            $0[$1.key] = $1.value.timeIntervalSince1970
        }
        if appTimestamps.isEmpty {
            defaults?.removeObject(forKey: NimaConstants.hardModePauseExpiriesKey)
        } else {
            defaults?.set(appTimestamps, forKey: NimaConstants.hardModePauseExpiriesKey)
        }
        if ruleTimestamps.isEmpty {
            defaults?.removeObject(forKey: NimaConstants.hardModePauseRuleExpiriesKey)
        } else {
            defaults?.set(ruleTimestamps, forKey: NimaConstants.hardModePauseRuleExpiriesKey)
        }
    }
}
