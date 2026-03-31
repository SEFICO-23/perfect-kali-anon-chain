#!/bin/bash
# kali-firewall.sh — Host isolation firewall
#
# Blocks all traffic between Kali and the Windows host IP.
# Prevents a compromised Kali from pivoting to the Windows filesystem,
# credential stores, or other Windows processes.
#
# The Windows host IP is the WSL2 NAT gateway (172.x.x.1).
# Auto-detected via: ip route | grep default
#
# This script is idempotent — safe to run multiple times.
# It uses a dedicated iptables chain to avoid flushing other rules.

set -euo pipefail

CHAIN_NAME="KALI_HOST_ISOLATION"
MAX_RETRIES=10
RETRY_DELAY=2

# Auto-detect the Windows host IP (WSL2 gateway) with retry for early boot
WIN_HOST=""
for i in $(seq 1 "$MAX_RETRIES"); do
    WIN_HOST=$(ip route | grep default | awk '{print $3}' 2>/dev/null || echo "")
    if [ -n "$WIN_HOST" ]; then
        break
    fi
    echo "[kali-firewall] Waiting for network... ($i/$MAX_RETRIES)" >&2
    sleep "$RETRY_DELAY"
done

if [ -z "$WIN_HOST" ]; then
    echo "[kali-firewall] ERROR: Could not detect WSL gateway IP after ${MAX_RETRIES} retries" >&2
    exit 1
fi

# Create dedicated chain (idempotent — flush if exists, create if not)
iptables -N "$CHAIN_NAME" 2>/dev/null || iptables -F "$CHAIN_NAME"

# Add rules to the dedicated chain
iptables -A "$CHAIN_NAME" -d "$WIN_HOST" -j DROP
iptables -A "$CHAIN_NAME" -s "$WIN_HOST" -j DROP

# Insert jump rules into INPUT/OUTPUT if not already present
iptables -C OUTPUT -j "$CHAIN_NAME" 2>/dev/null || iptables -I OUTPUT 1 -j "$CHAIN_NAME"
iptables -C INPUT  -j "$CHAIN_NAME" 2>/dev/null || iptables -I INPUT  1 -j "$CHAIN_NAME"

# Allow loopback (ensure not blocked)
iptables -C INPUT  -i lo -j ACCEPT 2>/dev/null || iptables -I INPUT  1 -i lo -j ACCEPT
iptables -C OUTPUT -o lo -j ACCEPT 2>/dev/null || iptables -I OUTPUT 1 -o lo -j ACCEPT

# Disable IPv6 to prevent bypass via link-local addresses
if command -v ip6tables >/dev/null 2>&1; then
    ip6tables -N "$CHAIN_NAME" 2>/dev/null || ip6tables -F "$CHAIN_NAME"
    ip6tables -A "$CHAIN_NAME" -j DROP
    ip6tables -C OUTPUT -j "$CHAIN_NAME" 2>/dev/null || ip6tables -I OUTPUT 1 -j "$CHAIN_NAME"
    ip6tables -C INPUT  -j "$CHAIN_NAME" 2>/dev/null || ip6tables -I INPUT  1 -j "$CHAIN_NAME"
    echo "[kali-firewall] IPv6 blocked (all traffic dropped)"
fi

echo "[kali-firewall] Host isolation applied. Windows host ($WIN_HOST) blocked."
