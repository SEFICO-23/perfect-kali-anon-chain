#!/bin/bash
# pull-from-kali.sh — Pull project output from Kali back to Windows
#
# Retrieves generated reports/output from Kali's project directory.
# Uses wsl pipe (AF_VSOCK) — works with automount=false and interop=false.
#
# Usage:
#   ./pull-from-kali.sh <project-name>
#
# Run from Git Bash on Windows.

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
# Edit these to match your setup
KALI_DISTRO="kali-linux"
KALI_USER="${KALI_USER:-kali}"                        # Override with env var
KALI_BASE="${KALI_BASE:-/home/$KALI_USER/workspace}"  # Kali source
OUTPUT_DIR="${OUTPUT_DIR:-./output}"                   # Windows destination
PROJECT_NAME="${1:-}"

# Input validation — prevent command injection via shell metacharacters
validate_name() {
    if [[ ! "$1" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        err "Invalid name: '$1' — only alphanumeric, dash, underscore, dot allowed"
        exit 1
    fi
}
[ -n "$PROJECT_NAME" ] && validate_name "$PROJECT_NAME"
# ──────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[PULL]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1" >&2; }

pull_file() {
    local src="$1"
    local dest="$2"
    mkdir -p "$(dirname "$dest")"
    wsl -d "$KALI_DISTRO" -u "$KALI_USER" -- bash -c "cat \"$src\" 2>/dev/null" > "$dest"
    if [ -s "$dest" ]; then
        log "  <- $src"
    else
        rm -f "$dest"
        warn "  Empty or missing: $src"
    fi
}

echo ""
echo "=========================================="
echo "  Kali Anon Chain — Pull from Kali WSL"
echo "=========================================="
echo ""

if [ -z "$PROJECT_NAME" ]; then
    err "Usage: $0 <project-name>"
    echo ""
    echo "Available projects in Kali:"
    wsl -d "$KALI_DISTRO" -u "$KALI_USER" -- bash -c "ls $KALI_BASE/projects/ 2>/dev/null" || echo "  (none)"
    exit 1
fi

if ! wsl -d "$KALI_DISTRO" -- bash -c "echo ok" >/dev/null 2>&1; then
    err "Kali Linux WSL is not running."
    exit 1
fi

KALI_PROJECT="$KALI_BASE/projects/$PROJECT_NAME"
WIN_OUTPUT="$OUTPUT_DIR/$PROJECT_NAME"

if ! wsl -d "$KALI_DISTRO" -u "$KALI_USER" -- bash -c "[ -d '$KALI_PROJECT' ]"; then
    err "Project not found in Kali: $KALI_PROJECT"
    exit 1
fi

mkdir -p "$WIN_OUTPUT"
log "Pulling output for: $PROJECT_NAME"

FILE_LIST=$(wsl -d "$KALI_DISTRO" -u "$KALI_USER" -- bash -c \
    "find '$KALI_PROJECT' -type f \( -name '*.md' -o -name '*.txt' -o -name '*.json' -o -name '*.csv' -o -name '*.html' -o -name '*.xml' \) 2>/dev/null")

if [ -z "$FILE_LIST" ]; then
    warn "No output files found in $KALI_PROJECT"
    exit 0
fi

while IFS= read -r kali_file; do
    rel_path="${kali_file#$KALI_PROJECT/}"
    pull_file "$kali_file" "$WIN_OUTPUT/$rel_path"
done <<< "$FILE_LIST"

echo ""
log "Pull complete. Output saved to: $WIN_OUTPUT"
echo ""
