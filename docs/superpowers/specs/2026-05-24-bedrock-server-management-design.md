# Minecraft Bedrock Server Management Scripts — Design Spec

## Overview

Two bash scripts for managing Minecraft Bedrock Dedicated Server (BDS) instances on Ubuntu/Debian Linux. Automates the repetitive process of setting up new servers with consistent configuration and addon support.

## Target Environment

- **OS:** Ubuntu/Debian Linux
- **Server software:** Official Minecraft Bedrock Dedicated Server (BDS)
- **Process management:** Screen sessions, with cron-based watchdog
- **Addons:** .mcpack and .mcaddon files (maps, behavior packs, resource packs)
- **Dependencies:** curl, unzip, screen, yq (auto-installed if missing)

## Directory Structure

```
<BASE_DIR>/                        # Configurable base path
├── setup-template.sh              # Script 1: create/update template
├── deploy-server.sh               # Script 2: deploy new server from template
├── template/                      # Clean BDS installation
├── addons/                        # Shared .mcpack/.mcaddon files
│   ├── oneblock.mcaddon
│   └── texture-pack.mcpack
├── configs/                       # YAML server config files
│   ├── survival.yaml
│   └── oneblock.yaml
└── servers/                       # Deployed server instances
    ├── survival-server/
    │   ├── start.sh
    │   ├── stop.sh
    │   └── ... (BDS files)
    └── oneblock-server/
```

## Config File Format (YAML)

The config file must be fully self-documenting. Every setting includes a YAML comment explaining what it does, valid values, and defaults. The `deploy-server.sh` script generates a documented example config when run with `--example`.

```yaml
# =============================================================================
# Minecraft Bedrock Server Configuration
# =============================================================================
# This file configures a new Bedrock Dedicated Server instance.
# All gameplay settings map directly to BDS server.properties.
# Only settings present in this file will be modified; others keep BDS defaults.
# =============================================================================

# --- Server Identity ---------------------------------------------------------

# The name shown in the server list when players search for servers.
server_name: "One Block Server"

# Directory name for this server under the servers/ folder.
# This is NOT a full path — just the folder name (e.g. "oneblock-server").
# The server will be created at: <base_dir>/servers/<server_dir>/
server_dir: "oneblock-server"

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
level_name: "One Block World"

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
addons:
  - oneblock.mcaddon
  - cool-textures.mcpack
```

All gameplay fields map directly to BDS `server.properties` entries. `server_dir` determines the subdirectory name under `servers/`. `addons` is a list of filenames that must exist in the `addons/` directory. Only fields present in the YAML are modified in server.properties — omitted fields keep BDS defaults.

## Script 1: setup-template.sh

**Purpose:** Download the official BDS and create a clean template directory.

**Usage:**
```bash
./setup-template.sh [DOWNLOAD_URL]
```

**Behavior:**
1. Check dependencies (curl, unzip, screen). Install yq if missing (downloads binary from GitHub).
2. If no URL argument provided, prompt the user for the BDS download URL. The URL must be obtained manually from https://www.minecraft.net/en-us/download/server/bedrock because Mojang requires ToS acceptance.
3. If `template/` already exists, ask for confirmation before replacing.
4. Download the BDS zip file to a temporary location.
5. Extract to `template/`.
6. Create `addons/`, `configs/`, and `servers/` directories if they don't exist.
7. Print success message with next steps.

**Notes:**
- The download URL looks like: `https://minecraft.azureedge.net/bin-linux/bedrock-server-X.XX.XX.XX.zip`
- The template is a vanilla BDS installation — no config modifications.

## Script 2: deploy-server.sh

**Purpose:** Deploy a new server instance from the template using a YAML config file.

**Usage:**
```bash
./deploy-server.sh <config.yaml>
```

**Behavior:**

### Step 1: Validate
- Check that `template/` exists (error if not — run setup-template.sh first).
- Parse the YAML config using yq.
- Validate required fields: `server_name`, `server_dir`, `server_port`.
- Check that `servers/<server_dir>/` does not already exist (error with message).

### Step 2: Copy template
- Copy `template/` to `servers/<server_dir>/`.

### Step 3: Configure server.properties
- Read the template `server.properties`.
- Replace values based on YAML config fields:
  - `server_name` → `server-name`
  - `server_port` → `server-port`
  - `server_port_v6` → `server-portv6`
  - `gamemode` → `gamemode`
  - `difficulty` → `difficulty`
  - `max_players` → `max-players`
  - `level_name` → `level-name`
  - `level_seed` → `level-seed`
  - `allow_cheats` → `allow-cheats`
  - `view_distance` → `view-distance`
  - `online_mode` → `online-mode`
- Only modify fields that are present in the YAML config; leave others at BDS defaults.

### Step 4: Install addons
For each addon listed in the `addons` YAML array:

1. Verify the file exists in `addons/`.
2. Determine type by extension:
   - `.mcaddon`: extract the outer zip, then process each inner `.mcpack` separately.
   - `.mcpack`: process directly.
3. For each `.mcpack`:
   - Extract to a temp directory.
   - Read `manifest.json` to get the pack UUID, version, and module type.
   - Module type `data` → behavior pack. Module type `resources` → resource pack.
   - Copy the extracted pack to `behavior_packs/<pack_name>/` or `resource_packs/<pack_name>/`.
4. After all packs are extracted, generate:
   - `worlds/<level_name>/world_behavior_packs.json` with entries for each behavior pack (UUID + version from manifest).
   - `worlds/<level_name>/world_resource_packs.json` with entries for each resource pack.
   - Create the `worlds/<level_name>/` directory if it doesn't exist yet.

### Step 5: Generate start.sh
```bash
#!/bin/bash
SERVER_DIR="<absolute path to this server>"
SCREEN_NAME="mc-<server_dir>"

if screen -list | grep -q "$SCREEN_NAME"; then
    echo "Server is already running in screen session: $SCREEN_NAME"
    exit 0
fi

cd "$SERVER_DIR"
screen -dmS "$SCREEN_NAME" ./bedrock_server
echo "Server started in screen session: $SCREEN_NAME"
```

This script is safe to call from cron — it exits cleanly if the server is already running.

### Step 6: Generate stop.sh
```bash
#!/bin/bash
SCREEN_NAME="mc-<server_dir>"

if ! screen -list | grep -q "$SCREEN_NAME"; then
    echo "Server is not running."
    exit 0
fi

screen -S "$SCREEN_NAME" -p 0 -X stuff "stop$(printf '\r')"
echo "Stop command sent to $SCREEN_NAME. Server is shutting down."
```

### Step 7: Print summary
- Server location
- Port
- Installed addons
- How to start: `./servers/<server_dir>/start.sh`
- How to stop: `./servers/<server_dir>/stop.sh`
- Suggested cron entry: `* * * * * /path/to/servers/<server_dir>/start.sh > /dev/null 2>&1`

## Error Handling

- Missing dependencies: clear error message with install instructions.
- Missing template: error pointing to setup-template.sh.
- Server directory already exists: error, do not overwrite.
- Missing addon file: error listing which file was not found in addons/.
- Invalid manifest.json in addon: warning, skip that addon, continue with the rest.
- Missing required YAML fields: error listing which fields are missing.

## Out of Scope

- Server updates (updating BDS version for existing servers).
- Backup management.
- Multi-machine deployment.
- Docker/container support.
- Automatic BDS download URL detection (requires ToS acceptance).
