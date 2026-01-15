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
openssh.authorizedKeys.keys = [
  # MacBook
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOv/btyrQGVnaGQCLEdkOGKtGgSN2TmdFMgDyst4tpaz samuelschlesinger@Samuels-MacBook-Pro.local"
  # Desktop
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMXkHnuxSPuZfVl1vMa6h4H230X3s1f3ch4oZGKTz91f samuel@desktop"
  # Cluster inter-node keys (node1 through node7)
  "ssh-ed25519 ... node1@odroid-cluster"
  # ... (all 7 node keys)
];
```

### Inter-Node SSH Access

Nodes can SSH to each other directly for cluster operations:

```bash
# From node1, SSH to node2
ssh admin@node1.local
ssh node2 hostname   # Works directly between nodes
```

**Key Storage Locations**:
- MacBook: `~/.ssh/odroid-cluster/node{1-7}` (private) and `.pub` (public)
- Desktop: `~/.ssh/odroid-cluster/node{1-7}` (private) and `.pub` (public)
- Nodes: `~/.ssh/id_ed25519` (each node has its own key)

**Re-distributing Keys** (if needed):

```bash
# From MacBook, run the distribution script
./distribute-cluster-keys.sh        # All nodes
./distribute-cluster-keys.sh 3      # Single node
```

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

| Service | Purpose | Port |
|---------|---------|------|
| OpenSSH | Remote access | 22 |
| Avahi | mDNS discovery | 5353/udp |

### Installed Packages

```nix
environment.systemPackages = with pkgs; [
  vim      # Text editor
  git      # Version control
  htop     # Process monitor
  tmux     # Terminal multiplexer
  curl     # HTTP client
  wget     # File downloader
];
```

### Security Configuration

| Setting | Value | Notes |
|---------|-------|-------|
| SSH root login | Disabled | `PermitRootLogin = "no"` |
| Password auth | Disabled | SSH keys only |
| Firewall | Enabled | Only port 22 open |
| Sudo | Passwordless | For `admin` user via `wheel` group |

---

## Repository Structure

```
odroid-c4-cluster/
├── flake.nix                 # Nix flake: defines all 7 nodes
├── flake.lock                # Pinned dependencies (nixpkgs version)
├── configuration.nix         # Shared NixOS config for all nodes
├── hardware-configuration.nix # Odroid C4 hardware settings
├── flash-with-towboot.sh     # SD card flashing script (macOS)
├── distribute-cluster-keys.sh # SSH key distribution script
├── README.md                 # Quick start guide
├── CLUSTER-GUIDE.md          # This file
├── CLAUDE.md                 # Claude Code operational guide
└── odroid-C4-2023.07-007/    # Tow-Boot bootloader
    ├── binaries/
    │   ├── Tow-Boot.mmcboot.bin
    │   └── Tow-Boot.noenv.bin
    ├── config/
    │   ├── mmcboot.config
    │   └── noenv.config
    ├── mmcboot.installer.img
    └── shared.disk-image.img
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

For updates that don't require reflashing:

```bash
# On desktop (single node)
cd ~/sysadmin/odroid-c4
nixos-rebuild switch --flake .#node1 \
  --target-host admin@node1.local \
  --build-host admin@node1.local

# All nodes
for i in 1 2 3 4 5 6 7; do
  echo "=== Deploying to node$i ==="
  nixos-rebuild switch --flake .#node$i \
    --target-host admin@node$i.local \
    --build-host admin@node$i.local
done
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
| Deploy to node | `nixos-rebuild switch --flake .#node1 --target-host admin@node1.local --build-host admin@node1.local` |
| Update flake | `nix flake update` |
| Rollback node | `ssh admin@node1.local sudo nixos-rebuild switch --rollback` |
| View logs | `ssh admin@node1.local journalctl -f` |
| Reboot node | `ssh admin@node1.local sudo reboot` |
