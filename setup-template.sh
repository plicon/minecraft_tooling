#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_DIR="$BASE_DIR/template"

usage() {
    echo "Usage: $0 <path-to-zip | download-url>"
    echo ""
    echo "Creates a template directory from the official Minecraft Bedrock"
    echo "Dedicated Server for deploying new server instances."
    echo ""
    echo "Accepts either:"
    echo "  - A local .zip file path (e.g. ./bedrock-server-1.21.62.01.zip)"
    echo "  - A download URL"
    echo ""
    echo "If no argument is provided, you will be prompted to enter a path or URL."
    echo "Download the server from: https://www.minecraft.net/en-us/download/server/bedrock"
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
    arch="$(dpkg --print-architecture 2>/dev/null || { warn "dpkg not found, assuming amd64"; echo "amd64"; })"
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

check_dependency "curl" "sudo apt install curl"
check_dependency "unzip" "sudo apt install unzip"
check_dependency "screen" "sudo apt install screen"
install_yq

SOURCE="${1:-}"

if [[ -z "$SOURCE" ]]; then
    echo ""
    echo "No argument provided."
    echo "Download the server zip from: https://www.minecraft.net/en-us/download/server/bedrock"
    echo "Then provide the path to the zip file, or paste a download URL."
    echo ""
    read -rp "Path or URL: " SOURCE
fi

if [[ -z "$SOURCE" ]]; then
    die "No path or URL provided."
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

if [[ -f "$SOURCE" ]]; then
    ZIP_FILE="$SOURCE"
    info "Using local file: $ZIP_FILE"
else
    ZIP_FILE="$(mktemp /tmp/bedrock-server-XXXXXX.zip)"
    trap 'rm -f "$ZIP_FILE"' EXIT
    info "Downloading Bedrock Dedicated Server..."
    if ! curl -fSL "$SOURCE" -o "$ZIP_FILE"; then
        die "Download failed. Check the URL and try again."
    fi
fi

info "Extracting to $TEMPLATE_DIR..."
mkdir -p "$TEMPLATE_DIR"
if ! unzip -qo "$ZIP_FILE" -d "$TEMPLATE_DIR"; then
    rm -rf "$TEMPLATE_DIR"
    die "Extraction failed. Is this a valid zip file?"
fi

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
