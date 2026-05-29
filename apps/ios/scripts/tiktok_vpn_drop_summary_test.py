#!/usr/bin/env python3
from __future__ import annotations

import json
import plistlib
import subprocess
import tempfile
import textwrap
from pathlib import Path


SCRIPT = Path(__file__).with_name("tiktok_vpn_drop_summary.py")


def write_case(
    root: Path,
    *,
    critical_seconds: int,
    disconnect_line: str | None,
    breaker_suppressed: int = 0,
    stop_cause_final: str = "",
    provider_last_phase: str = "",
    decoder_event_json: str = "",
    heartbeat_snapshot_json: str = "",
    tun2socks_exit_ts: float = 0,
) -> None:
    (root / "app_diagnostic_log.txt").write_text(
        textwrap.dedent(
            """
            [2026-05-07T10:00:00+00:00] App launched
            [2026-05-07T10:00:01+00:00] External-kill reconnect policy active delay_seconds=1.20 signature_tier=external_kill_signature_none in_flight_candidate=false
            """
        ).strip()
        + "\n"
    )
    tunnel_lines = [
        "[2026-05-07T10:00:01+00:00] SOCKS5 STATS: 20 total, 5 active, 0 errors, udpActive=6, mem=43.0MB",
        "[2026-05-07T10:00:02+00:00] EXTENSION_PRESSURE sample runtime_s=1 level=hard action=trim memory_mb=43.0 cpu_percent=2 active_udp=6 queued_udp=2 degraded_state=healthy app_lifecycle=active tun_up=10 tun_down=11",
        "[2026-05-07T10:00:03+00:00] Auto-reconnect attempt 1/6 delay=1.00s",
        "[2026-05-07T10:00:04+00:00] host=tiktokcdn-us.example.com",
    ]
    for offset in range(critical_seconds):
        tunnel_lines.append(
            f"[2026-05-07T10:00:{5+offset:02d}+00:00] EXTENSION_PRESSURE sample runtime_s={2+offset} level=critical action=critical memory_mb=43.0 cpu_percent=2 active_udp=20 queued_udp=12 degraded_state=tripped app_lifecycle=active tun_up=10 tun_down=11"
        )
    if disconnect_line:
        tunnel_lines.append(disconnect_line)
    (root / "tunnel_log.txt").write_text("\n".join(tunnel_lines) + "\n")
    (root / "traffic_stats.json").write_text(
        json.dumps(
            {
                "snapshots": [
                    {
                        "timestamp": "2026-05-07T10:00:10Z",
                        "connections": [{"host": "tiktokcdn-us.example.com", "sni": "tiktokcdn-us.example.com"}],
                        "topDomains": [{"domain": "tiktokcdn-us.example.com", "count": 10, "totalBytes": 1000}],
                        "stats": {"totalConns": 20, "udpActiveStreams": 6, "providerLastPhase": provider_last_phase},
                    }
                ],
                "events": [],
            }
        )
    )
    with (root / "app_group_prefs.plist").open("wb") as fh:
        plistlib.dump(
            {
                "vpnLifecycle.external_kill_signature": False,
                "vpnLifecycle.reconnect_suppressed_by_breaker": breaker_suppressed,
                "vpnLifecycle.external_kill_reconnect_cap_active": False,
                "vpnLifecycle.extension_pressure_memory_mb": 43.0,
                "vpnLifecycle.last_completed_stop_cause_final": stop_cause_final,
                "vpnLifecycle.provider_last_phase": provider_last_phase,
                "vpnLifecycle.provider_last_heartbeat_snapshot_json": heartbeat_snapshot_json,
                "udp_last_decoder_event_json": decoder_event_json,
                "vpnLifecycle.stop_signal_tun2socks_exit_ts": tun2socks_exit_ts,
            },
            fh,
        )
    (root / "device_TEST-DEVICE_last10m.logarchive").mkdir()
    (root / "device_TEST-DEVICE_last10m.logarchive" / "logdata.json").write_text("{}\n")
    (root / "sysdiagnose").mkdir()
    (root / "sysdiagnose" / "sysdiagnose.tar.gz").write_text("placeholder\n")
    (root / "device_crash_logs").mkdir()


