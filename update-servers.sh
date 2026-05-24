#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_DIR="$BASE_DIR/template"
SERVERS_DIR="$BASE_DIR/servers"
BACKUPS_DIR="$BASE_DIR/backups"

usage() {
    echo "Usage: $0"
    echo ""
    echo "Updates all deployed Minecraft Bedrock servers to the BDS version"
    echo "currently in the template/ directory."
    echo ""
    echo "Before running this script, update the template first:"
    echo "  ./setup-template.sh /path/to/new-bedrock-server.zip"
    exit 0
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
die()   { error "$1"; exit 1; }

if [[ ! -d "$TEMPLATE_DIR" ]]; then
    die "Template directory not found at: $TEMPLATE_DIR\nRun ./setup-template.sh first to create or update the template."
fi

if ! command -v rsync &>/dev/null; then
    die "'rsync' is not installed. Install it with: sudo apt install rsync"
fi

if [[ ! -d "$SERVERS_DIR" ]]; then
    info "No servers directory found. Nothing to update."
    exit 0
fi

server_dirs=()
for dir in "$SERVERS_DIR"/*/; do
    [[ -d "$dir" ]] && server_dirs+=("$dir")
done

if [[ ${#server_dirs[@]} -eq 0 ]]; then
    info "No servers found in $SERVERS_DIR. Nothing to update."
    exit 0
fi

info "Found ${#server_dirs[@]} server(s) to update."
echo ""

updated=()
skipped=()
backup_paths=()

TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"

for server_path in "${server_dirs[@]}"; do
    server_name="$(basename "$server_path")"
    screen_name="mc-${server_name}"

    echo "----------------------------------------------"
    info "Updating: $server_name"

    # Stop server
    if screen -list 2>/dev/null | grep -q "$screen_name"; then
        info "  Stopping server (screen: $screen_name)..."
        if [[ -x "$server_path/stop.sh" ]]; then
            "$server_path/stop.sh" >/dev/null 2>&1 || true
        else
            screen -S "$screen_name" -p 0 -X stuff "stop$(printf '\r')" 2>/dev/null || true
        fi

        elapsed=0
        while screen -list 2>/dev/null | grep -q "$screen_name"; do
            sleep 2
            elapsed=$((elapsed + 2))
            if [[ $elapsed -ge 30 ]]; then
                warn "  Server $server_name did not stop within 30 seconds. Skipping."
                skipped+=("$server_name (failed to stop)")
                continue 2
            fi
        done
        info "  Server stopped."
    else
        info "  Server is not running."
    fi

    # Backup
    backup_dest="$BACKUPS_DIR/$server_name/$TIMESTAMP"
    info "  Creating backup at: $backup_dest"
    mkdir -p "$backup_dest"
    if ! cp -r "$server_path"/* "$backup_dest"/ 2>/dev/null; then
        error "  Backup failed for $server_name. Skipping update."
        skipped+=("$server_name (backup failed)")
        # Restart server even though we skipped update
        if [[ -x "$server_path/start.sh" ]]; then
            "$server_path/start.sh" >/dev/null 2>&1 || true
        fi
        continue
    fi
    backup_paths+=("$backup_dest")
    info "  Backup complete."

    # Update BDS files
    info "  Copying new BDS files from template..."
    if ! rsync -a \
         --exclude='worlds' \
         --exclude='server.properties' \
         --exclude='permissions.json' \
         --exclude='allowlist.json' \
         --exclude='start.sh' \
         --exclude='stop.sh' \
         "$TEMPLATE_DIR/" "$server_path/"; then
        error "  Update failed for $server_name."
        skipped+=("$server_name (rsync failed)")
        # Restart with old files
        if [[ -x "$server_path/start.sh" ]]; then
            "$server_path/start.sh" >/dev/null 2>&1 || true
        fi
        continue
    fi
    info "  BDS files updated."

    # Restart server
    if [[ -x "$server_path/start.sh" ]]; then
        info "  Starting server..."
        "$server_path/start.sh" >/dev/null 2>&1 || true
        info "  Server started (screen: $screen_name)."
    else
        warn "  No start.sh found. Server not restarted."
    fi

    updated+=("$server_name")
    echo ""
done

echo ""
echo "=============================================="
info "Update complete!"
echo "=============================================="
echo ""

if [[ ${#updated[@]} -gt 0 ]]; then
    echo "  Updated servers:"
    for s in "${updated[@]}"; do
        echo "    - $s"
    done
    echo ""
fi

if [[ ${#skipped[@]} -gt 0 ]]; then
    echo "  Skipped servers:"
    for s in "${skipped[@]}"; do
        echo "    - $s"
    done
    echo ""
fi

if [[ ${#backup_paths[@]} -gt 0 ]]; then
    echo "  Backups:"
    for b in "${backup_paths[@]}"; do
        echo "    - $b"
    done
    echo ""
fi
