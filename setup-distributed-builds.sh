#!/usr/bin/env bash
# Set up distributed builds across the cluster
# Run from MacBook through desktop jump host
#
# This script distributes:
# 1. Root SSH key (for nix-daemon to SSH between nodes)
# 2. Cache signing key (for signing/trusting builds)

set -euo pipefail

KEY_DIR="$HOME/.ssh/odroid-cluster"
JUMP_HOST="samuel@desktop"

setup_node() {
    local node_num=$1
    local node_name="node${node_num}"
    local target="admin@${node_name}.local"

    echo "=== Setting up distributed builds on ${node_name} ==="

    # Create root .ssh directory
    ssh -J "$JUMP_HOST" "$target" "sudo mkdir -p /root/.ssh && sudo chmod 700 /root/.ssh"

    # Copy root SSH private key
    cat "${KEY_DIR}/root-cluster" | ssh -J "$JUMP_HOST" "$target" "sudo tee /root/.ssh/id_ed25519 > /dev/null && sudo chmod 600 /root/.ssh/id_ed25519"

    # Copy root SSH public key
    cat "${KEY_DIR}/root-cluster.pub" | ssh -J "$JUMP_HOST" "$target" "sudo tee /root/.ssh/id_ed25519.pub > /dev/null && sudo chmod 644 /root/.ssh/id_ed25519.pub"

    # Create root SSH config for StrictHostKeyChecking
    ssh -J "$JUMP_HOST" "$target" "sudo tee /root/.ssh/config > /dev/null << 'EOF'
Host *.local
    StrictHostKeyChecking accept-new
    UserKnownHostsFile /root/.ssh/known_hosts
EOF
sudo chmod 600 /root/.ssh/config"

    # Copy cache signing key
    cat "${KEY_DIR}/cache/priv-key.pem" | ssh -J "$JUMP_HOST" "$target" "sudo tee /etc/nix/cache-priv-key.pem > /dev/null && sudo chmod 600 /etc/nix/cache-priv-key.pem"

    echo "=== ${node_name} done ==="
}

if [[ $# -eq 1 ]]; then
    setup_node "$1"
else
    for i in 1 2 3 4 5 6 7; do
        setup_node "$i"
    done
fi

echo ""
echo "Distributed build setup complete!"
echo "After deploying the new configuration, test with:"
echo "  ssh admin@node1.local 'nix build nixpkgs#hello --rebuild'"
