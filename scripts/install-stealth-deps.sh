#!/bin/bash
# install-stealth-deps.sh — Install anti-bot bypass dependencies
#
# Sets up a Python venv with curl-cffi (Tier 1) and optionally
# Patchright + Chromium (Tier 2) for the stealth-fetch tool.
#
# Usage:
#   sudo ./scripts/install-stealth-deps.sh
#
# The venv is created at /opt/kali-anon-chain/venv to avoid
# PEP 668 errors on Kali (Debian's externally-managed-environment).

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()    { echo -e "${GREEN}[+]${NC} $1"; }
warn()   { echo -e "${YELLOW}[!]${NC} $1"; }
err()    { echo -e "${RED}[-]${NC} $1" >&2; }
header() { echo -e "\n${CYAN}${BOLD}── $1 ──${NC}\n"; }

VENV_DIR="/opt/kali-anon-chain/venv"

# ── Root check ────────────────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    err "This script must be run as root. Use: sudo $0"
    exit 1
fi

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  Kali Anon Chain — Stealth Fetch Installer   ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo ""

# ── Step 1: System dependencies ──────────────────────────────────────────────
header "Step 1/4: System dependencies"

apt update -qq
apt install -y python3-pip python3-venv >/dev/null \
    || { err "Failed to install python3-pip/venv"; exit 1; }
log "python3-pip and python3-venv installed"

# ── Step 2: Create venv ──────────────────────────────────────────────────────
header "Step 2/4: Python virtual environment"

if [ -d "$VENV_DIR" ]; then
    log "Venv already exists at $VENV_DIR — upgrading packages"
else
    python3 -m venv "$VENV_DIR"
    log "Venv created at $VENV_DIR"
fi

source "$VENV_DIR/bin/activate"
pip install --upgrade pip >/dev/null 2>&1

# ── Step 3: Tier 1 — curl-cffi ──────────────────────────────────────────────
header "Step 3/4: Tier 1 — curl-cffi (TLS fingerprint spoofing)"

pip install curl-cffi --upgrade >/dev/null \
    || { err "Failed to install curl-cffi"; exit 1; }
log "curl-cffi installed"

# Verify import works
if python3 -c "from curl_cffi import requests; print('OK')" 2>/dev/null | grep -q "OK"; then
    log "Tier 1 verified: curl-cffi import successful"
else
    warn "curl-cffi installed but import failed — check for missing system libraries"
fi

# ── Step 4: Tier 2 — Patchright (optional) ───────────────────────────────────
header "Step 4/4: Tier 2 — Patchright (headless Chromium, ~250MB)"

echo ""
echo "  Patchright provides a full headless browser for bypassing JavaScript"
echo "  challenges (Cloudflare Turnstile, Akamai, etc.). It downloads ~250MB"
echo "  of Chromium browser binaries."
echo ""
read -r -p "  Install Patchright + Chromium? [y/N]: " install_browser

if [[ "$install_browser" =~ ^[Yy]$ ]]; then
    # System dependencies for headless Chromium
    log "Installing Chromium system dependencies..."
    # Full list — libnspr4 and libasound2-data are critical but easy to miss.
    # Without libnspr4: Chromium crashes on launch with "libnspr4.so not found"
    # Without libasound2-data: libasound2t64 stays unconfigured in dpkg
    apt install -y \
        libnspr4 libnss3 libgbm1 libxkbcommon0 libdbus-1-3 libxss1 \
        libasound2t64 libasound2-data \
        libatk-bridge2.0-0t64 libatk1.0-0t64 libcups2t64 libdrm2 \
        libpango-1.0-0 libcairo2 libxcomposite1 libxdamage1 \
        libxfixes3 libxrandr2 \
        >/dev/null 2>&1 \
        || warn "Some Chromium deps may be missing — browser might still work"

    log "Installing Patchright..."
    pip install patchright --upgrade >/dev/null \
        || { err "Failed to install patchright"; exit 1; }

    log "Downloading Chromium browser..."
    python3 -m patchright install chromium 2>/dev/null \
        || { err "Chromium download failed"; exit 1; }

    # Verify
    if python3 -c "from patchright.sync_api import sync_playwright; print('OK')" 2>/dev/null | grep -q "OK"; then
        log "Tier 2 verified: Patchright import successful"
    else
        warn "Patchright installed but import failed — check system dependencies"
    fi
else
    log "Skipping Tier 2 (Patchright). Tier 1 (curl-cffi) is still available."
    warn "Some sites with JavaScript challenges may require Tier 2."
    warn "Re-run this script to install later."
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║         Stealth Fetch — Installed            ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo "  Usage:"
echo "    ./scripts/stealth-fetch.sh https://amazon.com --tier auto -v"
echo ""
echo "  Tiers installed:"

if python3 -c "from curl_cffi import requests" 2>/dev/null; then
    echo -e "    ${GREEN}[1]${NC} curl-cffi — TLS fingerprint spoofing"
else
    echo -e "    ${RED}[1]${NC} curl-cffi — NOT available"
fi

if python3 -c "from patchright.sync_api import sync_playwright" 2>/dev/null; then
    echo -e "    ${GREEN}[2]${NC} Patchright — headless Chromium"
else
    echo -e "    ${YELLOW}[2]${NC} Patchright — NOT installed (optional)"
fi

echo ""
echo "  See: docs/09-anti-bot-bypass.md"
echo ""

deactivate 2>/dev/null || true
