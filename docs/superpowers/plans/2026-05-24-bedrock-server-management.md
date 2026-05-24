# Bedrock Server Management Scripts — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two bash scripts that automate creating a Bedrock Dedicated Server template and deploying configured server instances from it on Ubuntu/Debian Linux.

**Architecture:** Script 1 (`setup-template.sh`) downloads and extracts the official BDS to a template directory. Script 2 (`deploy-server.sh`) copies that template, applies YAML config (parsed with `yq`), installs .mcpack/.mcaddon addons by reading their manifest.json, and generates screen-based start/stop scripts. Both scripts resolve BASE_DIR from their own location.

**Tech Stack:** Bash, yq (YAML parser), curl, unzip, screen

**Spec:** `docs/superpowers/specs/2026-05-24-bedrock-server-management-design.md`

---

## File Structure

| File | Responsibility |
|------|---------------|
| `setup-template.sh` | Download BDS, extract to template/, create directory structure, install yq if missing |
| `deploy-server.sh` | Parse YAML config, copy template, configure server.properties, install addons, generate start/stop scripts |
| `configs/example.yaml` | Fully documented example config with all available settings |

---

### Task 1: Create setup-template.sh

**Files:**
- Create: `setup-template.sh`

This script handles dependency checking, yq auto-installation, BDS download, and template extraction.

- [ ] **Step 1: Create setup-template.sh with shebang, BASE_DIR, and usage**

```bash
#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_DIR="$BASE_DIR/template"

usage() {
    echo "Usage: $0 [DOWNLOAD_URL]"
    echo ""
    echo "Downloads the official Minecraft Bedrock Dedicated Server and creates"
    echo "a template directory for deploying new server instances."
    echo ""
    echo "If DOWNLOAD_URL is not provided, you will be prompted to enter it."
    echo "Get the URL from: https://www.minecraft.net/en-us/download/server/bedrock"
    exit 1
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
fi
```

- [ ] **Step 2: Add dependency checking functions**

After the `usage` function, add:

```bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
die()   { error "$1"; exit 1; }

check_dependency() {
    local cmd="$1"
    local install_hint="$2"
    if ! command -v "$cmd" &>/dev/null; then
        die "'$cmd' is not installed. Install it with: $install_hint"
    fi
}

install_yq() {
    if command -v yq &>/dev/null; then
        info "yq is already installed."
        return 0
    fi

    info "Installing yq..."
    local yq_version="v4.44.1"
    local arch
    arch="$(dpkg --print-architecture 2>/dev/null || echo "amd64")"
    local yq_url="https://github.com/mikefarah/yq/releases/download/${yq_version}/yq_linux_${arch}"

    if [[ -w /usr/local/bin ]]; then
        curl -fsSL "$yq_url" -o /usr/local/bin/yq
        chmod +x /usr/local/bin/yq
    else
        sudo curl -fsSL "$yq_url" -o /usr/local/bin/yq
        sudo chmod +x /usr/local/bin/yq
    fi

    if ! command -v yq &>/dev/null; then
        die "Failed to install yq. Please install it manually: https://github.com/mikefarah/yq"
    fi
    info "yq installed successfully."
}
```

- [ ] **Step 3: Add main logic — download and extract BDS**

After the helper functions, add the main logic:

