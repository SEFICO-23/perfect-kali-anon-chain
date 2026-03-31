#!/bin/bash
# Enforce multihop relay configuration after Mullvad auto-connects on boot.
# Reads relay preferences from /etc/anon-chain/relay.conf (or config/relay.conf).
#
# Fixes race condition: Mullvad auto-connects before Tor circuits are ready,
# fails multihop, falls back to single-hop, and saves that config.

LOG="/var/log/mullvad-multihop-fix.log"
CONF="/etc/anon-chain/relay.conf"

# Default relay config (overridden by config file)
ENTRY_COUNTRY="rs"
ENTRY_CITY="beg"
EXIT_COUNTRY="pt"
EXIT_CITY="lis"

# Load config if available
if [ -f "$CONF" ]; then
    # shellcheck source=/dev/null
    source "$CONF"
    echo "$(date): Loaded relay config: entry=$ENTRY_COUNTRY/$ENTRY_CITY exit=$EXIT_COUNTRY/$EXIT_CITY" >> "$LOG"
else
    # Try relative path (for running from repo checkout)
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$SCRIPT_DIR/../config/relay.conf" ]; then
        source "$SCRIPT_DIR/../config/relay.conf"
    fi
    echo "$(date): Using relay config: entry=$ENTRY_COUNTRY/$ENTRY_CITY exit=$EXIT_COUNTRY/$EXIT_CITY" >> "$LOG"
fi

echo "$(date): Multihop enforcement starting" >> "$LOG"

# Wait for Mullvad to be connected (max 90s — Tor bootstrap can be slow)
for i in $(seq 1 45); do
  status=$(mullvad status 2>&1 | head -1)
  if echo "$status" | grep -q "Connected"; then
    echo "$(date): Mullvad connected: $status" >> "$LOG"
    break
  fi
  if [ "$i" -eq 45 ]; then
    echo "$(date): ERROR: Mullvad did not connect after 90s" >> "$LOG"
    exit 1
  fi
  echo "$(date): Waiting for Mullvad ($i/45)..." >> "$LOG"
  sleep 2
done

# Check if multihop/relay needs fixing
current=$(mullvad relay get 2>&1)
needs_fix=0

if echo "$current" | grep "Multihop state" | grep -q "disabled"; then
  echo "$(date): Multihop disabled, fixing..." >> "$LOG"
  needs_fix=1
fi

# Also check if entry relay matches config
if ! echo "$current" | grep -qi "$ENTRY_COUNTRY"; then
  echo "$(date): Entry relay not set to $ENTRY_COUNTRY, fixing..." >> "$LOG"
  needs_fix=1
fi

if [ "$needs_fix" -eq 1 ]; then
  mullvad relay set tunnel-protocol wireguard >> "$LOG" 2>&1
  mullvad relay set multihop on >> "$LOG" 2>&1
  mullvad relay set entry location "$ENTRY_COUNTRY" "$ENTRY_CITY" >> "$LOG" 2>&1
  mullvad relay set location "$EXIT_COUNTRY" "$EXIT_CITY" >> "$LOG" 2>&1
  mullvad reconnect >> "$LOG" 2>&1

  # Wait for reconnection
  sleep 15
  final=$(mullvad status 2>&1)
  echo "$(date): After fix: $final" >> "$LOG"
else
  echo "$(date): Multihop already configured correctly, no fix needed" >> "$LOG"
fi

echo "$(date): Multihop enforcement complete" >> "$LOG"
