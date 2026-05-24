# Update Servers Script — Design Spec

## Overview

A bash script that updates all deployed Minecraft Bedrock servers to a new BDS version by copying updated binaries from the template directory, while preserving world data, configuration, and addons.

## Prerequisites

The user must first update the template by running `setup-template.sh` with the new BDS zip. Then `update-servers.sh` applies that updated template to all deployed servers.

## Usage

```bash
# Step 1: Update the template
./setup-template.sh /path/to/new-bedrock-server.zip

# Step 2: Update all servers
./update-servers.sh
```

## Script: update-servers.sh

### Behavior

1. Verify `template/` exists (error if not).
2. Verify `servers/` exists and contains at least one server directory.
3. For each subdirectory in `servers/`:
   a. Stop the server via its `stop.sh` script.
   b. Wait for the screen session to terminate (poll with timeout).
   c. Create a backup to `backups/<server-dir>/<YYYY-MM-DD_HH-MM-SS>/` (full copy).
   d. Copy new BDS files from `template/` to the server directory, skipping preserved files/directories.
   e. Restart the server via its `start.sh` script.
4. Print a summary of updated servers.

### Preserved Files (not overwritten)

These files and directories are NOT replaced during the update — they contain user data and configuration:

- `worlds/` — world save data
- `server.properties` — server configuration
- `permissions.json` — operator permissions
- `allowlist.json` — player allowlist
- `start.sh` — generated start script
- `stop.sh` — generated stop script
- Custom packs installed in `behavior_packs/` and `resource_packs/` that don't exist in the template

### Shutdown and Restart

- Stop: execute the server's `stop.sh` script, then poll `screen -list` every 2 seconds for up to 30 seconds waiting for the session to disappear.
- If the session doesn't stop within 30 seconds, warn and skip that server (don't force-kill).
- Start: execute the server's `start.sh` script after the update is complete.

### Backup

- Destination: `backups/<server-dir>/<YYYY-MM-DD_HH-MM-SS>/`
- Full copy of the server directory before any modifications.
- The `backups/` directory is created automatically if it doesn't exist.

### Update Strategy

Use `rsync` to copy template files to the server directory with exclusions:

```bash
rsync -a --exclude='worlds' \
         --exclude='server.properties' \
         --exclude='permissions.json' \
         --exclude='allowlist.json' \
         --exclude='start.sh' \
         --exclude='stop.sh' \
         template/ servers/<server-dir>/
```

This replaces all BDS binaries and default packs while preserving user data. Custom behavior/resource packs that were installed by `deploy-server.sh` (not present in the template) survive because `rsync` without `--delete` only adds/updates files, never removes.

### Error Handling

- Missing template: error pointing to `setup-template.sh`.
- Empty servers directory: info message, exit cleanly.
- Server won't stop: warn, skip that server, continue with the rest.
- Backup failure: error, skip that server (don't update without backup).
- rsync failure: error, report which server failed, continue with the rest.

### Summary Output

After all servers are processed, print:
- List of successfully updated servers
- List of skipped servers (with reason)
- Backup locations