```bash
check_dependency "curl" "sudo apt install curl"
check_dependency "unzip" "sudo apt install unzip"
check_dependency "screen" "sudo apt install screen"
install_yq

DOWNLOAD_URL="${1:-}"

if [[ -z "$DOWNLOAD_URL" ]]; then
    echo ""
    echo "No download URL provided."
    echo "Go to https://www.minecraft.net/en-us/download/server/bedrock"
    echo "Accept the terms, copy the Linux download URL, and paste it below."
    echo ""
    read -rp "Download URL: " DOWNLOAD_URL
fi

if [[ -z "$DOWNLOAD_URL" ]]; then
    die "No download URL provided."
fi

if [[ -d "$TEMPLATE_DIR" ]]; then
    warn "Template directory already exists at: $TEMPLATE_DIR"
    read -rp "Replace it? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        info "Aborted."
        exit 0
    fi
    rm -rf "$TEMPLATE_DIR"
fi

TMP_ZIP="$(mktemp /tmp/bedrock-server-XXXXXX.zip)"
trap 'rm -f "$TMP_ZIP"' EXIT

info "Downloading Bedrock Dedicated Server..."
if ! curl -fSL "$DOWNLOAD_URL" -o "$TMP_ZIP"; then
    die "Download failed. Check the URL and try again."
fi

info "Extracting to $TEMPLATE_DIR..."
mkdir -p "$TEMPLATE_DIR"
unzip -qo "$TMP_ZIP" -d "$TEMPLATE_DIR"

mkdir -p "$BASE_DIR/addons"
mkdir -p "$BASE_DIR/configs"
mkdir -p "$BASE_DIR/servers"

echo ""
info "Template created successfully at: $TEMPLATE_DIR"
echo ""
echo "Next steps:"
echo "  1. Place your .mcpack/.mcaddon files in: $BASE_DIR/addons/"
echo "  2. Create a config file: ./deploy-server.sh --example > configs/my-server.yaml"
echo "  3. Edit the config file with your settings"
echo "  4. Deploy: ./deploy-server.sh configs/my-server.yaml"
```

- [ ] **Step 4: Make executable and commit**

```bash
chmod +x setup-template.sh
git add setup-template.sh
git commit -m "feat: add setup-template.sh for BDS template creation"
```

---

### Task 2: Create deploy-server.sh — config parsing, validation, and template copy

**Files:**
- Create: `deploy-server.sh`

- [ ] **Step 1: Create deploy-server.sh with shebang, BASE_DIR, helpers, and usage**

```bash
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
    exit 1
}

if [[ $# -eq 0 || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
fi
```

- [ ] **Step 2: Add --example flag handler**

After the `usage` function call block, add:

```bash
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
```

- [ ] **Step 3: Add config parsing and validation**

After the `--example` block, add:

```bash
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
```

- [ ] **Step 4: Add template copy**

```bash
info "Deploying server '$SERVER_NAME' to $TARGET_DIR..."

info "Copying template..."
cp -r "$TEMPLATE_DIR" "$TARGET_DIR"
```

- [ ] **Step 5: Commit**

```bash
git add deploy-server.sh
git commit -m "feat: add deploy-server.sh with config parsing, validation, and --example"
```

---

### Task 3: Add server.properties configuration to deploy-server.sh

**Files:**
- Modify: `deploy-server.sh`

- [ ] **Step 1: Add server.properties update function**

After the template copy line (`cp -r "$TEMPLATE_DIR" "$TARGET_DIR"`), add:

```bash
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
```

- [ ] **Step 2: Commit**

```bash
git add deploy-server.sh
git commit -m "feat: add server.properties configuration from YAML"
```

---

### Task 4: Add addon installation to deploy-server.sh

**Files:**
- Modify: `deploy-server.sh`

- [ ] **Step 1: Add addon installation logic**

After the `update_property` calls, add:

