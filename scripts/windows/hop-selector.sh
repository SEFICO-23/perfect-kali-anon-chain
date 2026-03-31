#!/bin/bash
# Mullvad Multihop Relay Selector — Windows Git Bash Launcher
# Launches the interactive selector inside Kali WSL2
#
# Usage:
#   ./hop-selector.sh                  # Interactive menu
#   ./hop-selector.sh --status         # Show current config
#   ./hop-selector.sh --apply rs pt    # Quick apply
#
# NOTE: MSYS_NO_PATHCONV=1 prevents Git Bash from mangling /home/... paths

export MSYS_NO_PATHCONV=1

SELECTOR="/usr/local/bin/mullvad-hop-selector.sh"

if [ $# -eq 0 ]; then
    wsl -d kali-linux -u root -- bash -c "$SELECTOR"
elif [ "$1" = "--status" ] || [ "$1" = "-s" ]; then
    wsl -d kali-linux -u root -- bash -c "$SELECTOR --status"
elif [ "$1" = "--presets" ] || [ "$1" = "-p" ]; then
    wsl -d kali-linux -u root -- bash -c "$SELECTOR --presets"
elif [ "$1" = "--apply" ] || [ "$1" = "-a" ]; then
    wsl -d kali-linux -u root -- bash -c "$SELECTOR --apply $2 $3"
else
    # Shorthand: hop-selector.sh rs pt
    wsl -d kali-linux -u root -- bash -c "$SELECTOR --apply $1 $2"
fi
