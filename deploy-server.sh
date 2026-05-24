#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_DIR="$BASE_DIR/template"
SERVERS_DIR="$BASE_DIR/servers"
ADDONS_DIR="$BASE_DIR/addons"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
die()   { error "$1"; exit 1; }

usage() {
    echo "Usage: $0 <config.yaml>"
    echo "       $0 --example"
    echo ""
    echo "Deploys a new Minecraft Bedrock server from the template."
    echo ""
    echo "Options:"
    echo "  <config.yaml>  Path to YAML config file for the new server"
    echo "  --example      Print a fully documented example config to stdout"
    echo "  -h, --help     Show this help message"
    exit 0
}

if [[ $# -eq 0 || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
fi

if [[ "${1:-}" == "--example" ]]; then
    cat <<'EXAMPLE_EOF'
# =============================================================================
# Minecraft Bedrock Server Configuration
# =============================================================================
# This file configures a new Bedrock Dedicated Server instance.
# All gameplay settings map directly to BDS server.properties.
# Only settings present in this file will be modified; others keep BDS defaults.
# =============================================================================

# --- Server Identity ---------------------------------------------------------

# The name shown in the server list when players search for servers.
server_name: "My Bedrock Server"

# Directory name for this server under the servers/ folder.
# This is NOT a full path — just the folder name (e.g. "my-server").
# The server will be created at: <base_dir>/servers/<server_dir>/
server_dir: "my-server"

# --- Network -----------------------------------------------------------------

# IPv4 port the server listens on. Each server on the same machine needs a
# unique port. Default Bedrock port is 19132.
server_port: 19132

# IPv6 port the server listens on. Must also be unique per server.
# Default is 19133.
server_port_v6: 19133

# --- Gameplay ----------------------------------------------------------------

# Default game mode for new players joining the server.
# Options: survival, creative, adventure
gamemode: survival

# World difficulty level.
# Options: peaceful, easy, normal, hard
difficulty: normal

# Maximum number of players that can be connected at the same time.
max_players: 10

# Name of the world / level. This determines the world save folder name
# inside the server directory (worlds/<level_name>/).
level_name: "Bedrock level"

# Seed for world generation. Leave empty ("") for a random seed.
# Only applies when the world is first created.
level_seed: ""

# Whether cheats (commands) are allowed for players.
# Options: true, false
allow_cheats: false

# Maximum view distance in chunks that the server will send to clients.
# Higher values use more memory and bandwidth. Range: 5-48.
view_distance: 32

# Whether players must have a valid Xbox Live account to connect.
# Set to false for LAN-only or offline servers.
# Options: true, false
online_mode: true

# --- Addons ------------------------------------------------------------------

# List of addon files to install from the addons/ directory.
# Supported formats:
#   .mcpack  - A single behavior pack or resource pack
#   .mcaddon - A bundle containing one or more .mcpack files
# The script reads each addon's manifest.json to determine the pack type
# and installs it in the correct location automatically.
# Remove or leave empty if no addons are needed.
addons: []
#  - example-map.mcaddon
#  - cool-textures.mcpack
EXAMPLE_EOF
    exit 0
fi

CONFIG_FILE="$1"

if [[ ! -f "$CONFIG_FILE" ]]; then
    die "Config file not found: $CONFIG_FILE"
fi

if ! command -v yq &>/dev/null; then
    die "yq is not installed. Run ./setup-template.sh first to install dependencies."
fi

if [[ ! -d "$TEMPLATE_DIR" ]]; then
    die "Template directory not found at: $TEMPLATE_DIR\nRun ./setup-template.sh first."
fi

yq_read() {
    yq eval "$1" "$CONFIG_FILE" 2>/dev/null
}

SERVER_NAME="$(yq_read '.server_name')"
SERVER_DIR="$(yq_read '.server_dir')"
SERVER_PORT="$(yq_read '.server_port')"

missing=""
[[ "$SERVER_NAME" == "null" || -z "$SERVER_NAME" ]] && missing="$missing server_name"
[[ "$SERVER_DIR" == "null" || -z "$SERVER_DIR" ]]   && missing="$missing server_dir"
[[ "$SERVER_PORT" == "null" || -z "$SERVER_PORT" ]]  && missing="$missing server_port"

if [[ -n "$missing" ]]; then
    die "Missing required fields in config:$missing"
fi

TARGET_DIR="$SERVERS_DIR/$SERVER_DIR"

if [[ -d "$TARGET_DIR" ]]; then
    die "Server directory already exists: $TARGET_DIR\nChoose a different server_dir or remove the existing directory."
fi

info "Deploying server '$SERVER_NAME' to $TARGET_DIR..."

info "Copying template..."
cp -r "$TEMPLATE_DIR" "$TARGET_DIR"

info "Configuring server.properties..."

PROPERTIES_FILE="$TARGET_DIR/server.properties"

if [[ ! -f "$PROPERTIES_FILE" ]]; then
    die "server.properties not found in template. Is the template valid?"
fi

update_property() {
    local key="$1"
    local yaml_path="$2"
    local value
    value="$(yq_read "$yaml_path")"
    if [[ "$value" != "null" && -n "$value" ]]; then
        if grep -q "^${key}=" "$PROPERTIES_FILE"; then
            sed -i "s|^${key}=.*|${key}=${value}|" "$PROPERTIES_FILE"
        else
            echo "${key}=${value}" >> "$PROPERTIES_FILE"
        fi
    fi
}

update_property "server-name"   ".server_name"
update_property "server-port"   ".server_port"
update_property "server-portv6" ".server_port_v6"
update_property "gamemode"      ".gamemode"
update_property "difficulty"    ".difficulty"
update_property "max-players"   ".max_players"
update_property "level-name"    ".level_name"
update_property "level-seed"    ".level_seed"
update_property "allow-cheats"  ".allow_cheats"
update_property "view-distance" ".view_distance"
update_property "online-mode"   ".online_mode"
