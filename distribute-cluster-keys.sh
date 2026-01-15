#!/usr/bin/env bash
# Distribute SSH keys to cluster nodes
# Usage: ./distribute-cluster-keys.sh [node_number]
#
# Run from MacBook through desktop jump host.
# If no node specified, distributes to all nodes.

set -euo pipefail

KEY_DIR="$HOME/.ssh/odroid-cluster"
JUMP_HOST="samuel@desktop"

distribute_to_node() {
    local node_num=$1
    local node_name="node${node_num}"
    local target="admin@${node_name}.local"

    echo "=== Distributing key to ${node_name} ==="

    # Create .ssh directory if needed
    ssh -J "$JUMP_HOST" "$target" "mkdir -p ~/.ssh && chmod 700 ~/.ssh"

    # Copy private key
    scp -o "ProxyJump=$JUMP_HOST" "${KEY_DIR}/${node_name}" "${target}:~/.ssh/id_ed25519"

    # Copy public key
    scp -o "ProxyJump=$JUMP_HOST" "${KEY_DIR}/${node_name}.pub" "${target}:~/.ssh/id_ed25519.pub"

    # Set correct permissions
    ssh -J "$JUMP_HOST" "$target" "chmod 600 ~/.ssh/id_ed25519 && chmod 644 ~/.ssh/id_ed25519.pub"

    # Create SSH config for easy inter-node access
    ssh -J "$JUMP_HOST" "$target" "cat > ~/.ssh/config << 'EOF'
# Cluster nodes
Host node1 node1.local
    HostName node1.local
    User admin

Host node2 node2.local
    HostName node2.local
    User admin

Host node3 node3.local
    HostName node3.local
    User admin

Host node4 node4.local
    HostName node4.local
    User admin

Host node5 node5.local
    HostName node5.local
    User admin

Host node6 node6.local
    HostName node6.local
    User admin

Host node7 node7.local
    HostName node7.local
    User admin

Host *
    StrictHostKeyChecking accept-new
EOF
chmod 600 ~/.ssh/config"

    echo "=== ${node_name} done ==="
}

if [[ $# -eq 1 ]]; then
    distribute_to_node "$1"
else
    for i in 1 2 3 4 5 6 7; do
        distribute_to_node "$i"
    done
fi

echo "Key distribution complete."
