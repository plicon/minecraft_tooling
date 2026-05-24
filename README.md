# Minecraft Bedrock Server Management

Two scripts for managing Minecraft Bedrock Dedicated Server (BDS) instances on Ubuntu/Debian Linux. Automates the repetitive process of setting up new servers with consistent configuration and addon support.

## Prerequisites

- Ubuntu/Debian Linux
- `curl`, `unzip`, `screen` (installed via `apt`)
- `yq` (auto-installed by `setup-template.sh` if missing)

## Quick Start

### 1. Create the template

Download the BDS zip from [minecraft.net](https://www.minecraft.net/en-us/download/server/bedrock) and point the script at the local file:

```bash
./setup-template.sh /path/to/bedrock-server-1.21.62.01.zip
```

A download URL also works if you have one:

```bash
./setup-template.sh "https://minecraft.azureedge.net/bin-linux/bedrock-server-X.XX.XX.XX.zip"
```

Or run without arguments to be prompted interactively:

```bash
./setup-template.sh
```

### 2. Create a server config

Generate a fully documented example config:

```bash
./deploy-server.sh --example > configs/my-server.yaml
```

Edit the file with your settings (server name, port, gamemode, etc.). Every setting is documented with comments explaining what it does and which values are valid.

### 3. Import a world (optional)

To use a pre-made world (e.g. a One Block map from CurseForge), place the `.mcworld` file in the `addons/` directory and reference it in your config:

```bash
cp oneblock.mcworld addons/
```

```yaml
level_name: "One Block World"
world_file: "oneblock.mcworld"
```

The `.mcworld` is extracted to `worlds/<level_name>/` and replaces any auto-generated world.

### 4. Add addons (optional)

Place your `.mcpack` and `.mcaddon` files in the `addons/` directory:

```bash
cp oneblock.mcaddon addons/
cp cool-textures.mcpack addons/
```

Then reference them in your config:

```yaml
addons:
  - oneblock.mcaddon
  - cool-textures.mcpack
```

The script reads each addon's `manifest.json` to determine the pack type (behavior or resource) and installs it in the correct location automatically.

### 5. Deploy the server

```bash
./deploy-server.sh configs/my-server.yaml
```

This will:
- Copy the template to `servers/<server_dir>/`
- Apply your config to `server.properties`
- Install any configured addons
- Generate `start.sh` and `stop.sh` scripts

### 6. Start the server

```bash
./servers/my-server/start.sh
```

The server runs in a `screen` session. To attach:

```bash
screen -r mc-my-server
```

To detach from the screen session: press `Ctrl+A` then `D`.

### 7. Stop the server

```bash
./servers/my-server/stop.sh
```

### 8. Auto-restart with cron (optional)

The `start.sh` script is safe to call repeatedly -- it exits cleanly if the server is already running. Add a cron entry to restart the server if it crashes:

```bash
crontab -e
```

Add:

```
* * * * * /path/to/servers/my-server/start.sh > /dev/null 2>&1
```

## Updating Servers

When a new BDS version is released, update all servers in two steps:

```bash
# 1. Update the template with the new BDS zip
./setup-template.sh /path/to/new-bedrock-server.zip

# 2. Update all deployed servers
./update-servers.sh
```

The update script will, for each server:
1. Stop the server gracefully
2. Create a backup in `backups/<server-dir>/<timestamp>/`
3. Copy new BDS files from the template (preserving worlds, config, and addons)
4. Restart the server

If a server fails to stop within 30 seconds, it is skipped. If a backup fails, the server is skipped and restarted with the old files.

## Directory Structure

```
.
├── setup-template.sh          # Creates/updates the BDS template
├── deploy-server.sh           # Deploys new servers from the template
├── update-servers.sh          # Updates all servers to new BDS version
├── template/                  # Clean BDS installation (created by setup-template.sh)
├── addons/                    # Shared .mcpack/.mcaddon/.mcworld files
├── backups/                   # Server backups (created by update-servers.sh)
├── configs/                   # Server config files (YAML)
│   └── example.yaml
└── servers/                   # Deployed server instances
    └── my-server/
        ├── start.sh
        ├── stop.sh
        └── ... (BDS files)
```

## Deploying Multiple Servers

Each server needs a unique port. Create a separate config for each:

```bash
./deploy-server.sh --example > configs/survival.yaml
./deploy-server.sh --example > configs/creative.yaml
```

Edit each with different `server_name`, `server_dir`, and `server_port` values, then deploy:

```bash
./deploy-server.sh configs/survival.yaml
./deploy-server.sh configs/creative.yaml
```
