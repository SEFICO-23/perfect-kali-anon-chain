#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# kali-boot-fix.sh — Kali WSL2 Boot Network Fix
# ══════════════════════════════════════════════════════════════════════════════
#
# Fixes the networking chicken-and-egg problem on Kali WSL2 boot:
#   1. Brings eth0 UP
#   2. Removes conflicting manual nftables tables (ip filter, ip6 filter)
#   3. Adds default route via WSL gateway
#   4. Applies Mullvad-compatible hardening
#   5. Waits for Mullvad to connect (auto-connect is on)
#
# Run as root, either manually or via wsl.conf [boot] command.
#
# To make persistent, add to /etc/wsl.conf:
#   [boot]
#   command = /home/$USER/kali-boot-fix.sh
#
# Part of: kali-anon-chain
# ══════════════════════════════════════════════════════════════════════════════

LOG="/var/log/kali-boot-fix.log"
echo "$(date): Boot fix starting" >> "$LOG"

# Step 1: Bring eth0 UP
ip link set eth0 up 2>/dev/null
echo "$(date): eth0 brought up" >> "$LOG"

# Step 2: Remove conflicting manual nftables tables
# The Mullvad daemon's own `table inet mullvad` handles the VPN kill switch.
# Manual `ip filter` tables block the WSL gateway, preventing Mullvad from connecting.
nft delete table ip filter 2>/dev/null && echo "$(date): Deleted table ip filter" >> "$LOG"
nft delete table ip6 filter 2>/dev/null && echo "$(date): Deleted table ip6 filter" >> "$LOG"

# Also clean any iptables rules from kali-firewall.sh
iptables -F KALI_HOST_ISOLATION 2>/dev/null
iptables -D OUTPUT -j KALI_HOST_ISOLATION 2>/dev/null
iptables -D INPUT -j KALI_HOST_ISOLATION 2>/dev/null
iptables -X KALI_HOST_ISOLATION 2>/dev/null

# Step 3: Detect WSL gateway and add default route
# WSL2 gateway is always .1 of the assigned subnet
ETH0_IP=$(ip addr show eth0 | grep "inet " | awk '{print $2}' | cut -d/ -f1)
SUBNET=$(echo "$ETH0_IP" | cut -d. -f1-2)
# WSL2 uses /20 subnets. Gateway is at the start of the subnet block.
GATEWAY=$(ip route | grep "dev eth0" | grep -oP '\d+\.\d+\.\d+\.\d+' | head -1 | sed 's/\.[0-9]*$/.1/')
if [ -z "$GATEWAY" ]; then
    # Fallback: derive from eth0 IP — WSL2 gateway is always x.x.SUBNET_START.1
    GATEWAY="${SUBNET}.112.1"  # Common WSL2 pattern
fi

ip route add default via "$GATEWAY" dev eth0 2>/dev/null
echo "$(date): Default route added via $GATEWAY" >> "$LOG"

# Step 4: Apply Mullvad-compatible hardening
nft delete table ip hardening 2>/dev/null
nft add table ip hardening
nft add chain ip hardening input '{ type filter hook input priority 10 ; policy accept ; }'
nft add chain ip hardening output '{ type filter hook output priority 10 ; policy accept ; }'
nft add rule ip hardening input ip saddr "$GATEWAY" tcp dport != 22 drop
nft add rule ip hardening input ip saddr "$GATEWAY" udp dport != 53 drop

# Block IPv6 (prevent bypass)
nft delete table ip6 hardening 2>/dev/null
nft add table ip6 hardening
nft add chain ip6 hardening input '{ type filter hook input priority 10 ; policy drop ; }'
nft add chain ip6 hardening output '{ type filter hook output priority 10 ; policy drop ; }'
nft add rule ip6 hardening input iif lo accept
nft add rule ip6 hardening output oif lo accept

echo "$(date): Hardening applied (compatible with Mullvad)" >> "$LOG"

# Step 5: Wait for Mullvad to connect (auto-connect is enabled)
for i in $(seq 1 30); do
    status=$(mullvad status 2>&1 | head -1)
    if echo "$status" | grep -q "Connected"; then
        echo "$(date): Mullvad connected: $status" >> "$LOG"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "$(date): WARNING: Mullvad did not connect after 60s" >> "$LOG"
    fi
    sleep 2
done

# Step 6: Ensure PATH includes Go tools
if [ ! -f /etc/profile.d/go-tools.sh ]; then
    cat > /etc/profile.d/go-tools.sh << 'GOEOF'
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin
GOEOF
    echo "$(date): Go PATH profile script created" >> "$LOG"
fi

echo "$(date): Boot fix complete" >> "$LOG"
