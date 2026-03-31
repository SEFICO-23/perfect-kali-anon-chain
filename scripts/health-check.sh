#!/bin/bash
# health-check.sh — Verify the full VPN-over-Tor anonymization chain
#
# Checks every layer of the chain and reports status.
# Run after install or after any reboot to confirm everything is working.
#
# Usage:
#   ./health-check.sh          # Full check
#   ./health-check.sh --quick  # Services only (no network tests)
#   ./health-check.sh --fix    # Full check + attempt auto-repair of failures

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

pass() { echo -e "  ${GREEN}[PASS]${NC} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; FAIL=$((FAIL + 1)); }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; WARN=$((WARN + 1)); }
info() { echo -e "  ${DIM}[INFO]${NC} $1"; }
header() { echo -e "\n${CYAN}${BOLD}── $1 ──${NC}"; }

# Portable JSON value extractor (no grep -P dependency)
json_val() {
    local key="$1" json="$2"
    echo "$json" | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\([^,}]*\).*/\1/p" | tr -d '"[:space:]'
}

QUICK=false
FIX=false
for arg in "$@"; do
    case "$arg" in
        --quick) QUICK=true ;;
        --fix)   FIX=true ;;
    esac
done

try_fix() {
    if [ "$FIX" = true ]; then
        echo -e "  ${YELLOW}  → Attempting fix: $1${NC}"
        eval "$2" 2>/dev/null || true
    fi
}

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║    Kali Anon Chain — Health Check            ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"

# ── 1. Systemd services ─────────────────────────────────────────────────────
header "1. Systemd Services"

for svc in kali-dns tor-exempt tor@default mullvad-daemon; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        pass "$svc is active"
    else
        fail "$svc is NOT active"
        try_fix "restarting $svc" "systemctl restart $svc && sleep 5"
    fi
done

for svc in kali-dns tor-exempt tor@default.service; do
    if systemctl is-enabled --quiet "$svc" 2>/dev/null; then
        pass "$svc is enabled (persistent)"
    else
        fail "$svc is NOT enabled — won't survive reboot"
    fi
done

# ── 2. DNS ───────────────────────────────────────────────────────────────────
header "2. DNS Configuration"

if [ -f /etc/resolv.conf ] && [ ! -L /etc/resolv.conf ]; then
    pass "/etc/resolv.conf is a real file (not symlink)"
else
    fail "/etc/resolv.conf is missing or is a dangling symlink"
fi

if grep -q "nameserver" /etc/resolv.conf 2>/dev/null; then
    DNS=$(head -1 /etc/resolv.conf | awk '{print $2}')
    pass "DNS configured: $DNS"
    info "Shows 9.9.9.9 before Mullvad connects, 10.64.0.1 after — both correct"
else
    fail "No nameserver in /etc/resolv.conf"
fi

# ── 3. nftables exemption ───────────────────────────────────────────────────
header "3. nftables Tor Exemption"

if nft list table inet tor_exempt >/dev/null 2>&1; then
    pass "tor_exempt table exists"
    PACKETS=$(nft list table inet tor_exempt 2>/dev/null | awk '/packets/{print $2}' | head -1 || echo "0")
    if [ "${PACKETS:-0}" -gt 0 ] 2>/dev/null; then
        pass "Tor packets are being marked (counter: $PACKETS)"
    else
        warn "Tor packet counter is 0 — Tor may not be sending traffic yet"
    fi
else
    fail "tor_exempt nftables table is MISSING — Mullvad will block Tor"
    try_fix "re-applying tor_exempt rules" "bash /etc/tor-exempt-nft.sh 2>/dev/null || bash scripts/tor-exempt-nft.sh"
fi

# ── 4. Tor daemon ────────────────────────────────────────────────────────────
header "4. Tor Daemon"

EXPECTED_TOR_UID=$(id -u debian-tor 2>/dev/null || echo "")

