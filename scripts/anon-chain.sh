#!/bin/bash
# ══════════════════════════════════════════════════════════════
# anon-chain — On-demand Mullvad + Tor + nftables toggle (v2.0)
# ══════════════════════════════════════════════════════════════
# Usage:
#   sudo anon-chain on      Start VPN + Tor + firewall hardening
#   sudo anon-chain off     Stop everything, restore plain networking
#   sudo anon-chain status  Show current state
#
# Design rules (learned the hard way):
#   - ONLY uses nftables (nft). NEVER touches iptables.
#     WSL2's iptables-nft backend + nft commands = kernel deadlock.
#   - All firewall rules live in "inet anon_chain" table.
#   - Mullvad manages its own "inet mullvad" table.
#   - Boot is ALWAYS plain networking. Anon chain is opt-in.
# ══════════════════════════════════════════════════════════════

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
LOG="/var/log/anon-chain.log"

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[!] Run as root: sudo anon-chain $*${NC}"
    exit 1
fi

# Get WSL2 gateway IP from eth0 subnet
get_gateway() {
    local ip
    ip=$(ip -4 addr show eth0 2>/dev/null | awk '/inet / {split($2,a,"/"); print a[1]}')
    [ -z "$ip" ] && echo "" && return
    IFS='.' read -r a b c d <<< "$ip"
    echo "$a.$b.$(( c & 240 )).1"
}

# ══════════════════════════════════════════════════════════════
# ON — Start the full anonymization chain
# ══════════════════════════════════════════════════════════════
do_on() {
    echo -e "${CYAN}[*] Starting anon-chain...${NC}"
    echo "$(date): ON" >> "$LOG"

    local GW
    GW=$(get_gateway)
    [ -z "$GW" ] && echo -e "${RED}[!] No gateway. Is eth0 up?${NC}" && exit 1

    # 1. Start Mullvad daemon
    echo -e "${CYAN}[1/5] Starting Mullvad daemon...${NC}"
    systemctl start mullvad-daemon 2>/dev/null || true
    sleep 2

    # 2. Connect Mullvad VPN
    echo -e "${CYAN}[2/5] Connecting Mullvad VPN...${NC}"
    mullvad connect 2>/dev/null || true

    local i=0
    while [ $i -lt 15 ]; do
        if mullvad status 2>/dev/null | grep -q "Connected"; then
            echo -e "${GREEN}[+] Mullvad connected${NC}"
            break
        fi
        i=$((i + 1))
        sleep 2
    done
    [ $i -eq 15 ] && echo -e "${YELLOW}[!] Mullvad slow to connect — continuing${NC}"

    # 3. Start Tor
    echo -e "${CYAN}[3/5] Starting Tor...${NC}"
    systemctl start tor 2>/dev/null || true
    sleep 1

    # 4. Apply nftables hardening (pure nft, no iptables)
    echo -e "${CYAN}[4/5] Applying nftables hardening...${NC}"
    nft delete table inet anon_chain 2>/dev/null || true
    nft -f - <<'NFTEOF'
table inet anon_chain {
    chain input {
        type filter hook input priority 10; policy accept;
        iif lo accept
        ct state established,related accept
        ip saddr != 127.0.0.0/8 tcp dport 22 drop comment "block external SSH"
    }
    chain output {
        type filter hook output priority 10; policy accept;
        oif lo accept
        ct state established,related accept
    }
}
NFTEOF

    # 5. Set DNS to Mullvad tunnel DNS
    # Mullvad blocks external DNS when connected (leak prevention).
    # 10.64.0.1 is Mullvad's internal DNS resolver inside the tunnel.
    echo -e "${CYAN}[5/5] Setting Mullvad tunnel DNS...${NC}"
    printf 'nameserver 10.64.0.1\nnameserver 9.9.9.9\n' > /etc/resolv.conf

    echo ""
    echo -e "${GREEN}══════════════════════════════════════════${NC}"
    echo -e "${GREEN}  anon-chain: ON${NC}"
    echo -e "${GREEN}  Mullvad:    $(mullvad status 2>/dev/null | head -1)${NC}"
    echo -e "${GREEN}  Tor:        $(systemctl is-active tor 2>/dev/null)${NC}"
    echo -e "${GREEN}  Firewall:   nftables anon_chain loaded${NC}"
    echo -e "${GREEN}  DNS:        10.64.0.1 (Mullvad tunnel)${NC}"
    echo -e "${GREEN}══════════════════════════════════════════${NC}"
}

