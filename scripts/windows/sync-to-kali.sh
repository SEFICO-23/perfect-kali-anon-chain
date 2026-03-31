#!/bin/bash
# sync-to-kali.sh — One-way push from Windows to Kali WSL2
#
# Pushes project files into Kali without using Windows filesystem automounting.
# Uses WSL pipe (wsl -d kali-linux -u user) which works even with
# automount=false and interop=false in wsl.conf.
#
# Usage:
#   ./sync-to-kali.sh                       # Sync project files only
#   ./sync-to-kali.sh <project-name>        # Sync project + scope data
#
# Run from Git Bash on Windows.

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
# Edit these to match your setup
KALI_DISTRO="kali-linux"
KALI_USER="${KALI_USER:-kali}"                        # Override with env var
KALI_BASE="${KALI_BASE:-/home/$KALI_USER/workspace}"  # Kali destination
PROJECT_DIR="${PROJECT_DIR:-}"                         # Windows source directory
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

log()  { echo -e "${GREEN}[SYNC]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Push a single file into Kali via wsl pipe
push_file() {
    local src="$1"
    local dest="$2"
    if [ -f "$src" ]; then
        wsl -d "$KALI_DISTRO" -u "$KALI_USER" -- bash -c "mkdir -p \"$(dirname "$dest")\"" 2>/dev/null
        cat "$src" | wsl -d "$KALI_DISTRO" -u "$KALI_USER" -- bash -c "cat > \"$dest\""
        log "  -> $dest"
    else
        warn "  Source not found: $src"
    fi
}

# Push an entire directory into Kali
push_dir() {
    local src_dir="$1"
    local dest_dir="$2"
    local count=0
    wsl -d "$KALI_DISTRO" -u "$KALI_USER" -- bash -c "mkdir -p \"$dest_dir\"" 2>/dev/null
    while IFS= read -r -d '' file; do
        local rel_path="${file#$src_dir/}"
        push_file "$file" "$dest_dir/$rel_path"
        ((count++))
    done < <(find "$src_dir" -type f -print0 2>/dev/null)
    log "  Pushed $count files to $dest_dir"
}

echo ""
echo "=========================================="
echo "  Kali Anon Chain — Sync to Kali WSL"
echo "=========================================="
echo ""

# Check Kali is running
if ! wsl -d "$KALI_DISTRO" -- bash -c "echo ok" >/dev/null 2>&1; then
    err "Kali Linux WSL is not running. Start it first."
    exit 1
fi

# Create directory structure
log "Creating directory structure in Kali..."
wsl -d "$KALI_DISTRO" -u "$KALI_USER" -- bash -c "mkdir -p $KALI_BASE/{config,projects}"

# Sync project directory if specified
if [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ]; then
    log "Syncing project directory..."
    push_dir "$PROJECT_DIR" "$KALI_BASE/projects"
fi

# Optionally sync a named project's scope
if [ -n "$PROJECT_NAME" ]; then
    log "Syncing project: $PROJECT_NAME..."
    if [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR/$PROJECT_NAME" ]; then
        KALI_PROJECT_DIR="$KALI_BASE/projects/$PROJECT_NAME"
        wsl -d "$KALI_DISTRO" -u "$KALI_USER" -- bash -c "mkdir -p \"$KALI_PROJECT_DIR\""
        push_dir "$PROJECT_DIR/$PROJECT_NAME" "$KALI_PROJECT_DIR"
        log "Project '$PROJECT_NAME' pushed."
    else
        warn "Project directory not found. Skipping project sync."
    fi
fi

echo ""
log "Sync complete."
echo ""
