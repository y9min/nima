#!/usr/bin/env python3
"""Summarize real-device TikTok VPN drop harness artifacts."""

from __future__ import annotations

import argparse
import json
import plistlib
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ERROR_RE = re.compile(
    r"(error|failed|failure|fatal|crash|exception|timeout|denied|reject|"
    r"degraded|tripped|unexpected|disconnect)",
    re.IGNORECASE,
)
DISCONNECT_RE = re.compile(
    r"(vpn status .*->\s*disconnected|status_drop_without_stop_callback|"
    r"stop_cause_final=|last_completed_stop_cause_final=|unexpected_exit=true|"
    r"inferred_crash=true|provider_deinit_without_stop|tun2socks_exit|"
    r"os_stop_reason_|NEProviderStopReason|Stopping VPN tunnel)",
    re.IGNORECASE,
)
MANUAL_STOP_RE = re.compile(r"Stopping VPN tunnel.*source=.*(toggle|manual|settings)", re.IGNORECASE)
TIKTOK_RE = re.compile(
    r"(tiktok|musical\.ly|musically|byteoversea|ibyteimg|bytefcdn|ttwstatic|"
    r"tiktokcdn|tiktokv|snssdk|aweme|bytedance)",
    re.IGNORECASE,
)
STATS_LINE_RE = re.compile(r"SOCKS5 STATS: (?P<body>.*)")
PRESSURE_SAMPLE_RE = re.compile(r"EXTENSION_PRESSURE sample runtime_s=(?P<runtime>\d+)\s+level=(?P<level>[a-z_]+)")
RECONNECT_ATTEMPT_RE = re.compile(r"(Auto-reconnect attempt|Probe reconnect attempt after transport trip)", re.IGNORECASE)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifact-dir", required=True)
    parser.add_argument("--duration", type=int, required=True)
    parser.add_argument("--started-at", type=float, required=True)
    parser.add_argument("--ended-at", type=float, required=True)
    parser.add_argument("--device-udid", required=True)
    parser.add_argument("--tiktok-bundle-id", required=True)
    parser.add_argument("--app-group-id", default="group.com.yamin.nimademo")
    return parser.parse_args()


def iso_from_epoch(value: float | int | None) -> str | None:
    if not value or value <= 0:
        return None
    return datetime.fromtimestamp(value, tz=timezone.utc).isoformat().replace("+00:00", "Z")


def parse_iso(value: str) -> datetime | None:
    value = value.strip()
    if not value:
        return None
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    try:
        return datetime.fromisoformat(value)
    except ValueError:
        return None


def parse_log(path: Path, source: str, start: float, end: float) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    rows: list[dict[str, Any]] = []
    for index, line in enumerate(path.read_text(errors="replace").splitlines(), start=1):
        timestamp = None
        match = re.match(r"^\[(?P<ts>[^\]]+)\]\s*(?P<body>.*)$", line)
        body = line
        if match:
            parsed = parse_iso(match.group("ts"))
            if parsed:
                timestamp = parsed.timestamp()
            body = match.group("body")
        if timestamp is not None and not (start - 10 <= timestamp <= end + 30):
            continue
        rows.append(
            {
                "source": source,
                "line_number": index,
                "timestamp": timestamp,
                "time": iso_from_epoch(timestamp),
                "line": line,
                "body": body,
            }
        )
    return rows


def read_json(path: Path) -> Any:
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(errors="replace"))
    except json.JSONDecodeError:
        return None


