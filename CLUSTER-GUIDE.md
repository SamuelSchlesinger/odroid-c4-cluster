# Odroid C4 Cluster - Complete Guide

This document provides comprehensive documentation for the 7-node Odroid C4 NixOS cluster.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Hardware](#hardware)
- [Network Topology](#network-topology)
- [Remote Access](#remote-access)
- [Software Stack](#software-stack)
- [Repository Structure](#repository-structure)
- [Management Workflows](#management-workflows)
- [Kubernetes (K3s)](#kubernetes-k3s)
- [Configuration Reference](#configuration-reference)
- [Troubleshooting](#troubleshooting)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Network Architecture                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   ┌──────────────┐         Tailscale VPN          ┌──────────────────┐  │
│   │   MacBook    │ ◄──────────────────────────────► │     Desktop      │  │
│   │   (laptop)   │        100.x.x.x mesh          │  (build machine) │  │
│   └──────────────┘                                 └────────┬─────────┘  │
│                                                             │            │
│                                                    Local LAN (Ethernet)  │
│                                                             │            │
│                                                    ┌────────┴─────────┐  │
│                                                    │      Router      │  │
│                                                    │   192.168.4.1    │  │
│                                                    │   (DHCP server)  │  │
│                                                    └────────┬─────────┘  │
│                                                             │            │
│                                              ┌──────────────┴──────────┐ │
│                                              │    Ethernet Switch      │ │
│                                              └──┬───┬───┬───┬───┬───┬──┘ │
│                                                 │   │   │   │   │   │    │
│   ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐              │
│   │node1│ │node2│ │node3│ │node4│ │node5│ │node6│ │node7│              │
│   │ .250│ │ .0  │ │ .255│ │ .254│ │ .251│ │ .253│ │ .252│              │
│   └─────┘ └─────┘ └─────┘ └─────┘ └─────┘ └─────┘ └─────┘              │
│                                                                          │
│   All nodes: 192.168.4.x/22 or 192.168.5.x/22 (DHCP assigned)           │
│   mDNS: node1.local through node7.local                                  │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Key Components

| Component | Role | Location |
|-----------|------|----------|
| **MacBook** | Configuration editing, SD card flashing | Mobile |
| **Desktop** | Nix builds, deployment, direct cluster access | Local network |
| **Cluster** | 7 identical compute nodes | Local network |

---

## Hardware

### Node Specifications (per node)

| Component | Specification |
|-----------|---------------|
| **Board** | Hardkernel Odroid C4 |
| **SoC** | Amlogic S905X3 |
| **CPU** | 4x ARM Cortex-A55 @ 2.0GHz |
| **RAM** | 4GB DDR4 |
| **Storage** | MicroSD card (32GB recommended) |
| **Network** | Gigabit Ethernet (RTL8211F) |
| **Power** | 12V/2A DC barrel jack |
| **USB** | 4x USB 3.0 |
| **GPIO** | 40-pin header (RPi compatible) |

### Cluster Totals

| Resource | Total |
|----------|-------|
| CPU Cores | 28 (4 × 7) |
| RAM | 28GB (4GB × 7) |
| Network | 7 Gbps aggregate |

### Desktop (Build Machine)

| Component | Specification |
|-----------|---------------|
| **OS** | Ubuntu 24.04.3 LTS |
| **CPU** | AMD Ryzen 9 5900X (12c/24t) |
| **RAM** | 64GB DDR4 |
| **Storage** | 2x 1.8TB NVMe |
| **Network** | Gigabit Ethernet + Tailscale |
| **Hostname** | `desktop` / `samuel@desktop` |

---

## Network Topology

### IP Addressing

Nodes receive dynamic IPs via DHCP in the 192.168.4.0/22 range:

| Node | Hostname | Current IP | mDNS |
|------|----------|------------|------|
| 1 | node1 | 192.168.4.250 | node1.local |
| 2 | node2 | 192.168.5.0 | node2.local |
| 3 | node3 | 192.168.4.255 | node3.local |
| 4 | node4 | 192.168.4.254 | node4.local |
| 5 | node5 | 192.168.4.251 | node5.local |
| 6 | node6 | 192.168.4.253 | node6.local |
| 7 | node7 | 192.168.4.252 | node7.local |

**Note**: IPs may change after router/node restarts. Always prefer mDNS names (`nodeX.local`).

### Service Discovery

Nodes advertise themselves via **Avahi/mDNS**:
- Works automatically on most home networks
- May not work on corporate networks that block multicast
- Fallback: Check router's DHCP lease table for current IPs

---

## Remote Access

### Access Patterns

There are three ways to access the cluster depending on your location:

#### 1. Local Network Access (Desktop)

When on the same LAN as the cluster:

```bash
# Direct SSH to any node
ssh admin@node1.local
ssh admin@node2.local
# ... etc
```

#### 2. Remote Access via Tailscale (MacBook → Desktop → Cluster)

When away from the local network, use the desktop as a jump host:

```bash
# Option A: Two-hop manual
ssh samuel@desktop
ssh admin@node1.local

# Option B: Single command with jump host
ssh -J samuel@desktop admin@node1.local

# Option C: ProxyJump in SSH config (recommended - see below)
ssh node1
```

#### 3. SSH Config for Seamless Access

Add this to `~/.ssh/config` on your MacBook for easy remote access:

```ssh-config
# Desktop as jump host (accessible via Tailscale)
Host desktop
    HostName desktop
    User samuel

# Cluster nodes via jump host
Host node1
    HostName node1.local
    User admin
    ProxyJump desktop

Host node2
    HostName node2.local
    User admin
    ProxyJump desktop

Host node3
    HostName node3.local
    User admin
    ProxyJump desktop

Host node4
    HostName node4.local
    User admin
    ProxyJump desktop

Host node5
    HostName node5.local
    User admin
    ProxyJump desktop

Host node6
    HostName node6.local
    User admin
    ProxyJump desktop

Host node7
    HostName node7.local
    User admin
    ProxyJump desktop

# Wildcard for all nodes (alternative to individual entries)
Host node?
    HostName %h.local
    User admin
    ProxyJump desktop
```

With this config, simply run:
```bash
ssh node1    # Automatically routes through desktop
ssh node5    # Works from anywhere with Tailscale connected
```

### Network Path Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    Remote Access Path                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────┐    Tailscale    ┌──────────┐    LAN    ┌───────┐ │
│  │ MacBook  │ ───────────────►│ Desktop  │ ─────────►│ nodeX │ │
│  │ (remote) │   100.x.x.x     │  (jump)  │  .local   │       │ │
│  └──────────┘                 └──────────┘           └───────┘ │
│                                                                  │
│  Authentication chain:                                           │
│  1. MacBook SSH key → Desktop (samuel)                          │
│  2. Desktop SSH key → Node (admin) [key forwarding]             │
│                                                                  │
│  Both keys are already authorized in configuration.nix          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Authorized SSH Keys

The cluster accepts these SSH keys (defined in `configuration.nix`):

```nix
# Admin user - external access
openssh.authorizedKeys.keys = [
  # MacBook
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOv/btyrQGVnaGQCLEdkOGKtGgSN2TmdFMgDyst4tpaz samuelschlesinger@Samuels-MacBook-Pro.local"
  # Desktop
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMXkHnuxSPuZfVl1vMa6h4H230X3s1f3ch4oZGKTz91f samuel@desktop"
];

# Root user - distributed builds only
users.users.root.openssh.authorizedKeys.keys = [
  "ssh-ed25519 AAAA... root@odroid-cluster"  # Shared cluster key
];
```

**Key Storage Locations**:
- MacBook/Desktop: `~/.ssh/odroid-cluster/root-cluster` (root key for distributed builds and GitHub)
- Nodes: `/root/.ssh/id_ed25519` (shared root key for inter-node builds and GitHub access)

**GitHub Deploy Key**: The `root@odroid-cluster` public key is configured as a read-only deploy key on the GitHub repo, allowing nodes to pull configuration directly.

**Security**: The cluster root key is NOT authorized on the desktop or MacBook - nodes cannot SSH back to those machines.

---

## Software Stack

### Operating System

```
┌─────────────────────────────────────┐
│          Applications               │
│   (vim, git, htop, tmux, curl)      │
├─────────────────────────────────────┤
│         NixOS 25.05                 │
│   (Declarative Linux distribution)  │
├─────────────────────────────────────┤
│       Linux Kernel 6.6 LTS          │
├─────────────────────────────────────┤
│        Tow-Boot Bootloader          │
│   (U-Boot based, SD card boot)      │
├─────────────────────────────────────┤
│       Odroid C4 Hardware            │
│   (Amlogic S905X3 SoC)              │
└─────────────────────────────────────┘
```

### Key Services

| Service | Purpose | Port | Location |
|---------|---------|------|----------|
| OpenSSH | Remote access | 22 | All nodes |
| Avahi | mDNS discovery | 5353/udp | All nodes |
| node_exporter | System metrics | 9100 | All nodes |
| K3s API | Kubernetes API server | 6443 | All nodes |
| etcd | K3s cluster state | 2379-2380 | All nodes |
| Prometheus | Metrics aggregation | 9090 | node1 |
| Grafana | Dashboards | 3000 | node1 |

### Installed Packages

```nix
environment.systemPackages = with pkgs; [
  vim      # Text editor
  git      # Version control
  htop     # Process monitor
  tmux     # Terminal multiplexer
  curl     # HTTP client
  wget     # File downloader
  kubectl  # Kubernetes CLI
];
```

### Container Orchestration

All nodes run **K3s**, a lightweight Kubernetes distribution:

| Component | Purpose |
|-----------|---------|
| **K3s** | Lightweight Kubernetes (single binary) |
| **containerd** | Container runtime (bundled with K3s) |
| **flannel** | Pod networking (VXLAN backend) |
| **CoreDNS** | Service discovery |

**Cluster topology:**
- All 7 nodes run as K3s servers (control plane + workloads)
- node1 is the initial server (bootstrap node)
- Tolerates loss of up to 3 nodes (4-node quorum)
- ~50MB RAM overhead per node

### Security Configuration

| Setting | Value | Notes |
|---------|-------|-------|
| SSH root login | Keys only | `PermitRootLogin = "prohibit-password"` (for distributed builds) |
| Password auth | Disabled | SSH keys only |
| Firewall | Enabled | Ports 22, 9100 on all; 9090, 3000 on node1 |
| Sudo | Passwordless | For `admin` user via `wheel` group |

### Monitoring Stack

The cluster runs a Prometheus + Grafana monitoring stack:

```
┌─────────────────────────────────────────────────────────────────┐
│                     Monitoring Architecture                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────── node1 (monitoring hub) ─────────────────┐ │
│  │                                                             │ │
│  │  ┌─────────────┐     ┌────────────┐     ┌──────────────┐  │ │
│  │  │ Prometheus  │────▶│  Grafana   │     │ node_exporter│  │ │
│  │  │   :9090     │     │   :3000    │     │    :9100     │  │ │
│  │  └──────┬──────┘     └────────────┘     └──────────────┘  │ │
│  │         │ scrapes every 15s                                │ │
│  └─────────┼──────────────────────────────────────────────────┘ │
│            │                                                     │
│            ▼ scrapes metrics from all nodes                      │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │ node2           │  │ node3           │  │ node4-7         │  │
│  │ node_exporter   │  │ node_exporter   │  │ node_exporter   │  │
│  │ :9100           │  │ :9100           │  │ :9100           │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Access via go-links** (see below) or directly:
- Grafana: `http://node1.local:3000` (admin/admin)
- Prometheus: `http://node1.local:9090`
- Node metrics: `http://nodeX.local:9100/metrics`

**Configuration files**:
- `monitoring.nix` - Prometheus and Grafana (included only for node1 in flake.nix)
- `configuration.nix` - node_exporter (all nodes)

**Recommended Grafana dashboard**: Import dashboard ID `1860` (Node Exporter Full) for comprehensive node metrics.

### Go-Links

Short URLs for cluster services, accessible via Tailscale from anywhere:

| Link | Destination |
|------|-------------|
| `go/` | Index page showing all available links |
| `go/grafana` | Grafana dashboards (node1.local:3000) |
| `go/prometheus` | Prometheus UI (node1.local:9090) |
| `go/prom` | Prometheus (short alias) |
| `go/node1` - `go/node7` | Node metrics (nodeX.local:9100) |

**How it works**:
1. nginx on desktop (`samuel@desktop`) handles redirects
2. Config: `/etc/nginx/sites-enabled/go-links`
3. Clients resolve `go` via `/etc/hosts` → desktop's Tailscale IP (100.123.199.53)

**To add go-links to a new machine**:
```bash
sudo sh -c 'echo "100.123.199.53 go" >> /etc/hosts'
```

---

## Repository Structure

```
odroid-c4-cluster/
├── flake.nix                 # Nix flake: defines all 7 nodes
├── flake.lock                # Pinned dependencies (nixpkgs version)
├── configuration.nix         # Shared NixOS config for all nodes
├── k3s.nix                   # K3s Kubernetes configuration (all nodes)
├── monitoring.nix            # Prometheus + Grafana (node1 only)
├── hardware-configuration.nix # Odroid C4 hardware settings
├── flash-with-towboot.sh     # SD card flashing script (macOS)
├── setup-distributed-builds.sh # Root SSH + cache key distribution
├── .gitignore                # Ignores build outputs and logs
├── README.md                 # Quick start guide
├── CLUSTER-GUIDE.md          # This file
├── CLAUDE.md                 # Claude Code operational guide
├── k8s/                      # Kubernetes resources and tutorials
│   └── examples/             # Example applications and walkthroughs
│       ├── README.md         # Step-by-step K8s tutorial
│       └── whoami-app.yaml   # Sample deployment with service
└── odroid-C4-2023.07-007/    # Tow-Boot bootloader
    └── shared.disk-image.img # Bootloader image for flashing
```

### Key Files Explained

| File | Purpose |
|------|---------|
| `flake.nix` | Defines the 7 node configurations and SD image build targets |
| `flake.lock` | **Critical**: Pins exact nixpkgs version. Must match deployed nodes. |
| `configuration.nix` | All system settings: users, SSH, packages, services |
| `hardware-configuration.nix` | Boot settings, kernel modules, filesystem mounts |
| `flash-with-towboot.sh` | Writes Tow-Boot + NixOS image to SD card |

---

## Management Workflows

### Repository Sync (MacBook ↔ Desktop)

This repo is synced via GitHub between machines:

```bash
# On either machine
cd ~/sysadmin/odroid-c4
git pull origin main          # Get latest changes
# Make edits...
git add -A
git commit -m "Description of changes"
git push origin main          # Push to GitHub
```

### Update NixOS Packages

**Important**: Only run `nix flake update` if you plan to rebuild and redeploy all nodes. The `flake.lock` must match what's deployed.

```bash
# On desktop (has Nix)
cd ~/sysadmin/odroid-c4
nix flake update              # Updates flake.lock to latest nixpkgs
git add flake.lock
git commit -m "Update flake inputs to $(date +%Y-%m-%d)"
git push origin main

# Then rebuild and deploy to all nodes (see below)
```

### Build SD Card Images

```bash
# On desktop
cd ~/sysadmin/odroid-c4

# Build single node
nix build .#node1-sdImage -o result-node1

# Build all nodes
for i in 1 2 3 4 5 6 7; do
  nix build .#node${i}-sdImage -o result-node${i}
done

# Images are at: result-nodeX/sd-image/*.img.zst
```

### Flash SD Cards (macOS)

```bash
# On MacBook
cd ~/sysadmin/odroid-c4

# List disks to find SD card
diskutil list

# Flash (replace diskX with actual disk number)
./flash-with-towboot.sh /path/to/image.img.zst /dev/diskX
```

### Deploy Configuration to Running Nodes

Nodes can pull configuration directly from GitHub using the root SSH key (configured as a deploy key on the repo).

**Important**: Use `--refresh` to ensure nodes fetch the latest commit (Nix caches flake references).

```bash
# Single node (from desktop)
ssh admin@node1.local "sudo nixos-rebuild switch --flake 'git+ssh://git@github.com/SamuelSchlesinger/odroid-c4-cluster#node1' --refresh"

# Single node (from MacBook via jump host)
ssh -J samuel@desktop admin@node1.local "sudo nixos-rebuild switch --flake 'git+ssh://git@github.com/SamuelSchlesinger/odroid-c4-cluster#node1' --refresh"

# All nodes in parallel (from desktop)
for i in 1 2 3 4 5 6 7; do
  echo "=== Deploying to node$i ==="
  ssh admin@node$i.local "sudo nixos-rebuild switch --flake 'git+ssh://git@github.com/SamuelSchlesinger/odroid-c4-cluster#node$i' --refresh" &
done
wait
```

### Check Cluster Health

```bash
# Quick health check (from desktop or via jump host)
for i in 1 2 3 4 5 6 7; do
  echo "=== node$i ==="
  ssh admin@node$i.local "hostname && uptime && free -h && df -h /"
done
```

### Rollback a Node

If a deployment breaks something:

```bash
ssh admin@node1.local

# List available generations
sudo nix-env --list-generations -p /nix/var/nix/profiles/system

# Rollback to previous
sudo nixos-rebuild switch --rollback
```

### Distributed Builds

The cluster uses Nix distributed builds to share build capacity across all 7 nodes (28 cores total). When you build something on any node, Nix can automatically offload work to other nodes.

#### How It Works

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    Distributed Build Flow                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  1. User runs `nix build` on node1                                      │
│                                                                          │
│  2. Nix daemon checks what needs building                               │
│                                                                          │
│  3. For each derivation, daemon either:                                 │
│     - Downloads from cache.nixos.org (if available)                     │
│     - Builds locally                                                    │
│     - Offloads to a remote node via SSH                                 │
│                                                                          │
│  4. Remote builds happen via:                                           │
│     ssh root@node2.local nix-store --serve --write                      │
│                                                                          │
│  5. Built artifacts are copied back to requesting node                  │
│                                                                          │
│  ┌───────┐         ┌───────┐         ┌───────┐                         │
│  │ node1 │ ──────► │ node2 │         │ node3 │                         │
│  │(user) │ build   │(build)│         │(build)│                         │
│  └───────┘ request └───────┘         └───────┘                         │
│      ▲                 │                 │                              │
│      └─────────────────┴─────────────────┘                              │
│                  results copied back                                     │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

#### Configuration (in configuration.nix)

The distributed builds setup has three parts:

**1. Enable distributed builds:**
```nix
nix.distributedBuilds = true;
```

**2. Define build machines (all 7 nodes):**
```nix
nix.buildMachines = [
  {
    hostName = "node1.local";           # mDNS hostname
    sshUser = "root";                   # Must be root for nix-daemon
    sshKey = "/root/.ssh/id_ed25519";   # Shared cluster root key
    system = "aarch64-linux";           # Architecture
    maxJobs = 4;                        # CPU cores available
    speedFactor = 1;                    # Priority (all equal)
    supportedFeatures = [ "nixos-test" "big-parallel" ];
  }
  # ... repeated for all 7 nodes
];
```

**3. Root SSH access (for inter-node builds):**
```nix
services.openssh.settings.PermitRootLogin = "prohibit-password";
users.users.root.openssh.authorizedKeys.keys = [
  "ssh-ed25519 AAAA... root@odroid-cluster"  # Shared root key
];
```

#### Key Files on Each Node

| Path | Purpose |
|------|---------|
| `/root/.ssh/id_ed25519` | Root private key for SSH to other nodes |
| `/etc/nix/cache-priv-key.pem` | Signs builds so other nodes trust them |
| Generated `/etc/nix/machines` | List of remote builders (from buildMachines) |

#### Using Distributed Builds

```bash
# Normal build - uses local + remote nodes
nix build nixpkgs#hello

# Force remote-only (useful for testing)
nix build nixpkgs#hello --max-jobs 0

# See which nodes are being used
nix build nixpkgs#hello -v 2>&1 | grep "building.*on"
```

#### Important Notes

- **Nodes don't share stores**: Each node has its own `/nix/store`. If node1 builds something, node2 must rebuild it (unless it's in cache.nixos.org).
- **Pre-built packages**: Most nixpkgs packages are in cache.nixos.org, so distributed builds mainly help for custom derivations or packages not in the cache.
- **Latency**: Distributed builds add SSH overhead. For small builds, local is faster.

#### Re-setup Keys (if needed)

```bash
# From MacBook, distribute root SSH and cache signing keys
./setup-distributed-builds.sh        # All nodes
./setup-distributed-builds.sh 3      # Single node
```

---

## Kubernetes (K3s)

The cluster runs K3s, a lightweight Kubernetes distribution. All 7 nodes operate as servers, providing a highly available control plane that can tolerate up to 3 node failures.

### Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      K3s Cluster Architecture                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │                    K3s Server Cluster (HA)                       │   │
│   │                                                                  │   │
│   │   node1        node2        node3        node4                  │   │
│   │   (init)                                                         │   │
│   │    ┌──┐        ┌──┐        ┌──┐        ┌──┐                     │   │
│   │    │S │◄──────►│S │◄──────►│S │◄──────►│S │                     │   │
│   │    └──┘        └──┘        └──┘        └──┘                     │   │
│   │      ▲           ▲           ▲           ▲                       │   │
│   │      │           │           │           │                       │   │
│   │      ▼           ▼           ▼           ▼                       │   │
│   │   node5        node6        node7                               │   │
│   │    ┌──┐        ┌──┐        ┌──┐                                 │   │
│   │    │S │◄──────►│S │◄──────►│S │                                 │   │
│   │    └──┘        └──┘        └──┘                                 │   │
│   │                                                                  │   │
│   │   S = Server (API + etcd + kubelet)                             │   │
│   │   All nodes can run workloads                                    │   │
│   │   Quorum: 4 nodes (tolerates 3 failures)                        │   │
│   │                                                                  │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│   Networking: Flannel VXLAN (port 8472/udp)                             │
│   DNS: CoreDNS (cluster.local)                                          │
│   API: https://any-node:6443                                            │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 6443 | TCP | Kubernetes API server |
| 2379 | TCP | etcd client |
| 2380 | TCP | etcd peer |
| 8472 | UDP | Flannel VXLAN |
| 10250 | TCP | Kubelet metrics |

### Quick Start

```bash
# Check cluster status (from any node)
ssh admin@node1.local "kubectl get nodes"

# Check all pods
ssh admin@node1.local "kubectl get pods -A"

# Deploy a simple workload
ssh admin@node1.local "kubectl run nginx --image=nginx:alpine"
```

### Learning Kubernetes

For a hands-on tutorial, see **`k8s/examples/README.md`**. It walks through:
- Deploying a multi-replica application
- Understanding namespaces, deployments, and services
- Observing load balancing (and why browsers behave differently than curl)
- Scaling, logs, exec, and cleanup

Deploy the example application:
```bash
kubectl apply -f https://raw.githubusercontent.com/SamuelSchlesinger/odroid-c4-cluster/main/k8s/examples/whoami-app.yaml
```

### Common Commands

```bash
# Cluster status
kubectl get nodes -o wide
kubectl cluster-info
kubectl get componentstatuses

# View workloads
kubectl get pods -A                    # All namespaces
kubectl get deployments
kubectl get services

# Deploy from YAML
kubectl apply -f deployment.yaml

# Quick test deployment
kubectl create deployment nginx --image=nginx:alpine --replicas=3

# Expose as service
kubectl expose deployment nginx --port=80 --type=NodePort

# View logs
kubectl logs <pod-name>
kubectl logs -f <pod-name>             # Follow

# Execute in pod
kubectl exec -it <pod-name> -- sh

# Delete resources
kubectl delete deployment nginx
kubectl delete pod <pod-name>
```

### Example Deployment

```yaml
# hello-world.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-world
spec:
  replicas: 3
  selector:
    matchLabels:
      app: hello-world
  template:
    metadata:
      labels:
        app: hello-world
    spec:
      containers:
      - name: hello
        image: nginx:alpine
        ports:
        - containerPort: 80
        resources:
          limits:
            memory: "128Mi"
            cpu: "250m"
---
apiVersion: v1
kind: Service
metadata:
  name: hello-world
spec:
  type: NodePort
  selector:
    app: hello-world
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30080
```

```bash
# Deploy
kubectl apply -f hello-world.yaml

# Access (from any node IP)
curl http://node1.local:30080
```

### Kubeconfig Access

The kubeconfig is at `/etc/rancher/k3s/k3s.yaml` on each node.

```bash
# Copy kubeconfig to local machine (adjust server address)
scp -J samuel@desktop admin@node1.local:/etc/rancher/k3s/k3s.yaml ~/.kube/config

# Edit to use node1's address
sed -i '' 's/127.0.0.1/node1.local/' ~/.kube/config

# Now use kubectl locally
kubectl get nodes
```

### Resource Management

Each node has ~3.5GB RAM available for pods (after 512MB reserved for system).

```yaml
# Set resource requests and limits
resources:
  requests:
    memory: "64Mi"
    cpu: "100m"
  limits:
    memory: "128Mi"
    cpu: "250m"
```

### Storage

K3s includes a local-path provisioner for simple persistent volumes:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-data
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 1Gi
```

### Troubleshooting K3s

```bash
# Check K3s service status
systemctl status k3s

# View K3s logs
journalctl -u k3s -f

# Check node status
kubectl describe node node1

# Check pod events
kubectl describe pod <pod-name>

# Check cluster events
kubectl get events --sort-by='.lastTimestamp'

# Restart K3s on a node
sudo systemctl restart k3s
```

### Token File

K3s uses a token file at `/etc/k3s/token` for cluster authentication. This token must be the same on all nodes.

---

## Configuration Reference

### Adding Packages

Edit `configuration.nix`:

```nix
environment.systemPackages = with pkgs; [
  vim git htop tmux curl wget
  # Add new packages here:
  python3
  docker
  ripgrep
];
```

### Adding a Systemd Service

```nix
systemd.services.my-service = {
  description = "My Custom Service";
  wantedBy = [ "multi-user.target" ];
  after = [ "network.target" ];
  serviceConfig = {
    ExecStart = "${pkgs.my-app}/bin/my-app";
    Restart = "always";
    User = "admin";
  };
};
```

### Enabling Docker

```nix
virtualisation.docker.enable = true;
users.users.admin.extraGroups = [ "wheel" "docker" ];
```

### Opening Firewall Ports

```nix
networking.firewall.allowedTCPPorts = [ 22 80 443 ];
networking.firewall.allowedUDPPorts = [ ];
```

### Setting Static IPs

For stable addressing, replace DHCP with static IPs:

```nix
networking = {
  useDHCP = false;
  interfaces.end0 = {
    ipv4.addresses = [{
      address = "192.168.4.101";  # Unique per node
      prefixLength = 24;
    }];
  };
  defaultGateway = "192.168.4.1";
  nameservers = [ "192.168.4.1" "8.8.8.8" ];
};
```

**Note**: For per-node IPs, you'll need to modify `flake.nix` to pass different addresses to each node.

### Adding SSH Keys

```nix
users.users.admin.openssh.authorizedKeys.keys = [
  "ssh-ed25519 AAAA... user@host"
  # Add additional keys here
];
```

---

## Troubleshooting

### Node Not Reachable

**Symptoms**: `ssh admin@nodeX.local` times out or refuses connection.

**Checklist**:
1. **Wait**: First boot takes 2-5 minutes
2. **Check power**: LED should be on
3. **Check network**: Ethernet cable connected, link lights active
4. **Check router**: Look for nodeX in DHCP lease table
5. **Try IP directly**: `ssh admin@192.168.4.XXX`
6. **Connect monitor**: Check for boot errors

### mDNS Not Working

**Symptoms**: `nodeX.local` doesn't resolve but IP works.

**Causes**:
- Network blocks multicast (corporate networks)
- macOS mDNS cache stale

**Solutions**:
```bash
# Flush macOS DNS cache
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder

# Use IP instead
ssh admin@192.168.4.250
```

### Build Fails on Desktop

**Symptoms**: `nix build` errors out.

**Checklist**:
```bash
# Check disk space
df -h /

# Check Nix daemon running
systemctl status nix-daemon

# Verify flakes enabled
nix --version
grep experimental-features ~/.config/nix/nix.conf

# Try with verbose output
nix build .#node1-sdImage -L
```

### Deployment Fails

**Symptoms**: `nixos-rebuild switch` fails.

**Common causes**:
- Network timeout: Node is busy or unreachable
- Build failure: Check error message for missing dependencies
- Disk full on node: Check with `df -h /`

**Solutions**:
```bash
# Check node is reachable
ssh admin@node1.local echo "OK"

# Check disk space on node
ssh admin@node1.local df -h /

# Garbage collect on node
ssh admin@node1.local sudo nix-collect-garbage -d
```

### Node Won't Boot

**Symptoms**: No network activity, no mDNS, nothing on monitor.

**Checklist**:
1. **SD card seated**: Remove and reinsert firmly
2. **Power supply**: Ensure 12V/2A, check barrel jack connection
3. **SD card corruption**: Reflash the SD card
4. **Boot selection**: Ensure booting from SD, not eMMC

### SSH Key Rejected

**Symptoms**: `Permission denied (publickey)`

**Solutions**:
```bash
# Check your key is loaded
ssh-add -l

# Add key if missing
ssh-add ~/.ssh/id_ed25519

# Verify key matches configuration.nix
cat ~/.ssh/id_ed25519.pub
# Compare with keys in configuration.nix
```

---

## Appendix: NixOS Concepts

### Declarative Configuration

Unlike traditional Linux where you run commands to install software, NixOS describes the desired state in configuration files. The system is then built to match.

**Traditional**: `apt install nginx` (imperative)
**NixOS**: Add `nginx` to `configuration.nix`, rebuild (declarative)

### Generations

Every rebuild creates a new "generation". You can:
- List generations: `sudo nix-env --list-generations -p /nix/var/nix/profiles/system`
- Rollback: `sudo nixos-rebuild switch --rollback`
- Boot old generation: Select from bootloader menu

### Flakes

Flakes provide reproducible builds by pinning all dependencies in `flake.lock`. The same `flake.lock` produces the exact same system.

**Update dependencies**: `nix flake update`
**Check validity**: `nix flake check`

### The Nix Store

All packages live in `/nix/store/` with content-addressed paths like:
```
/nix/store/abc123...-nginx-1.24.0
```

This enables:
- Multiple versions simultaneously
- Atomic upgrades and rollbacks
- Reproducible builds

---

## Quick Reference

| Task | Command |
|------|---------|
| SSH to node | `ssh admin@node1.local` |
| SSH via jump host | `ssh -J samuel@desktop admin@node1.local` |
| Check all nodes | `for i in 1..7; do ssh admin@node$i.local uptime; done` |
| Build image | `nix build .#node1-sdImage` |
| Deploy to node | `ssh admin@node1.local "sudo nixos-rebuild switch --flake 'git+ssh://...#node1' --refresh"` |
| Update flake | `nix flake update` |
| Rollback node | `ssh admin@node1.local sudo nixos-rebuild switch --rollback` |
| View logs | `ssh admin@node1.local journalctl -f` |
| Reboot node | `ssh admin@node1.local sudo reboot` |
| K8s nodes | `ssh admin@node1.local kubectl get nodes` |
| K8s pods | `ssh admin@node1.local kubectl get pods -A` |
| Deploy app | `ssh admin@node1.local kubectl apply -f app.yaml` |
| K8s tutorial | `k8s/examples/README.md` |
| K8s logs | `ssh admin@node1.local kubectl logs <pod>` |
| K3s status | `ssh admin@node1.local systemctl status k3s` |
