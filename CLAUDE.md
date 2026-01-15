# Claude Operating Guide - Odroid C4 Cluster

Instructions for Claude workers operating in this repository.

## Repository Purpose

This repository contains the **NixOS configuration for a 7-node Odroid C4 cluster**. It is synced between:
- **MacBook** (`~/sysadmin/odroid-c4/`) - Configuration editing, SD card flashing
- **Desktop** (`samuel@desktop:~/sysadmin/odroid-c4/`) - Nix builds, deployments

## Quick Reference

| Task | Command |
|------|---------|
| Check cluster health | See [Health Check](#health-check) below |
| SSH to node | `ssh admin@node1.local` (or via jump host) |
| Build image | On desktop: `nix build .#node1-sdImage` |
| Deploy to node | On desktop: `nixos-rebuild switch --flake .#node1 --target-host admin@node1.local --build-host admin@node1.local` |
| Update packages | On desktop: `nix flake update && git add flake.lock && git commit && git push` |
| Sync repo | `git pull origin main` / `git push origin main` |

## Network Access

### From Desktop (Local Network)
```bash
ssh admin@node1.local
ssh admin@node2.local
# ... through node7.local
```

### From MacBook (Remote via Tailscale)
```bash
# Option 1: Jump through desktop
ssh -J samuel@desktop admin@node1.local

# Option 2: Two hops
ssh samuel@desktop
ssh admin@node1.local
```

### Current Node IPs
| Node | mDNS | IP (may change) |
|------|------|-----------------|
| node1 | node1.local | 192.168.4.250 |
| node2 | node2.local | 192.168.5.0 |
| node3 | node3.local | 192.168.4.255 |
| node4 | node4.local | 192.168.4.254 |
| node5 | node5.local | 192.168.4.251 |
| node6 | node6.local | 192.168.4.253 |
| node7 | node7.local | 192.168.4.252 |

## Health Check

Run this to check all nodes:

```bash
for i in 1 2 3 4 5 6 7; do
  echo "=== node$i ==="
  ssh admin@node$i.local "uptime && free -h && df -h /" 2>&1 || echo "UNREACHABLE"
done
```

For remote access from MacBook, use the desktop as jump host:

```bash
for i in 1 2 3 4 5 6 7; do
  echo "=== node$i ==="
  ssh -J samuel@desktop admin@node$i.local "uptime && free -h && df -h /" 2>&1 || echo "UNREACHABLE"
done
```

## Key Files

| File | Purpose | Edit Frequency |
|------|---------|----------------|
| `configuration.nix` | All system settings (users, packages, services) | Often |
| `flake.nix` | Node definitions, build outputs | Rarely |
| `flake.lock` | Pinned nixpkgs version | Only when updating packages |
| `hardware-configuration.nix` | Boot/hardware settings | Rarely |
| `CLUSTER-GUIDE.md` | Comprehensive documentation | As needed |

## Common Operations

### Making Configuration Changes

1. Edit `configuration.nix` (or other files)
2. Commit and push:
   ```bash
   git add -A && git commit -m "Description" && git push
   ```
3. Deploy from desktop:
   ```bash
   ssh samuel@desktop "cd ~/sysadmin/odroid-c4 && git pull && nixos-rebuild switch --flake .#node1 --target-host admin@node1.local --build-host admin@node1.local"
   ```

### Adding a Package

Edit `configuration.nix`:
```nix
environment.systemPackages = with pkgs; [
  vim git htop tmux curl wget
  # Add here:
  newpackage
];
```

### Adding a Service

Edit `configuration.nix`:
```nix
systemd.services.myservice = {
  description = "My Service";
  wantedBy = [ "multi-user.target" ];
  serviceConfig = {
    ExecStart = "${pkgs.mypackage}/bin/mycommand";
    Restart = "always";
  };
};
```

### Opening a Firewall Port

Edit `configuration.nix`:
```nix
networking.firewall.allowedTCPPorts = [ 22 80 443 ];
```

### Updating NixOS Packages

**Warning**: Only do this if you plan to rebuild all nodes. The `flake.lock` must match deployed nodes.

```bash
# On desktop
cd ~/sysadmin/odroid-c4
nix flake update
git add flake.lock
git commit -m "Update flake inputs"
git push

# Then deploy to all nodes
for i in 1 2 3 4 5 6 7; do
  nixos-rebuild switch --flake .#node$i \
    --target-host admin@node$i.local \
    --build-host admin@node$i.local
done
```

## Guidelines for Claude Workers

### Do
- Run health checks before making changes
- Read `CLUSTER-GUIDE.md` for detailed documentation
- Test changes on one node before deploying to all
- Commit changes with clear messages
- Push changes so both machines stay in sync

### Don't
- Run `nix flake update` without planning full deployment
- Modify `flake.lock` manually
- Change SSH keys without explicit request
- Deploy untested configurations to all nodes at once

### Verifying Changes

After deployment, verify the change took effect:

```bash
# Check NixOS version
ssh admin@node1.local cat /run/current-system/nixos-version

# Check a package is installed
ssh admin@node1.local which newpackage

# Check a service is running
ssh admin@node1.local systemctl status myservice
```

### Rollback

If something breaks:

```bash
ssh admin@node1.local sudo nixos-rebuild switch --rollback
```

## Build Machine Access

Nix is installed on the desktop, not the MacBook. For any `nix` commands:

```bash
# From MacBook
ssh samuel@desktop "cd ~/sysadmin/odroid-c4 && nix build .#node1-sdImage"

# Or SSH to desktop first
ssh samuel@desktop
cd ~/sysadmin/odroid-c4
nix build .#node1-sdImage
```

## Cluster Specifications

| Property | Value |
|----------|-------|
| Nodes | 7 × Odroid C4 |
| CPU | 4× Cortex-A55 per node (28 cores total) |
| RAM | 4GB per node (28GB total) |
| OS | NixOS 24.11 |
| Kernel | 6.6 LTS |
| Network | Gigabit Ethernet, DHCP, mDNS |
| SSH User | `admin` (passwordless sudo) |

## Troubleshooting

### Node unreachable
1. Check if other nodes work (network issue vs single node)
2. Try IP instead of mDNS: `ssh admin@192.168.4.250`
3. Check router DHCP leases for current IP
4. Physical check: power LED, ethernet link lights

### Build fails
```bash
# On desktop
df -h /                          # Check disk space
nix-collect-garbage -d           # Free space if needed
nix build .#node1-sdImage -L     # Verbose output
```

### Deployment fails
```bash
# Check node is reachable
ssh admin@node1.local echo OK

# Check disk space on node
ssh admin@node1.local df -h /

# Clean up old generations
ssh admin@node1.local sudo nix-collect-garbage -d
```

## Repository Sync

This repo is hosted at: `github.com/SamuelSchlesinger/odroid-c4-cluster` (private)

Always pull before making changes:
```bash
git pull origin main
```

Always push after making changes:
```bash
git push origin main
```