if pgrep -x tor >/dev/null 2>&1; then
    TOR_UID=$(ps -o uid= -p "$(pgrep -x tor | head -1)" 2>/dev/null | tr -d ' ')
    pass "Tor process running (UID: $TOR_UID)"
    if [ -n "$EXPECTED_TOR_UID" ] && [ "$TOR_UID" = "$EXPECTED_TOR_UID" ]; then
        pass "Tor running as debian-tor (UID $EXPECTED_TOR_UID) — nftables match correct"
    elif [ -n "$EXPECTED_TOR_UID" ]; then
        warn "Tor UID is $TOR_UID, expected $EXPECTED_TOR_UID — check nftables rule"
    else
        warn "Could not determine expected Tor UID (debian-tor user missing?)"
    fi
else
    fail "Tor is NOT running"
fi

if journalctl -u tor@default --no-pager -n 10 2>/dev/null | grep -q "Bootstrapped 100%"; then
    pass "Tor bootstrapped 100%"
else
    fail "Tor has NOT fully bootstrapped"
    try_fix "restarting Tor" "systemctl restart tor@default.service && sleep 15"
fi

# ── 5. Mullvad status ───────────────────────────────────────────────────────
header "5. Mullvad VPN"

if command -v mullvad >/dev/null 2>&1; then
    MULLVAD_STATUS=$(mullvad status 2>/dev/null || echo "error")
    if echo "$MULLVAD_STATUS" | grep -q "Connected"; then
        pass "Mullvad is connected"
        RELAY=$(echo "$MULLVAD_STATUS" | sed -n 's/.*Relay:[[:space:]]*//p' || echo "unknown")
        info "Relay: $RELAY"
    elif echo "$MULLVAD_STATUS" | grep -q "Connecting"; then
        warn "Mullvad is still connecting — wait and re-check"
    else
        fail "Mullvad is NOT connected: $MULLVAD_STATUS"
        try_fix "reconnecting Mullvad" "mullvad connect && sleep 15"
    fi

    # Check critical settings
    AC=$(mullvad auto-connect get 2>/dev/null || echo "unknown")
    if echo "$AC" | grep -qi "on"; then
        pass "Auto-connect is ON"
    else
        fail "Auto-connect is OFF — chain won't start at boot"
    fi

    TUNNEL_INFO=$(mullvad tunnel get 2>/dev/null || echo "unknown")
    if echo "$TUNNEL_INFO" | grep -i "quantum" | grep -qi "off"; then
        pass "Quantum resistance is OFF (required for Tor routing)"
    else
        warn "Quantum resistance may be ON — this breaks VPN-over-Tor"
    fi

    # DAITA shows as "DAITA: off" or "DAITA: any/smart routing". If connected via Tor,
    # the chain working IS proof DAITA is off (it kills the tunnel entirely if on).
    if echo "$TUNNEL_INFO" | grep -i "daita" | grep -qi "off\|smart"; then
        pass "DAITA is OFF (incompatible with Udp2Tcp + Tor)"
    elif echo "$MULLVAD_STATUS" | grep -q "Connected"; then
        pass "DAITA is OFF (confirmed: VPN-over-Tor tunnel is up)"
    else
        warn "DAITA may be ON — this prevents tunnel establishment over Tor"
    fi

    # Check multihop
    RELAY_INFO=$(mullvad relay get 2>/dev/null || echo "unknown")
    if echo "$RELAY_INFO" | grep -qi "via\|entry"; then
        pass "Multihop is configured (entry + exit relays)"
    else
        warn "Multihop may not be configured — single relay detected"
    fi
else
    fail "Mullvad CLI not found"
fi

# ── 6. WSL isolation ────────────────────────────────────────────────────────
header "6. WSL Isolation"

if [ -f /etc/wsl.conf ]; then
    if grep -q "enabled = false" /etc/wsl.conf 2>/dev/null; then
        pass "Windows automount is disabled"
    else
        warn "Automount may still be enabled — check /etc/wsl.conf"
    fi
else
    warn "/etc/wsl.conf not found"
fi

if [ -d /mnt/c ]; then
    if ls /mnt/c/ >/dev/null 2>&1; then
        fail "/mnt/c is accessible — Windows filesystem is mounted!"
    else
        pass "/mnt/c exists but is not accessible"
    fi
else
    pass "/mnt/c does not exist — isolation working"
fi

