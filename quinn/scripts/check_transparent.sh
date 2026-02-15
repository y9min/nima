#!/usr/bin/env bash
# Quick checks for transparent proxy + Instagram block.
# Run on the server. No root needed for status checks.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$REPO_ROOT/.env"
  set +a
fi

PROXY_LISTEN_PORT="${PROXY_LISTEN_PORT:-8080}"
WG_INTERFACE="${WG_INTERFACE:-wg0}"
VPN_SUBNET="${VPN_SUBNET:-}"

echo "=== 1. Redirect rules (must be enabled) ==="
if sudo nft list table ip bubble_redirect &>/dev/null; then
  sudo nft list table ip bubble_redirect
else
  echo "  NOT ACTIVE. Run: sudo ./scripts/setup_transparent_redirect.sh enable"
fi

echo ""
echo "=== 2. Proxy must be in TRANSPARENT mode and listening on port $PROXY_LISTEN_PORT ==="
if ss -ltn 2>/dev/null | grep -q ":$PROXY_LISTEN_PORT "; then
  PROC=$(ss -ltnp 2>/dev/null | grep ":$PROXY_LISTEN_PORT " | head -1 || true)
  if echo "$PROC" | grep -q mitmdump; then
    echo "  OK: mitmdump is listening (transparent mode)."
  elif echo "$PROC" | grep -q mitm; then
    echo "  WRONG MODE: mitmproxy or mitmweb is on $PROXY_LISTEN_PORT."
    echo "  Stop it (Ctrl+C), then run: ./scripts/run_proxy.sh transparent"
  else
    echo "  Port $PROXY_LISTEN_PORT in use. Ensure you ran: ./scripts/run_proxy.sh transparent"
  fi
else
  echo "  Nothing listening on $PROXY_LISTEN_PORT. Start: ./scripts/run_proxy.sh transparent"
fi

echo ""
echo "=== 3. WireGuard interface $WG_INTERFACE ==="
if ip link show "$WG_INTERFACE" &>/dev/null; then
  echo "  Interface exists."
else
  echo "  Not found. Is WireGuard running? Set WG_INTERFACE in .env to your WG interface."
fi

echo ""
echo "=== 4. Device checklist ==="
echo "  - Device is connected to this server via WireGuard (VPN)."
echo "  - VPN is used for internet (default route or all traffic)."
echo "  - You do NOT need to set 'Web proxy' on the device; redirect forces traffic here."
echo "  - Install mitmproxy CA on the device and trust it, or HTTPS will show cert errors."
echo ""
echo "To test: with proxy running (transparent) and device on VPN, open Instagram."
echo "You should see blocked requests in the proxy log, and Instagram should not load."
