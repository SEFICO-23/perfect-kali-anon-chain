#!/bin/bash
# stealth-fetch.sh — Anti-bot bypass CLI for the Kali Anon Chain
#
# Fetches URLs through the anonymization chain with TLS fingerprint
# spoofing and automatic escalation to a headless browser when blocked.
#
# Usage:
#   ./scripts/stealth-fetch.sh <url> [options]
#   ./scripts/stealth-fetch.sh https://amazon.com --tier auto -v
#   ./scripts/stealth-fetch.sh https://example.com --tier 1 --json
#   ./scripts/stealth-fetch.sh https://nowsecure.nl --tier 2 -o page.html
#
# See: docs/09-anti-bot-bypass.md for full documentation.
# Install deps first: sudo ./scripts/install-stealth-deps.sh

set -euo pipefail

VENV="/opt/kali-anon-chain/venv"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# Check venv exists
if [ ! -f "$VENV/bin/activate" ]; then
    echo "[stealth-fetch] Python venv not found at $VENV" >&2
    echo "[stealth-fetch] Run: sudo ./scripts/install-stealth-deps.sh" >&2
    exit 1
fi

# Activate venv and run the CLI module
source "$VENV/bin/activate"
PYTHONPATH="$LIB_DIR:${PYTHONPATH:-}" python3 -m stealth_fetch.cli "$@"