```bash
LEVEL_NAME="$(yq_read '.level_name')"
if [[ "$LEVEL_NAME" == "null" || -z "$LEVEL_NAME" ]]; then
    LEVEL_NAME="Bedrock level"
fi

ADDON_COUNT="$(yq_read '.addons | length')"
BEHAVIOR_PACKS_JSON="[]"
RESOURCE_PACKS_JSON="[]"

install_mcpack() {
    local pack_path="$1"
    local tmp_extract
    tmp_extract="$(mktemp -d)"

    if ! unzip -qo "$pack_path" -d "$tmp_extract" 2>/dev/null; then
        warn "Failed to extract: $(basename "$pack_path"). Skipping."
        rm -rf "$tmp_extract"
        return 1
    fi

    local manifest="$tmp_extract/manifest.json"
    if [[ ! -f "$manifest" ]]; then
        local nested
        nested="$(find "$tmp_extract" -name "manifest.json" -maxdepth 2 | head -1)"
        if [[ -n "$nested" ]]; then
            manifest="$nested"
            tmp_extract="$(dirname "$nested")"
        else
            warn "No manifest.json found in: $(basename "$pack_path"). Skipping."
            rm -rf "$tmp_extract"
            return 1
        fi
    fi

    local uuid version_array module_type pack_name
    uuid="$(yq eval '.header.uuid' "$manifest" 2>/dev/null)"
    version_array="$(yq eval '.header.version' "$manifest" 2>/dev/null)"
    module_type="$(yq eval '.modules[0].type' "$manifest" 2>/dev/null)"
    pack_name="$(yq eval '.header.name' "$manifest" 2>/dev/null)"

    if [[ "$uuid" == "null" || -z "$uuid" ]]; then
        warn "Invalid manifest in: $(basename "$pack_path"). Skipping."
        rm -rf "$tmp_extract"
        return 1
    fi

    if [[ "$pack_name" == "null" || -z "$pack_name" ]]; then
        pack_name="$(basename "$pack_path" | sed 's/\.\(mcpack\|mcaddon\)$//')"
    fi

    local safe_name
    safe_name="$(echo "$pack_name" | tr ' ' '_' | tr -cd '[:alnum:]_-')"

    local dest_type
    if [[ "$module_type" == "data" || "$module_type" == "script" ]]; then
        dest_type="behavior_packs"
        BEHAVIOR_PACKS_JSON="$(echo "$BEHAVIOR_PACKS_JSON" | yq eval ". + [{\"pack_id\": \"$uuid\", \"version\": $version_array}]")"
    else
        dest_type="resource_packs"
        RESOURCE_PACKS_JSON="$(echo "$RESOURCE_PACKS_JSON" | yq eval ". + [{\"pack_id\": \"$uuid\", \"version\": $version_array}]")"
    fi

    local dest_dir="$TARGET_DIR/$dest_type/$safe_name"
    rm -rf "$dest_dir"
    cp -r "$tmp_extract" "$dest_dir"

    info "  Installed $dest_type pack: $pack_name ($uuid)"
    rm -rf "$tmp_extract"
    return 0
}

if [[ "$ADDON_COUNT" != "0" && "$ADDON_COUNT" != "null" ]]; then
    info "Installing addons..."

    for i in $(seq 0 $((ADDON_COUNT - 1))); do
        addon_file="$(yq_read ".addons[$i]")"
        addon_path="$ADDONS_DIR/$addon_file"

        if [[ ! -f "$addon_path" ]]; then
            warn "Addon file not found: $addon_path. Skipping."
            continue
        fi

        if [[ "$addon_file" == *.mcaddon ]]; then
            mcaddon_tmp="$(mktemp -d)"
            if ! unzip -qo "$addon_path" -d "$mcaddon_tmp" 2>/dev/null; then
                warn "Failed to extract mcaddon: $addon_file. Skipping."
                rm -rf "$mcaddon_tmp"
                continue
            fi

            found_packs=0
            while IFS= read -r inner_pack; do
                install_mcpack "$inner_pack" && ((found_packs++)) || true
            done < <(find "$mcaddon_tmp" -name "*.mcpack" -type f 2>/dev/null)

            if [[ "$found_packs" -eq 0 ]]; then
                local has_manifest
                has_manifest="$(find "$mcaddon_tmp" -name "manifest.json" -maxdepth 2 | head -1)"
                if [[ -n "$has_manifest" ]]; then
                    install_mcpack "$addon_path" || true
                else
                    warn "No packs found in mcaddon: $addon_file"
                fi
            fi

            rm -rf "$mcaddon_tmp"

        elif [[ "$addon_file" == *.mcpack ]]; then
            install_mcpack "$addon_path" || true
        else
            warn "Unknown addon format: $addon_file. Supported: .mcpack, .mcaddon"
        fi
    done

    WORLD_DIR="$TARGET_DIR/worlds/$LEVEL_NAME"
    mkdir -p "$WORLD_DIR"

    if [[ "$BEHAVIOR_PACKS_JSON" != "[]" ]]; then
        echo "$BEHAVIOR_PACKS_JSON" | yq eval -o=json > "$WORLD_DIR/world_behavior_packs.json"
    fi
    if [[ "$RESOURCE_PACKS_JSON" != "[]" ]]; then
        echo "$RESOURCE_PACKS_JSON" | yq eval -o=json > "$WORLD_DIR/world_resource_packs.json"
    fi
else
    info "No addons configured."
fi
```