def read_prefs(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        with path.open("rb") as file:
            data = plistlib.load(file)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def latest_snapshot(traffic: Any) -> dict[str, Any] | None:
    if not isinstance(traffic, dict):
        return None
    snapshots = traffic.get("snapshots")
    if not isinstance(snapshots, list) or not snapshots:
        return None
    last = snapshots[-1]
    return last if isinstance(last, dict) else None


def contains_tiktok_traffic(traffic: Any, log_rows: list[dict[str, Any]]) -> tuple[bool, list[str]]:
    evidence: list[str] = []
    if isinstance(traffic, dict):
        text_fields: list[str] = []
        for snapshot in traffic.get("snapshots", []) or []:
            if not isinstance(snapshot, dict):
                continue
            for connection in snapshot.get("connections", []) or []:
                if isinstance(connection, dict):
                    text_fields.extend(
                        str(connection.get(key, ""))
                        for key in ("host", "sni")
                    )
            for domain in snapshot.get("topDomains", []) or []:
                if isinstance(domain, dict):
                    text_fields.append(str(domain.get("domain", "")))
            stats = snapshot.get("stats")
            if isinstance(stats, dict):
                for key in ("attemptedByBucket", "blockedByBucket", "tiktokHardeningActions"):
                    value = stats.get(key)
                    if isinstance(value, dict):
                        text_fields.extend(str(item) for item in value.keys())
        for event in traffic.get("events", []) or []:
            if isinstance(event, dict):
                text_fields.extend(str(event.get(key, "")) for key in ("host", "sni", "detail", "type"))

        for value in text_fields:
            if TIKTOK_RE.search(value):
                evidence.append(value)
                if len(evidence) >= 8:
                    break

    if not evidence:
        for row in log_rows:
            if TIKTOK_RE.search(row["line"]):
                evidence.append(f"{row['source']}:{row['line_number']}: {row['line']}")
                if len(evidence) >= 8:
                    break
    return bool(evidence), evidence


def parse_latest_stats_line(log_rows: list[dict[str, Any]]) -> dict[str, Any]:
    parsed: dict[str, Any] = {}
    for row in log_rows:
        match = STATS_LINE_RE.search(row["line"])
        if not match:
            continue
        body = match.group("body")
        for key, pattern in {
            "total_connections_from_log": r"(?P<value>\d+)\s+total",
            "active_connections_from_log": r"(?P<value>\d+)\s+active",
            "active_udp_streams_from_log": r"udpActive=(?P<value>\d+)",
            "memory_mb_from_log": r"mem=(?P<value>[0-9.]+)MB",
        }.items():
            value_match = re.search(pattern, body)
            if value_match:
                value = value_match.group("value")
                parsed[key] = float(value) if "." in value else int(value)
    return parsed


def find_disconnect(log_rows: list[dict[str, Any]], prefs: dict[str, Any], start: float, end: float) -> dict[str, Any]:
    for idx, row in enumerate(log_rows):
        line = row["line"]
        if MANUAL_STOP_RE.search(line):
            continue
        if DISCONNECT_RE.search(line):
            if "stop_cause_final=" in line and re.search(r"stop_cause_final=\s*$", line):
                continue
            before = log_rows[max(0, idx - 20):idx]
            return {
                "vpn_disconnected": True,
                "first_disconnect_time": row["time"],
                "first_disconnect_epoch": row["timestamp"],
                "disconnect_evidence": f"{row['source']}:{row['line_number']}: {line}",
                "log_lines_before_disconnect": [
                    f"{item['source']}:{item['line_number']}: {item['line']}" for item in before
                ],
            }

    stop_keys = [
        "vpnLifecycle.last_stop_ts",
        "vpnLifecycle.stop_signal_status_drop_ts",
        "vpnLifecycle.stop_signal_tun2socks_exit_ts",
        "vpnLifecycle.stop_signal_provider_deinit_ts",
        "vpnLifecycle.stop_signal_os_stop_ts",
    ]
    for key in stop_keys:
        value = prefs.get(key)
        if isinstance(value, (int, float)) and start - 10 <= value <= end + 30:
            return {
                "vpn_disconnected": True,
                "first_disconnect_time": iso_from_epoch(value),
                "first_disconnect_epoch": value,
                "disconnect_evidence": f"app_group_pref:{key}={value}",
                "log_lines_before_disconnect": [],
            }

    final = str(prefs.get("vpnLifecycle.last_completed_stop_cause_final", ""))
    final_ts = prefs.get("vpnLifecycle.last_completed_stop_finalized_ts")
    if final and isinstance(final_ts, (int, float)) and start - 10 <= final_ts <= end + 30:
        return {
            "vpn_disconnected": True,
            "first_disconnect_time": iso_from_epoch(final_ts),
            "first_disconnect_epoch": final_ts,
            "disconnect_evidence": f"app_group_pref:vpnLifecycle.last_completed_stop_cause_final={final}",
            "log_lines_before_disconnect": [],
        }

    return {
        "vpn_disconnected": False,
        "first_disconnect_time": None,
        "first_disconnect_epoch": None,
        "disconnect_evidence": None,
        "log_lines_before_disconnect": [],
    }


def last_error(log_rows: list[dict[str, Any]]) -> dict[str, Any] | None:
    for row in reversed(log_rows):
        if "SOCKS5 STATS:" in row["line"] and re.search(r"\b0 errors\b", row["line"], re.IGNORECASE):
            continue
        if ERROR_RE.search(row["line"]):
            return {
                "source": row["source"],
                "line_number": row["line_number"],
                "time": row["time"],
                "line": row["line"],
            }
    return None


def count_disconnect_events(log_rows: list[dict[str, Any]]) -> int:
    count = 0
    for row in log_rows:
        line = row["line"]
        if MANUAL_STOP_RE.search(line):
            continue
        if DISCONNECT_RE.search(line):
            if "stop_cause_final=" in line and re.search(r"stop_cause_final=\s*$", line):
                continue
            count += 1
    return count


def critical_pressure_max_consecutive_seconds(log_rows: list[dict[str, Any]]) -> int:
    runtimes: list[int] = []
    for row in log_rows:
        match = PRESSURE_SAMPLE_RE.search(row["line"])
        if not match:
            continue
        if match.group("level") != "critical":
            continue
        runtimes.append(int(match.group("runtime")))
    if not runtimes:
        return 0
    runtimes = sorted(set(runtimes))
    best = 1
    current = 1
    for previous, current_runtime in zip(runtimes, runtimes[1:]):
        if current_runtime - previous <= 1:
            current += current_runtime - previous
        else:
            best = max(best, current)
            current = 1
    best = max(best, current)
    return best


def reconnect_attempt_metrics(log_rows: list[dict[str, Any]], first_disconnect_epoch: float | None) -> tuple[int, float | None]:
    attempts: list[dict[str, Any]] = []
    for row in log_rows:
        if RECONNECT_ATTEMPT_RE.search(row["line"]):
            attempts.append(row)
    first_delay = None
    if attempts and first_disconnect_epoch and attempts[0]["timestamp"] is not None:
        first_delay = max(0.0, attempts[0]["timestamp"] - first_disconnect_epoch)
    return len(attempts), first_delay


def bool_pref(prefs: dict[str, Any], key: str) -> bool:
    return bool(prefs.get(key, False))


def classify_disconnect(stats: dict[str, Any], prefs: dict[str, Any], disconnect_evidence: str | None) -> str:
    final = str(
        prefs.get("vpnLifecycle.last_completed_stop_cause_final")
        or prefs.get("vpnLifecycle.stop_cause_final")
        or ""
    )
    heartbeat_snapshot_raw = prefs.get("vpnLifecycle.provider_last_heartbeat_snapshot_json") or "{}"
    try:
        heartbeat_snapshot = json.loads(heartbeat_snapshot_raw) if isinstance(heartbeat_snapshot_raw, str) else {}
    except json.JSONDecodeError:
        heartbeat_snapshot = {}
    provider_phase = str(
        heartbeat_snapshot.get("provider_phase")
        or ""
    ) or str(
        prefs.get("vpnLifecycle.provider_last_phase")
        or stats.get("providerLastPhase")
        or ""
    )
    queued_udp_raw = heartbeat_snapshot.get("queued_udp")
    try:
        queued_udp = int(queued_udp_raw)
    except (TypeError, ValueError):
        queued_udp = -1
    last_udp_close_phase = str(heartbeat_snapshot.get("last_udp_close_phase") or "")
    tun2socks_exit_ts = prefs.get("vpnLifecycle.stop_signal_tun2socks_exit_ts")
    tun2socks_observed = (
        final == "tun2socks_exit"
        or (isinstance(tun2socks_exit_ts, (int, float)) and tun2socks_exit_ts > 0)
        or bool(disconnect_evidence and "tun2socks_exit" in disconnect_evidence)
    )
    if tun2socks_observed:
        return "tun2socks_native_exit"
    if final == "status_drop_without_stop_callback":
        if queued_udp >= 8 and last_udp_close_phase == "grace_close_blocked":
            return "suspected_udp_startup_guard_saturation"
        if provider_phase == "dns_one_shot_close" or provider_phase == "dns_response_send":
            return "suspected_udp_dns_close_crash"
        return "suspected_provider_silent_exit"
    return final or "unknown"


def write_debug_snapshot(path: Path, summary: dict[str, Any]) -> None:
    lines = [
        "Final debug snapshot",
        f"device_udid={summary['device_udid']}",
        f"duration_seconds={summary['duration_seconds']}",
        f"started_at={summary['started_at']}",
        f"ended_at={summary['ended_at']}",
        f"vpn_disconnected={summary['vpn_disconnected']}",
        f"disconnect_classification={summary['disconnect_classification']}",
        f"disconnect_count={summary['disconnect_count']}",
        f"first_disconnect_time={summary['first_disconnect_time'] or 'none'}",
        f"disconnect_evidence={summary['disconnect_evidence'] or 'none'}",
        f"critical_pressure_max_consecutive_seconds={summary['critical_pressure_max_consecutive_seconds']}",
        f"reconnect_attempt_count={summary['reconnect_attempt_count']}",
        f"reconnect_time_to_first_attempt_seconds={summary['reconnect_time_to_first_attempt_seconds'] if summary['reconnect_time_to_first_attempt_seconds'] is not None else 'none'}",
        f"external_kill_signature={summary['external_kill_signature']}",
        f"reconnect_breaker_suppressed={summary['reconnect_breaker_suppressed']}",
        f"reconnect_cap_suppressed={summary['reconnect_cap_suppressed']}",
        f"ten_minute_pass={summary['ten_minute_pass']}",
        f"last_observed_error={(summary['last_observed_error'] or {}).get('line', 'none')}",
        f"memory_mb={summary['memory_mb'] if summary['memory_mb'] is not None else 'unknown'}",
        f"connection_count={summary['connection_count']}",
        f"active_udp_streams={summary['active_udp_streams'] if summary['active_udp_streams'] is not None else 'unknown'}",
        f"tiktok_traffic_observed={summary['tiktok_traffic_observed']}",
        f"missing_artifacts={summary['missing_artifacts']}",
    ]
    path.write_text("\n".join(lines) + "\n")


def write_markdown(path: Path, summary: dict[str, Any]) -> None:
    error = summary["last_observed_error"]
    lines = [
        "# TikTok VPN Drop Harness Summary",
        "",
        f"- Device: `{summary['device_udid']}`",
        f"- Duration: `{summary['duration_seconds']}s`",
        f"- Started: `{summary['started_at']}`",
        f"- Ended: `{summary['ended_at']}`",
        f"- VPN disconnected: `{'yes' if summary['vpn_disconnected'] else 'no'}`",
        f"- Disconnect classification: `{summary['disconnect_classification']}`",
        f"- Disconnect count: `{summary['disconnect_count']}`",
        f"- First disconnect time: `{summary['first_disconnect_time'] or 'none'}`",
        f"- Critical pressure max consecutive seconds: `{summary['critical_pressure_max_consecutive_seconds']}`",
        f"- Reconnect attempts: `{summary['reconnect_attempt_count']}`",
        f"- Reconnect time to first attempt: `{summary['reconnect_time_to_first_attempt_seconds'] if summary['reconnect_time_to_first_attempt_seconds'] is not None else 'none'}`",
        f"- External kill signature: `{'yes' if summary['external_kill_signature'] else 'no'}`",
        f"- Reconnect breaker suppression: `{'yes' if summary['reconnect_breaker_suppressed'] else 'no'}`",
        f"- Reconnect cap suppression: `{'yes' if summary['reconnect_cap_suppressed'] else 'no'}`",
        f"- Ten minute pass: `{'yes' if summary['ten_minute_pass'] else 'no'}`",
        f"- Last observed error: `{error['line'] if error else 'none'}`",
        f"- Memory: `{summary['memory_mb'] if summary['memory_mb'] is not None else 'unknown'} MB`",
        f"- Connection count: `{summary['connection_count']}`",
        f"- Active UDP streams: `{summary['active_udp_streams'] if summary['active_udp_streams'] is not None else 'unknown'}`",
        f"- TikTok traffic observed: `{'yes' if summary['tiktok_traffic_observed'] else 'no'}`",
        "",
        "## Disconnect Evidence",
        "",
        summary["disconnect_evidence"] or "No disconnect evidence found in the captured window.",
        "",
        "## Log Lines Before Disconnect",
        "",
    ]
    before = summary["log_lines_before_disconnect"]
    lines.extend(f"- `{line}`" for line in before[:20])
    if not before:
        lines.append("No disconnect line was found.")
    lines.extend(["", "## TikTok Evidence", ""])
    evidence = summary["tiktok_traffic_evidence"]
    lines.extend(f"- `{item}`" for item in evidence[:8])
    if not evidence:
        lines.append("No TikTok host/bucket evidence was found.")
    lines.extend(["", "## Missing Artifacts", ""])
    lines.extend(f"- `{item}`" for item in summary["missing_artifacts"])
    if not summary["missing_artifacts"]:
        lines.append("None.")
    path.write_text("\n".join(lines) + "\n")


def main() -> int:
    args = parse_args()
    artifact_dir = Path(args.artifact_dir)
    app_group_dir = artifact_dir / "app_group"
    root_files = {
        "app_diagnostic_log": artifact_dir / "app_diagnostic_log.txt",
        "tunnel_log": artifact_dir / "tunnel_log.txt",
        "traffic_stats": artifact_dir / "traffic_stats.json",
        "app_group_prefs": artifact_dir / "app_group_prefs.plist",
        "device_logarchive": artifact_dir / f"device_{args.device_udid}_last10m.logarchive",
        "sysdiagnose": artifact_dir / "sysdiagnose",
        "device_crash_logs": artifact_dir / "device_crash_logs",
    }
    fallbacks = {
        "app_diagnostic_log": app_group_dir / "app_diagnostic_log.txt",
        "tunnel_log": app_group_dir / "tunnel_log.txt",
        "traffic_stats": app_group_dir / "traffic_stats.json",
        "app_group_prefs": app_group_dir / "Library" / "Preferences" / f"{args.app_group_id}.plist",
        "device_logarchive": artifact_dir / f"device_{args.device_udid}_last10m.logarchive",
        "sysdiagnose": artifact_dir / "sysdiagnose",
        "device_crash_logs": artifact_dir / "device_crash_logs",
    }
    paths = {key: path if path.exists() else fallbacks[key] for key, path in root_files.items()}
    missing = [
        key for key, path in paths.items()
        if not path.exists() or (path.is_dir() and not any(path.iterdir()) and key in {"sysdiagnose"})
    ]

    app_rows = parse_log(paths["app_diagnostic_log"], "app", args.started_at, args.ended_at)
    tunnel_rows = parse_log(paths["tunnel_log"], "tunnel", args.started_at, args.ended_at)
    log_rows = sorted(
        app_rows + tunnel_rows,
        key=lambda row: (row["timestamp"] is None, row["timestamp"] or 0, row["source"], row["line_number"]),
    )
    traffic = read_json(paths["traffic_stats"])
    prefs = read_prefs(paths["app_group_prefs"])
    snapshot = latest_snapshot(traffic)
    stats = snapshot.get("stats", {}) if snapshot else {}
    latest_log_stats = parse_latest_stats_line(tunnel_rows)
    tiktok_seen, tiktok_evidence = contains_tiktok_traffic(traffic, log_rows)
    disconnect = find_disconnect(log_rows, prefs, args.started_at, args.ended_at)
    disconnect_count = count_disconnect_events(log_rows)
    critical_pressure_seconds = critical_pressure_max_consecutive_seconds(log_rows)
    reconnect_attempt_count, reconnect_first_delay = reconnect_attempt_metrics(log_rows, disconnect["first_disconnect_epoch"])
    disconnect_classification = classify_disconnect(stats, prefs, disconnect["disconnect_evidence"])
    external_kill_signature = bool_pref(prefs, "vpnLifecycle.external_kill_signature")
    reconnect_breaker_suppressed = (prefs.get("vpnLifecycle.reconnect_suppressed_by_breaker", 0) or 0) > 0
    reconnect_cap_suppressed = bool_pref(prefs, "vpnLifecycle.external_kill_reconnect_cap_active")

    memory_mb = latest_log_stats.get("memory_mb_from_log")
    pref_memory = prefs.get("vpnLifecycle.extension_pressure_memory_mb")
    if memory_mb is None and isinstance(pref_memory, (int, float)):
        memory_mb = pref_memory

    total_connections = stats.get("totalConns")
    active_connections = latest_log_stats.get("active_connections_from_log")
    active_udp_streams = stats.get("udpActiveStreams")
    if active_udp_streams is None:
        active_udp_streams = latest_log_stats.get("active_udp_streams_from_log")

    summary = {
        "device_udid": args.device_udid,
        "tiktok_bundle_id": args.tiktok_bundle_id,
        "duration_seconds": args.duration,
        "started_at": iso_from_epoch(args.started_at),
        "ended_at": iso_from_epoch(args.ended_at),
        "vpn_disconnected": disconnect["vpn_disconnected"],
        "disconnect_classification": disconnect_classification,
        "disconnect_count": disconnect_count,
        "first_disconnect_time": disconnect["first_disconnect_time"],
        "disconnect_evidence": disconnect["disconnect_evidence"],
        "log_lines_before_disconnect": disconnect["log_lines_before_disconnect"],
        "critical_pressure_max_consecutive_seconds": critical_pressure_seconds,
        "reconnect_attempt_count": reconnect_attempt_count,
        "reconnect_time_to_first_attempt_seconds": reconnect_first_delay,
        "external_kill_signature": external_kill_signature,
        "reconnect_breaker_suppressed": reconnect_breaker_suppressed,
        "reconnect_cap_suppressed": reconnect_cap_suppressed,
        "last_observed_error": last_error(log_rows),
        "memory_mb": memory_mb,
        "connection_count": {
            "total": total_connections,
            "active": active_connections,
        },
        "active_udp_streams": active_udp_streams,
        "tiktok_traffic_observed": tiktok_seen,
        "tiktok_traffic_evidence": tiktok_evidence,
        "traffic_snapshot_time": snapshot.get("timestamp") if snapshot else None,
        "missing_artifacts": missing,
        "artifacts": {key: str(path) for key, path in paths.items()},
        "artifact_summary": {
            "device_logarchive": str(paths["device_logarchive"]),
            "sysdiagnose": str(paths["sysdiagnose"]),
            "device_crash_logs": str(paths["device_crash_logs"]),
            "ips_optional": True,
        },
    }

    summary["ten_minute_pass"] = (
        args.duration >= 600
        and not summary["vpn_disconnected"]
        and summary["disconnect_count"] == 0
        and not summary["external_kill_signature"]
        and summary["critical_pressure_max_consecutive_seconds"] <= 2
        and not summary["reconnect_breaker_suppressed"]
        and not summary["reconnect_cap_suppressed"]
        and summary["tiktok_traffic_observed"]
    )

    (artifact_dir / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    write_markdown(artifact_dir / "summary.md", summary)
    write_debug_snapshot(artifact_dir / "final_debug_snapshot.txt", summary)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