# ══════════════════════════════════════════════════════════════
# OFF — Stop everything, restore plain networking
# ══════════════════════════════════════════════════════════════
do_off() {
    echo -e "${CYAN}[*] Stopping anon-chain...${NC}"
    echo "$(date): OFF" >> "$LOG"

    local GW
    GW=$(get_gateway)

    # 1. Disconnect and stop Mullvad
    echo -e "${CYAN}[1/4] Stopping Mullvad...${NC}"
    mullvad disconnect 2>/dev/null || true
    sleep 1
    systemctl stop mullvad-daemon 2>/dev/null || true

    # 2. Stop Tor
    echo -e "${CYAN}[2/4] Stopping Tor...${NC}"
    systemctl stop tor 2>/dev/null || true

    # 3. Remove nftables rules (only our table + Mullvad leftovers)
    echo -e "${CYAN}[3/4] Removing nftables rules...${NC}"
    nft delete table inet anon_chain 2>/dev/null || true
    nft delete table inet mullvad 2>/dev/null || true

    # 4. Restore plain DNS
    echo -e "${CYAN}[4/4] Restoring DNS...${NC}"
    if [ -n "$GW" ]; then
        printf 'nameserver 8.8.8.8\nnameserver 8.8.4.4\n' > /etc/resolv.conf
    else
        printf 'nameserver 8.8.8.8\nnameserver 8.8.4.4\n' > /etc/resolv.conf
    fi

    echo ""
    echo -e "${GREEN}══════════════════════════════════════════${NC}"
    echo -e "${GREEN}  anon-chain: OFF${NC}"
    echo -e "${GREEN}  Plain networking restored${NC}"
    echo -e "${GREEN}  DNS: 8.8.8.8 (Google)${NC}"
    echo -e "${GREEN}══════════════════════════════════════════${NC}"
}

# ══════════════════════════════════════════════════════════════
# STATUS — Show current state
# ══════════════════════════════════════════════════════════════
do_status() {
    local ms ts ns cs gw
    ms=$(mullvad status 2>/dev/null | head -1 || echo "not installed")
    ts=$(systemctl is-active tor 2>/dev/null || echo "inactive")
    ns=$(nft list tables 2>/dev/null | grep -c "anon_chain" || echo "0")
    cs=$(grep "^nameserver" /etc/resolv.conf 2>/dev/null | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')
    gw=$(get_gateway)

    local state="OFF"
    echo "$ms" | grep -qi "connected" && state="ON"

    echo ""
    echo -e "${CYAN}══════════════════════════════════════════${NC}"
    echo -e "${CYAN}  anon-chain: ${state}${NC}"
    echo -e "${CYAN}  Mullvad:    ${ms}${NC}"
    echo -e "${CYAN}  Tor:        ${ts}${NC}"
    echo -e "${CYAN}  Firewall:   $( [ "${ns}" -gt 0 ] 2>/dev/null && echo 'loaded' || echo 'none' )${NC}"
    echo -e "${CYAN}  DNS:        ${cs}${NC}"
    echo -e "${CYAN}  eth0:       $(ip link show eth0 2>/dev/null | grep -o 'state [A-Z]*')${NC}"
    echo -e "${CYAN}  Gateway:    ${gw}${NC}"
    echo -e "${CYAN}══════════════════════════════════════════${NC}"
}

# ══════════════════════════════════════════════════════════════
case "${1:-}" in
    on)     do_on ;;
    off)    do_off ;;
    status) do_status ;;
    *)
        echo "Usage: sudo anon-chain {on|off|status}"
        echo ""
        echo "  on      Start Mullvad VPN + Tor + nftables hardening"
        echo "  off     Stop everything, restore plain networking"
        echo "  status  Show current state"
        exit 1
        ;;
esac
