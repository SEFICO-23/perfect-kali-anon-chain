#!/bin/bash
# ══════════════════════════════════════════════════════════════
# kali-boot-network.sh — Minimal WSL2 boot networking (v2.0)
# ══════════════════════════════════════════════════════════════
# Replaces kali-boot-fix.sh. Key differences:
#   - NO firewall rules at boot (prevents nftables/iptables deadlocks)
#   - NO iptables commands (WSL2 iptables-nft backend deadlocks kernel)
#   - NO VPN/Tor auto-start (use: sudo anon-chain on)
#   - Retries IP detection (Hyper-V can be slow to assign)
#   - Mounts C: drive for cross-filesystem access
#
# Run via systemd: kali-network.service (After=networking.service)
# ══════════════════════════════════════════════════════════════

LOG="/var/log/kali-boot.log"
echo "$(date): Boot network starting" >> "$LOG"

# Step 1: Bring eth0 UP
ip link set eth0 up 2>/dev/null

# Step 2: Wait for IP assignment (Hyper-V assigns via DHCP, can take a moment)
attempts=0
ETH0_IP=""
while [ $attempts -lt 10 ]; do
    ETH0_IP=$(ip -4 addr show eth0 2>/dev/null | awk '/inet / {split($2,a,"/"); print a[1]}')
    [ -n "$ETH0_IP" ] && break
    attempts=$((attempts + 1))
    sleep 1
done

if [ -z "$ETH0_IP" ]; then
    echo "$(date): ERROR: No eth0 IP after 10s" >> "$LOG"
    exit 1
fi
echo "$(date): eth0 IP: $ETH0_IP" >> "$LOG"

# Step 3: Calculate WSL2 gateway and add default route
# WSL2 uses /20 subnets. Gateway is at the first IP of the block.
# Example: eth0=172.20.114.229/20 → network=172.20.112.0/20 → gateway=172.20.112.1
IFS='.' read -r a b c d <<< "$ETH0_IP"
c_masked=$(( c & 240 ))
GATEWAY="$a.$b.$c_masked.1"
ip route add default via "$GATEWAY" dev eth0 2>/dev/null
echo "$(date): Route via $GATEWAY" >> "$LOG"

# Step 4: Set DNS (Google DNS — reliable on WSL2)
# WSL gateway DNS forwarding can be flaky; direct DNS is more reliable.
# Override with: sudo anon-chain on (switches to Mullvad/Quad9 DNS)
printf 'nameserver 8.8.8.8\nnameserver 8.8.4.4\n' > /etc/resolv.conf
echo "$(date): DNS set to 8.8.8.8" >> "$LOG"

# Step 5: Mount C: drive (if automount didn't catch it)
mount -t drvfs C: /mnt/c 2>/dev/null
echo "$(date): Boot complete" >> "$LOG"
