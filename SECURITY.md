# Security Model

This document describes the security model for the Odroid C4 cluster. This is a **home lab project** with security appropriate for a trusted local network.

## Overview

- **SSH key authentication only** - Password authentication is disabled
- **Firewall enabled by default** - Only SSH (port 22) is open unless explicitly configured
- **Passwordless sudo** - The `admin` user has passwordless sudo for convenience
- **No remote root login via password** - Root SSH is key-based only

## SSH Key Management

### Admin User Keys

Authorized SSH keys for the `admin` user are defined in `configuration.nix`:

```nix
users.users.admin.openssh.authorizedKeys.keys = [
  "ssh-ed25519 AAAA... user@host"
];
```

To add or remove access, edit this list and redeploy.

### Root SSH (Inter-Node)

Root SSH is enabled for **distributed Nix builds** between cluster nodes:

- Each node has `/root/.ssh/id_ed25519` (the cluster root key)
- This key is authorized on all nodes for root access
- Allows `nix-daemon` to offload builds to other nodes

**Important**: The cluster root key is internal only. It is NOT authorized on external machines (MacBook, desktop). Nodes cannot SSH out of the cluster.

### Key Storage

Keys are stored on management machines at:
- `~/.ssh/odroid-cluster/root-cluster` - Cluster root key
- `~/.ssh/odroid-cluster/cache/` - Binary cache signing keys

## Default Credentials

| Service | Username | Password | Notes |
|---------|----------|----------|-------|
| Grafana | admin | admin | **Change on first login** |

There are no other default passwords. All access is via SSH keys.

## Network Security

### Firewall

The NixOS firewall is enabled by default. Open ports are configured in `configuration.nix`:

```nix
networking.firewall.allowedTCPPorts = [ 22 ];  # SSH only by default
```

Additional ports are opened for specific services (Prometheus 9090, Grafana 3000, node_exporter 9100, K3s ports).

### Local Network Only

- Nodes communicate on the local network via mDNS (`node1.local`, etc.)
- Services are internal unless explicitly exposed via NodePort or LoadBalancer
- K3s uses Flannel VXLAN for pod-to-pod networking (encrypted within cluster)

### K3s Security

- K3s API server binds to node IPs (not exposed externally)
- Node token stored at `/etc/k3s/token` (root-only readable)
- Kubeconfig at `/etc/rancher/k3s/k3s.yaml` (root-only readable)

## What This Setup Does NOT Provide

This is a home lab, not production infrastructure:

- No TLS for internal services (Grafana, Prometheus)
- No secrets management (K8s secrets are base64 only)
- No network policies (all pods can communicate)
- No audit logging
- No automatic security updates (manual flake updates required)

## Hardening Recommendations (Optional)

If you want to improve security:

1. **Enable automatic updates**: Add a systemd timer to run `nix flake update` and rebuild
2. **Add TLS**: Use cert-manager with Let's Encrypt for HTTPS
3. **Network policies**: Implement Kubernetes NetworkPolicies to restrict pod traffic
4. **Change Grafana password**: Do this immediately after first login

## Reporting Security Issues

- **Non-sensitive issues**: Open a GitHub issue on `SamuelSchlesinger/odroid-c4-cluster`
- **Sensitive issues**: Contact via GitHub profile (see repository owner)

This is a personal project. Response times are best-effort.
