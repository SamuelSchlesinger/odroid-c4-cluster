#!/usr/bin/env bash
# Deploy NixOS configuration to all cluster nodes
# Usage: ./deploy-all-nodes.sh <node_number>
#
# This script is designed to be run ON node1, which acts as the build host.
# It builds the configuration for the target node, copies the closure,
# and switches to the new configuration.
#
# The "nixy way": Build once, distribute the closure, avoiding redundant downloads.

set -euo pipefail

NODE_NUM="${1:-}"
CONFIG_DIR="/tmp/nixos-config"

if [[ -z "$NODE_NUM" ]]; then
    echo "Usage: $0 <node_number>"
    echo "Example: $0 2"
    exit 1
fi

NODE_NAME="node${NODE_NUM}"
TARGET_HOST="${NODE_NAME}.local"

echo "=== Deploying to ${NODE_NAME} ==="

# Step 1: Build the configuration for this node (uses cached packages from node1 build)
echo "[1/3] Building configuration for ${NODE_NAME}..."
SYSTEM_PATH=$(nix build "${CONFIG_DIR}#nixosConfigurations.${NODE_NAME}.config.system.build.toplevel" --no-link --print-out-paths)
echo "Built: ${SYSTEM_PATH}"

if [[ "$NODE_NUM" == "1" ]]; then
    # Node1 is local, just switch directly
    echo "[2/3] Skipping copy (local node)"
    echo "[3/3] Switching to new configuration..."
    sudo nix-env -p /nix/var/nix/profiles/system --set "${SYSTEM_PATH}"
    sudo "${SYSTEM_PATH}/bin/switch-to-configuration" switch
else
    # Remote node: copy closure and switch
    echo "[2/3] Copying closure to ${TARGET_HOST}..."
    nix copy --to "ssh://admin@${TARGET_HOST}" "${SYSTEM_PATH}"

    echo "[3/3] Switching ${NODE_NAME} to new configuration..."
    ssh "admin@${TARGET_HOST}" "sudo nix-env -p /nix/var/nix/profiles/system --set '${SYSTEM_PATH}' && sudo '${SYSTEM_PATH}/bin/switch-to-configuration' switch"
fi

echo "=== ${NODE_NAME} deployment complete ==="