- [ ] **Step 2: Commit**

```bash
git add deploy-server.sh
git commit -m "feat: add addon installation (.mcpack/.mcaddon) to deploy-server.sh"
```

---

### Task 5: Add start/stop script generation and summary to deploy-server.sh

**Files:**
- Modify: `deploy-server.sh`

- [ ] **Step 1: Add start.sh generation**

After the addon installation block, add:

```bash
SCREEN_NAME="mc-${SERVER_DIR}"

info "Generating start.sh..."
cat > "$TARGET_DIR/start.sh" <<STARTEOF
#!/bin/bash
SERVER_DIR="$TARGET_DIR"
SCREEN_NAME="$SCREEN_NAME"

if screen -list | grep -q "\$SCREEN_NAME"; then
    echo "Server is already running in screen session: \$SCREEN_NAME"
    exit 0
fi

cd "\$SERVER_DIR"
LD_LIBRARY_PATH=. screen -dmS "\$SCREEN_NAME" ./bedrock_server
echo "Server started in screen session: \$SCREEN_NAME"
STARTEOF
chmod +x "$TARGET_DIR/start.sh"
```

- [ ] **Step 2: Add stop.sh generation**

```bash
info "Generating stop.sh..."
cat > "$TARGET_DIR/stop.sh" <<STOPEOF
#!/bin/bash
SCREEN_NAME="$SCREEN_NAME"

if ! screen -list | grep -q "\$SCREEN_NAME"; then
    echo "Server is not running."
    exit 0
fi

screen -S "\$SCREEN_NAME" -p 0 -X stuff "stop\$(printf '\r')"
echo "Stop command sent to \$SCREEN_NAME. Server is shutting down."
STOPEOF
chmod +x "$TARGET_DIR/stop.sh"
```

- [ ] **Step 3: Add summary output**

```bash
echo ""
echo "=============================================="
info "Server deployed successfully!"
echo "=============================================="
echo ""
echo "  Server name:  $SERVER_NAME"
echo "  Location:     $TARGET_DIR"
echo "  Port (IPv4):  $SERVER_PORT"
echo "  Screen name:  $SCREEN_NAME"
echo ""
echo "  Start:  $TARGET_DIR/start.sh"
echo "  Stop:   $TARGET_DIR/stop.sh"
echo ""
echo "  Cron watchdog (restarts if not running):"
echo "  * * * * * $TARGET_DIR/start.sh > /dev/null 2>&1"
echo ""
```

- [ ] **Step 4: Make executable and commit**

```bash
chmod +x deploy-server.sh
git add deploy-server.sh
git commit -m "feat: add start/stop script generation and deployment summary"
```

---

### Task 6: Create example config and final commit

**Files:**
- Create: `configs/example.yaml`

- [ ] **Step 1: Generate example config using the --example flag**

```bash
mkdir -p configs
./deploy-server.sh --example > configs/example.yaml
```

- [ ] **Step 2: Commit example config**

```bash
git add configs/example.yaml
git commit -m "feat: add documented example server config"
```

---

### Task 7: Verify and clean up

- [ ] **Step 1: Verify both scripts are executable and parse cleanly**

```bash
bash -n setup-template.sh
bash -n deploy-server.sh
ls -la setup-template.sh deploy-server.sh
```

Expected: no syntax errors, both files have execute permissions.

- [ ] **Step 2: Verify --example output**

```bash
./deploy-server.sh --example
```

Expected: fully documented YAML config printed to stdout.

- [ ] **Step 3: Verify --help on both scripts**

```bash
./setup-template.sh --help
./deploy-server.sh --help
```

Expected: usage information printed for both scripts.

- [ ] **Step 4: Final commit if any cleanup needed**

```bash
git status
# If clean, no commit needed
```
