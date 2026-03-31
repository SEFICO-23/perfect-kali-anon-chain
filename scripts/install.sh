#!/bin/bash
# ══════════════════════════════════════════════════════════════
# install.sh — Install kali-anon-chain v2.0
# ══════════════════════════════════════════════════════════════
# Run ONCE inside Kali WSL2 as root.
# After install: wsl --shutdown → restart → plain networking works.
# Then: sudo anon-chain on|off|status
# ══════════════════════════════════════════════════════════════

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[!] Run as root: sudo bash install.sh${NC}"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
USER_HOME=$(eval echo ~"${SUDO_USER:-$USER}")

echo -e "${CYAN}[*] Installing kali-anon-chain v2.0...${NC}"
echo ""

# ── 1. Backup existing configs ───────────────────────────────
echo -e "${CYAN}[1/8] Backing up existing configs...${NC}"
BACKUP_TS=$(date +%s)
cp /etc/wsl.conf "/etc/wsl.conf.bak.$BACKUP_TS" 2>/dev/null || true
echo "  Backed up wsl.conf"

# ── 2. Install boot network script ───────────────────────────
echo -e "${CYAN}[2/8] Installing boot script...${NC}"
cp "$SCRIPT_DIR/kali-boot-network.sh" "$USER_HOME/kali-boot-network.sh"
chmod +x "$USER_HOME/kali-boot-network.sh"
echo "  Installed: $USER_HOME/kali-boot-network.sh"

# ── 3. Install anon-chain command ─────────────────────────────
echo -e "${CYAN}[3/8] Installing anon-chain command...${NC}"
cp "$SCRIPT_DIR/anon-chain.sh" /usr/local/bin/anon-chain
chmod +x /usr/local/bin/anon-chain
echo "  Installed: /usr/local/bin/anon-chain"

# ── 4. Install systemd service ────────────────────────────────
echo -e "${CYAN}[4/8] Installing systemd network service...${NC}"
cat > /etc/systemd/system/kali-network.service << SVCEOF
[Unit]
Description=Kali WSL2 Plain Networking
After=network.target networking.service systemd-networkd.service
Wants=network.target

[Service]
Type=oneshot
ExecStart=$USER_HOME/kali-boot-network.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SVCEOF
systemctl daemon-reload
systemctl enable kali-network.service
echo "  Enabled: kali-network.service"

# ── 5. Update wsl.conf ───────────────────────────────────────
echo -e "${CYAN}[5/8] Updating wsl.conf...${NC}"
cat > /etc/wsl.conf << 'WSLEOF'
[boot]
systemd = true

[automount]
enabled = true

[network]
generateResolvConf = false

[interop]
enabled = false
appendWindowsPath = false
WSLEOF
echo "  Updated: /etc/wsl.conf"

# ── 6. Disable legacy anon chain services ─────────────────────
echo -e "${CYAN}[6/8] Disabling legacy auto-start services...${NC}"
LEGACY_SERVICES=(
    kali-firewall
    kali-dns
    anon-chain-healthcheck
    mullvad-multihop
    mullvad-daemon
    mullvad-early-boot-blocking
    tor
    tor-exempt
    vpn-killswitch
    vpn-leak-check
)
for svc in "${LEGACY_SERVICES[@]}"; do
    systemctl stop "$svc" 2>/dev/null || true
    systemctl disable "$svc" 2>/dev/null || true
done
echo "  Disabled ${#LEGACY_SERVICES[@]} legacy services"

# ── 7. Flush all firewall rules ───────────────────────────────
echo -e "${CYAN}[7/8] Flushing all firewall rules...${NC}"
nft flush ruleset 2>/dev/null || true
# Attempt iptables flush with timeout (may deadlock on WSL2)
timeout 5 iptables -P INPUT ACCEPT 2>/dev/null || true
timeout 5 iptables -P FORWARD ACCEPT 2>/dev/null || true
timeout 5 iptables -P OUTPUT ACCEPT 2>/dev/null || true
timeout 5 iptables -F 2>/dev/null || true
echo "  Firewall rules cleared"

# ── 8. Set initial DNS ────────────────────────────────────────
echo -e "${CYAN}[8/8] Setting initial DNS...${NC}"
printf 'nameserver 8.8.8.8\nnameserver 8.8.4.4\n' > /etc/resolv.conf
echo "  DNS: 8.8.8.8 (Google)"

echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  kali-anon-chain v2.0 installed!${NC}"
echo -e "${GREEN}${NC}"
echo -e "${GREEN}  Next steps:${NC}"
echo -e "${GREEN}    1. Exit WSL${NC}"
echo -e "${GREEN}    2. Run: wsl --shutdown${NC}"
echo -e "${GREEN}    3. Start Kali: wsl -d kali-linux${NC}"
echo -e "${GREEN}    4. Verify: ping -c1 8.8.8.8${NC}"
echo -e "${GREEN}${NC}"
echo -e "${GREEN}  Usage:${NC}"
echo -e "${GREEN}    sudo anon-chain on      # VPN + Tor + hardening${NC}"
echo -e "${GREEN}    sudo anon-chain off     # Plain networking${NC}"
echo -e "${GREEN}    sudo anon-chain status  # Show state${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
