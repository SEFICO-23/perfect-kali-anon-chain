#!/bin/bash
# tor-exempt-nft.sh — nftables exemption for Tor traffic
#
# Creates an nftables table that exempts Tor daemon traffic from Mullvad's
# strict firewall, enabling the VPN-over-Tor architecture.
#
# HOW IT WORKS:
# When Mullvad enters "Connecting" state, it applies a nftables policy that
# drops all outbound traffic except to the specific relay IP. This kills Tor's
# circuits, which Mullvad needs to connect. Deadlock.
#
# Mullvad's output chain contains: "ct mark 0x00000f41 accept"
# This is Mullvad's split-tunnel bypass — traffic with this conntrack mark
# is allowed through regardless of the policy.
#
# We create a chain at priority mangle (-150) that marks all outbound
# packets from the Tor daemon with this mark.
#
# TWO MARKS REQUIRED:
#   ct mark 0x00000f41 — Mullvad firewall bypass
#   meta mark 0x6d6f6c65 — Mullvad routing bypass ("mole" in ASCII)
#                          Routes Tor traffic through eth0, not wg0-mullvad
#
# PRIORITY -150 (NOT -200):
#   At -200, our chain races with Linux conntrack entry creation.
#   ct mark set requires an existing conntrack entry to store the mark.
#   At -150 (after conntrack), the entry exists and ct mark set works.
#
# CHAIN TYPE "route" (NOT "filter"):
#   The "route" type allows influencing routing decisions by changing fwmark
#   before the routing lookup happens. In a "filter" chain, fwmark changes
#   happen after routing — too late.
#
# Run as root. Safe to run multiple times (idempotent).

set -euo pipefail

# Detect the Tor daemon UID — fail explicitly if not found
TOR_UID=$(id -u debian-tor 2>/dev/null || echo "")

if [ -z "$TOR_UID" ]; then
    echo "[tor-exempt] ERROR: debian-tor user not found. Is Tor installed?" >&2
    echo "[tor-exempt] Install with: sudo apt install tor" >&2
    exit 1
fi

# Remove existing table (idempotent)
nft delete table inet tor_exempt 2>/dev/null || true

# Create the table
nft add table inet tor_exempt

# Create chain at mangle priority (-150), type route for fwmark influence
nft add chain inet tor_exempt mark_tor \
    '{ type route hook output priority mangle; policy accept; }'

# Mark all outbound packets from the Tor daemon
# Counter is for diagnostics — check packet count with: nft list table inet tor_exempt
nft add rule inet tor_exempt mark_tor \
    meta skuid "$TOR_UID" \
    ct mark set 0x00000f41 \
    meta mark set 0x6d6f6c65 \
    counter

echo "[tor-exempt] nftables rules applied (Tor UID: $TOR_UID)"
echo "[tor-exempt] Verify with: nft list table inet tor_exempt"
