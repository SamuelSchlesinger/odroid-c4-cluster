# NixOS on Odroid C4 Cluster

> **Note**: This is my personal cluster configuration. If you want to use this as a starting point for your own cluster, you'll need to:
> - Replace SSH public keys in `configuration.nix` with your own
> - Update the GitHub repository URL in `flake.nix` and deployment commands
> - Generate your own root SSH keys and binary cache signing keys (see `setup-distributed-builds.sh`)
> - Adjust node count and hostnames to match your hardware

A fully reproducible NixOS configuration for a 7-node ARM cluster running K3s Kubernetes. This project provides a complete infrastructure-as-code setup including GitOps auto-deployment (push to deploy), distributed Nix builds across all nodes, Prometheus + Grafana monitoring, and sensible security defaults. Everything is declarative and version-controlled - just edit, commit, and push.

## Features

- **Declarative NixOS Configuration** - All system settings defined in Nix, ensuring reproducibility and easy rollbacks
- **K3s Kubernetes** - Production-ready cluster with 3 control plane nodes and 4 workers for high availability
- **GitOps Auto-Deployment** - Push to GitHub and all nodes automatically deploy within seconds
- **Distributed Nix Builds** - Share build capacity across all 7 nodes (28 cores total)
- **Prometheus + Grafana Monitoring** - Full observability with node metrics, dashboards, and alerts
- **mDNS Discovery** - Access nodes via `node1.local` through `node7.local` without configuring DNS
- **Security by Default** - SSH key authentication only, firewall enabled, no passwords

## Cluster Overview

| Resource | Value |
|----------|-------|
| **Nodes** | 7 × Odroid C4 (ARM64) |
| **Total CPU** | 28 cores (4 per node) |
| **Total RAM** | 28 GB (4 GB per node) |
| **Orchestration** | K3s v1.32 (3 servers + 4 agents) |
| **Container Runtime** | containerd (bundled with K3s) |
| **Monitoring** | Prometheus + Grafana on node1 |

## Kubernetes Quick Start

```bash
# Check cluster status (from any node)
ssh admin@node1.local "kubectl get nodes"

# Deploy a workload
ssh admin@node1.local "kubectl create deployment nginx --image=nginx:alpine --replicas=3"

# Expose as NodePort service
ssh admin@node1.local "kubectl expose deployment nginx --port=80 --type=NodePort"

# Access via any node IP on the assigned port
curl http://node1.local:<nodeport>
```

## Prerequisites

Before getting started, you will need:

- **Linux machine with Nix installed** - Required for building SD card images (NixOS, or any Linux with Nix package manager)
- **7x Odroid C4 boards** - Each with a microSD card (8GB minimum, 32GB+ recommended)
- **Network switch and ethernet cables** - Gigabit recommended for best performance
- **Familiarity with NixOS basics** - Understanding of flakes, `nixos-rebuild`, and Nix expressions

Optional but helpful:
- **macOS machine** - For flashing SD cards (or use Linux)
- **USB SD card reader** - For flashing the images

## Quick Start (Initial Setup)

### 1. Build images on desktop (Linux)

```bash
# SSH to desktop and build
ssh samuel@desktop
cd ~/sysadmin/odroid-c4
nix build .#node1-sdImage -o result-node1
# Repeat for nodes 2-7, or build all:
for i in 1 2 3 4 5 6 7; do nix build .#node${i}-sdImage -o result-node${i}; done
```

### 2. Transfer images to MacBook

```bash
mkdir -p ~/odroid-images
scp "samuel@desktop:~/sysadmin/odroid-c4/result-node*/sd-image/*.img.zst" ~/odroid-images/
```

### 3. Flash SD cards

```bash
cd ~/sysadmin/odroid-c4
./flash-with-towboot.sh ~/odroid-images/*node1*.img.zst /dev/diskX
# Repeat for nodes 2-7
```

### 4. Boot and connect

```bash
ssh admin@node1.local
ssh admin@node2.local
# ... etc
```

## Configuration

All system settings are in NixOS modules:

| File | Purpose |
|------|---------|
| `configuration.nix` | Base system (SSH, users, packages, Nix settings) |
| `k3s.nix` | K3s Kubernetes cluster configuration |
| `monitoring.nix` | Prometheus + Grafana (node1 only) |

**Key features:**
- SSH key-only authentication
- `admin` user with passwordless sudo
- mDNS via Avahi (`nodeX.local`)
- K3s with 3 servers (node1-3) and 4 agents (node4-7)
- Distributed Nix builds across all nodes

## Remote Updates

After initial deployment, update nodes without reflashing. Nodes can pull directly from GitHub using the root SSH key (configured as a deploy key):

```bash
# Single node
ssh admin@node1.local "sudo nixos-rebuild switch --flake 'git+ssh://git@github.com/SamuelSchlesinger/odroid-c4-cluster#node1'"

# All nodes in parallel
for i in 1 2 3 4 5 6 7; do
  ssh admin@node$i.local "sudo nixos-rebuild switch --flake 'git+ssh://git@github.com/SamuelSchlesinger/odroid-c4-cluster#node$i'" &
done
wait
```

## Distributed Builds

The cluster shares build capacity across all 7 nodes (28 cores). When building on any node, Nix can offload work to other nodes via SSH.

See `configuration.nix:99-112` for the setup:
- `nix.distributedBuilds = true`
- `nix.buildMachines` lists all nodes
- Root SSH keys enable inter-node nix-daemon access

## Files

```
odroid-c4/
├── flake.nix                    # Nix flake defining all 7 nodes
├── flake.lock                   # Pinned nixpkgs version
├── configuration.nix            # Base system config (SSH, users, packages)
├── k3s.nix                      # K3s Kubernetes cluster configuration
├── monitoring.nix               # Prometheus + Grafana (node1 only)
├── hardware-configuration.nix   # Odroid C4 hardware + Tow-Boot boot
├── flash-with-towboot.sh        # Flash script for macOS
├── setup-distributed-builds.sh  # Set up root SSH + signing keys
├── README.md                    # This file
├── CLAUDE.md                    # Claude Code operational guide
├── CLUSTER-GUIDE.md             # Comprehensive documentation
└── odroid-C4-2023.07-007/       # Tow-Boot bootloader files
```

## Documentation

- **README.md** - Quick start (this file)
- **CLAUDE.md** - Operational guide for Claude Code workers
- **CLUSTER-GUIDE.md** - Complete reference with diagrams, troubleshooting, examples

## Contributing & Community

- **[CONTRIBUTING.md](CONTRIBUTING.md)** - Contribution guidelines and development workflow
- **[SECURITY.md](SECURITY.md)** - Security model and how to report vulnerabilities
- **[LICENSE](LICENSE)** - This project is MIT licensed

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Can't find node | Wait 5 min for first boot, check router DHCP leases |
| SSH refused | Verify node booted, check `ssh-add -l` for your key |
| Build fails | Check disk space (`df -h`), enable flakes |
| mDNS not working | Try direct IP from router DHCP table |

See `CLUSTER-GUIDE.md` for detailed troubleshooting.