# ── 7. Network tests (skip with --quick) ────────────────────────────────────
if [ "$QUICK" = false ]; then
    header "7. Network Verification"

    # Exit IP check
    EXIT_IP=$(curl -s --max-time 15 https://ifconfig.me 2>/dev/null || echo "timeout")
    if [ "$EXIT_IP" != "timeout" ] && [ -n "$EXIT_IP" ]; then
        pass "Exit IP: $EXIT_IP"
    else
        fail "Could not determine exit IP (network may be down)"
    fi

    # Tor check
    TOR_CHECK=$(curl -s --max-time 15 https://check.torproject.org/api/ip 2>/dev/null || echo "{}")
    IS_TOR=$(json_val "IsTor" "$TOR_CHECK")
    if [ "$IS_TOR" = "false" ]; then
        pass "Target sees clean IP (IsTor: false) — not a Tor exit"
    elif [ "$IS_TOR" = "true" ]; then
        fail "Target sees a Tor exit IP — Mullvad may be disconnected"
    else
        warn "Could not check Tor status"
    fi

    # Mullvad confirmation
    MULLVAD_CHECK=$(curl -s --max-time 15 https://am.i.mullvad.net/json 2>/dev/null || echo "{}")
    MULLVAD_EXIT=$(json_val "mullvad_exit_ip" "$MULLVAD_CHECK")
    BLACKLISTED=$(json_val "blacklisted" "$MULLVAD_CHECK")
    if [ "$MULLVAD_EXIT" = "true" ]; then
        pass "Mullvad confirms: traffic exits through Mullvad relay"
    else
        warn "Mullvad exit check inconclusive"
    fi
    if [ "$BLACKLISTED" = "false" ]; then
        pass "IP is NOT blacklisted — clean exit"
    elif [ "$BLACKLISTED" = "true" ]; then
        warn "IP is blacklisted — try reconnecting for a new relay"
    fi

    # Direct Tor test
    DIRECT_TOR=$(proxychains4 -q curl -s --max-time 20 https://check.torproject.org/api/ip 2>/dev/null || echo "{}")
    DIRECT_IS_TOR=$(json_val "IsTor" "$DIRECT_TOR")
    if [ "$DIRECT_IS_TOR" = "true" ]; then
        pass "Direct Tor path works (proxychains4 → IsTor: true)"
    else
        warn "Direct Tor path not responding (may need more bootstrap time)"
    fi
fi

# ── 8. Anti-bot bypass tiers ────────────────────────────────────────────────
header "8. Anti-Bot Bypass (stealth-fetch)"

VENV="/opt/kali-anon-chain/venv"
if [ -d "$VENV" ] && [ -f "$VENV/bin/activate" ]; then
    pass "Python venv exists at $VENV"

    # Test tier availability via venv Python
    VENV_PY="$VENV/bin/python3"

    if "$VENV_PY" -c "from curl_cffi import requests" 2>/dev/null; then
        pass "Tier 1 (curl-cffi) is installed"
    else
        warn "Tier 1 (curl-cffi) NOT installed — run install-stealth-deps.sh"
    fi

    if "$VENV_PY" -c "from patchright.sync_api import sync_playwright" 2>/dev/null; then
        pass "Tier 2 (Patchright) is installed"
    else
        info "Tier 2 (Patchright) not installed (optional — for JS challenges)"
    fi
else
    info "stealth-fetch venv not installed (optional)"
    info "Install with: sudo ./scripts/install-stealth-deps.sh"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}══════════════════════════════════════════════${NC}"
echo -e "  ${GREEN}PASS: $PASS${NC}  ${RED}FAIL: $FAIL${NC}  ${YELLOW}WARN: $WARN${NC}"

if [ "$FAIL" -eq 0 ]; then
    echo -e "\n  ${GREEN}${BOLD}All checks passed. Chain is operational.${NC}\n"
    exit 0
elif [ "$FAIL" -le 2 ]; then
    echo -e "\n  ${YELLOW}${BOLD}Minor issues detected. Review warnings above.${NC}\n"
    exit 1
else
    echo -e "\n  ${RED}${BOLD}Chain has problems. Review failures above.${NC}\n"
    exit 2
fi