def run_case(root: Path, duration: int) -> dict:
    subprocess.run(
        [
            "python3",
            str(SCRIPT),
            "--artifact-dir",
            str(root),
            "--duration",
            str(duration),
            "--started-at",
            "1778148000",
            "--ended-at",
            "1778148600",
            "--device-udid",
            "TEST-DEVICE",
            "--tiktok-bundle-id",
            "com.zhiliaoapp.musically",
        ],
        check=True,
    )
    return json.loads((root / "summary.json").read_text())


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        passing = Path(tmp) / "passing"
        passing.mkdir()
        write_case(passing, critical_seconds=2, disconnect_line=None)
        passing_summary = run_case(passing, 600)
        assert passing_summary["ten_minute_pass"] is True
        assert passing_summary["critical_pressure_max_consecutive_seconds"] == 2
        assert passing_summary["disconnect_count"] == 0
        assert passing_summary["reconnect_attempt_count"] == 1
        assert passing_summary["artifact_summary"]["ips_optional"] is True
        assert "device_logarchive" not in passing_summary["missing_artifacts"]
        assert "sysdiagnose" not in passing_summary["missing_artifacts"]

        failing = Path(tmp) / "failing"
        failing.mkdir()
        write_case(
            failing,
            critical_seconds=3,
            disconnect_line="[2026-05-07T10:00:10+00:00] status_drop_without_stop_callback",
            breaker_suppressed=1,
        )
        failing_summary = run_case(failing, 600)
        assert failing_summary["ten_minute_pass"] is False
        assert failing_summary["vpn_disconnected"] is True
        assert failing_summary["disconnect_count"] >= 1
        assert failing_summary["disconnect_classification"] == "unknown"
        assert failing_summary["critical_pressure_max_consecutive_seconds"] == 3
        assert failing_summary["reconnect_breaker_suppressed"] is True

        dns_crash = Path(tmp) / "dns_crash"
        dns_crash.mkdir()
        write_case(
            dns_crash,
            critical_seconds=0,
            disconnect_line="[2026-05-07T10:00:10+00:00] status_drop_without_stop_callback",
            stop_cause_final="status_drop_without_stop_callback",
            provider_last_phase="dns_one_shot_close",
        )
        dns_summary = run_case(dns_crash, 600)
        assert dns_summary["disconnect_classification"] == "suspected_udp_dns_close_crash"

        decoder_crash = Path(tmp) / "decoder_crash"
        decoder_crash.mkdir()
        write_case(
            decoder_crash,
            critical_seconds=0,
            disconnect_line="[2026-05-07T10:00:10+00:00] status_drop_without_stop_callback",
            stop_cause_final="status_drop_without_stop_callback",
            provider_last_phase="decoder_recovery",
            decoder_event_json='{"reason":"bad_len"}',
        )
        decoder_summary = run_case(decoder_crash, 600)
        assert decoder_summary["disconnect_classification"] == "suspected_provider_silent_exit"

        startup_guard = Path(tmp) / "startup_guard"
        startup_guard.mkdir()
        write_case(
            startup_guard,
            critical_seconds=0,
            disconnect_line="[2026-05-07T10:00:10+00:00] status_drop_without_stop_callback",
            stop_cause_final="status_drop_without_stop_callback",
            provider_last_phase="udp_accept",
            heartbeat_snapshot_json='{"active_udp":1,"queued_udp":8,"last_udp_close_phase":"grace_close_blocked","provider_phase":"udp_accept"}',
        )
        startup_guard_summary = run_case(startup_guard, 600)
        assert startup_guard_summary["disconnect_classification"] == "suspected_udp_startup_guard_saturation"

        tun_exit = Path(tmp) / "tun_exit"
        tun_exit.mkdir()
        write_case(
            tun_exit,
            critical_seconds=0,
            disconnect_line="[2026-05-07T10:00:10+00:00] tun2socks_exit",
            stop_cause_final="status_drop_without_stop_callback",
            provider_last_phase="dns_one_shot_close",
            tun2socks_exit_ts=1778148010,
        )
        tun_summary = run_case(tun_exit, 600)
        assert tun_summary["disconnect_classification"] == "tun2socks_native_exit"
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
