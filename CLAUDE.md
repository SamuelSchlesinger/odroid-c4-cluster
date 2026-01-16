# Claude Operating Guide - Odroid C4 Cluster

Instructions for Claude workers operating in this repository.

## Repository Purpose

This repository contains the **NixOS configuration for a 7-node Odroid C4 cluster**. It is synced between:
- **MacBook** (`~/sysadmin/odroid-c4/`) - Configuration editing, SD card flashing
- **Desktop** (`samuel@desktop:~/sysadmin/odroid-c4/`) - Nix builds, deployments

## Quick Reference

| Task | Command |
|------|---------|
| **Kubernetes** | |
| Check K8s nodes | `ssh admin@node1.local "kubectl get nodes"` |
| Check all pods | `ssh admin@node1.local "kubectl get pods -A"` |
| Deploy workload | `ssh admin@node1.local "kubectl apply -f app.yaml"` |
| Deploy example | `kubectl apply -f https://raw.githubusercontent.com/.../k8s/examples/whoami-app.yaml` |
| K8s tutorial | See `k8s/examples/README.md` |
| K3s service status | `ssh admin@node1.local "systemctl status k3s"` |
| **NixOS** | |
| Check cluster health | See [Health Check](#health-check) below |
| SSH to node | `ssh admin@node1.local` (or via jump host) |
| Build image | On desktop: `nix build .#node1-sdImage` |
| Deploy to node | `ssh admin@node1.local "sudo nixos-rebuild switch --flake 'git+ssh://git@github.com/SamuelSchlesinger/odroid-c4-cluster#node1' --refresh"` |
| Deploy all nodes | See [Deploying to All Nodes](#deploying-to-all-nodes) |
| Update packages | On desktop: `nix flake update && git add flake.lock && git commit && git push` |
| Sync repo | `git pull origin main` / `git push origin main` |

## Go-Links (Quick Access)

Access cluster services via short URLs (requires Tailscale connection):

| Link | Destination |
|------|-------------|
| `go/` | Index page with all links |
| `go/grafana` | Grafana dashboards |
| `go/prometheus` | Prometheus UI |
| `go/prom` | Prometheus (short) |
| `go/node1` - `go/node7` | Node metrics (node_exporter) |

**Setup**: The go-links nginx proxy runs on the desktop. DNS resolution is via `/etc/hosts` on each client machine (`100.123.199.53 go` pointing to desktop's Tailscale IP).

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

## Monitoring Stack

The cluster runs Prometheus + Grafana for monitoring:

| Service | Location | Port | Purpose |
|---------|----------|------|---------|
| Prometheus | node1 | 9090 | Metrics aggregation, queries |
| Grafana | node1 | 3000 | Dashboards, visualization |
| node_exporter | all nodes | 9100 | System metrics (CPU, RAM, disk, network) |

**Access**: Use `go/grafana` or `http://node1.local:3000` (admin/admin).

**Key files**:
- `monitoring.nix` - Prometheus + Grafana config (node1 only)
- `configuration.nix` - node_exporter config (all nodes)

**Useful Prometheus queries**:
```promql
# CPU usage per node
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory available
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100

# Disk space remaining
node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"} * 100
```

## Kubernetes (K3s)

The cluster runs K3s with all 7 nodes as servers (HA control plane). This provides fault tolerance for up to 3 node failures.

### Architecture

- **Control plane**: All 7 nodes (etcd + API server)
- **Runtime**: containerd (bundled with K3s)
- **Networking**: Flannel VXLAN
- **Initial server**: node1 (has `--cluster-init`)
- **Token file**: `/etc/k3s/token` on all nodes

### Common K3s Operations

```bash
# Cluster status
kubectl get nodes -o wide
kubectl cluster-info

# View workloads
kubectl get pods -A
kubectl get deployments
kubectl get services

# Deploy application
kubectl apply -f deployment.yaml

# Quick test deployment
kubectl create deployment nginx --image=nginx:alpine --replicas=3
kubectl expose deployment nginx --port=80 --type=NodePort

# View logs
kubectl logs <pod-name>
kubectl logs -f <pod-name>  # Follow

# Execute in pod
kubectl exec -it <pod-name> -- sh

# Delete resources
kubectl delete deployment nginx
```

### K3s Troubleshooting

```bash
# Check K3s service
systemctl status k3s
journalctl -u k3s -f

# Check node status
kubectl describe node node1

# Restart K3s on a node
sudo systemctl restart k3s

# Check K3s token (must match on all nodes)
sudo cat /etc/k3s/token
```

### Kubeconfig Access

The kubeconfig is at `/etc/rancher/k3s/k3s.yaml` on each node:

```bash
# Copy to local machine
scp -J samuel@desktop admin@node1.local:/etc/rancher/k3s/k3s.yaml ~/.kube/config
# Edit server address: change 127.0.0.1 to node1.local
```

## Key Files

| File | Purpose | Edit Frequency |
|------|---------|----------------|
| `configuration.nix` | Base system settings (users, packages) | Often |
| `k3s.nix` | K3s Kubernetes cluster configuration | Rarely |
| `monitoring.nix` | Prometheus + Grafana for node1 | Rarely |
| `flake.nix` | Node definitions, build outputs | Rarely |
| `flake.lock` | Pinned nixpkgs version | Only when updating packages |
| `hardware-configuration.nix` | Boot/hardware settings | Rarely |
| `setup-distributed-builds.sh` | Root SSH + cache key setup | Rarely |
| `CLUSTER-GUIDE.md` | Comprehensive documentation | As needed |
| `k8s/examples/` | Kubernetes tutorials and example manifests | As needed |

## Common Operations

### Making Configuration Changes

1. Edit `configuration.nix` (or other files)
2. Commit and push:
   ```bash
   git add -A && git commit -m "Description" && git push
   ```
3. Deploy to nodes (nodes pull directly from GitHub):
   ```bash
   # Single node (from desktop or via jump host)
   ssh admin@node1.local "sudo nixos-rebuild switch --flake 'git+ssh://git@github.com/SamuelSchlesinger/odroid-c4-cluster#node1'"

   # From MacBook via jump host
   ssh -J samuel@desktop admin@node1.local "sudo nixos-rebuild switch --flake 'git+ssh://git@github.com/SamuelSchlesinger/odroid-c4-cluster#node1'"
   ```

### Deploying to All Nodes

Deploy to all nodes in parallel:
```bash
# From desktop
for i in 1 2 3 4 5 6 7; do
  ssh admin@node$i.local "sudo nixos-rebuild switch --flake 'git+ssh://git@github.com/SamuelSchlesinger/odroid-c4-cluster#node$i'" &
done
wait

# From MacBook (via jump host)
for i in 1 2 3 4 5 6 7; do
  ssh -J samuel@desktop admin@node$i.local "sudo nixos-rebuild switch --flake 'git+ssh://git@github.com/SamuelSchlesinger/odroid-c4-cluster#node$i'" &
done
wait
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

# Then deploy to all nodes (nodes pull from GitHub)
for i in 1 2 3 4 5 6 7; do
  ssh admin@node$i.local "sudo nixos-rebuild switch --flake 'git+ssh://git@github.com/SamuelSchlesinger/odroid-c4-cluster#node$i'" &
done
wait
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

## Distributed Builds

The cluster uses Nix distributed builds to share capacity across all 7 nodes (28 cores total). When you build on any node, Nix can offload work to other nodes automatically.

**How it works** (see `configuration.nix:99-112`):
1. `nix.distributedBuilds = true` enables the feature
2. `nix.buildMachines` lists all 7 nodes with their specs
3. Root SSH keys allow nix-daemon to connect between nodes
4. A shared signing key ensures nodes trust each other's builds

**Key configuration in configuration.nix**:
```nix
nix.distributedBuilds = true;
nix.buildMachines = [
  { hostName = "node1.local"; sshUser = "root"; sshKey = "/root/.ssh/id_ed25519";
    system = "aarch64-linux"; maxJobs = 4; ... }
  # ... all 7 nodes
];
```

**Using distributed builds**:
```bash
# Normal build - uses local + remote nodes
nix build nixpkgs#hello

# Force remote-only
nix build nixpkgs#hello --max-jobs 0
```

**Important**: Nodes don't share stores automatically. Each has its own `/nix/store`. Most packages come from cache.nixos.org; distributed builds help with custom derivations.

**Key files on each node**:
- `/root/.ssh/id_ed25519` - Root SSH key for inter-node access
- `/etc/nix/cache-priv-key.pem` - Signing key for builds

**Re-setup if needed**:
```bash
./setup-distributed-builds.sh    # Distributes root keys and signing keys
```

## SSH Key Storage

**Key storage** (MacBook and desktop):
- `~/.ssh/odroid-cluster/root-cluster` - Root key for distributed builds and GitHub access
- `~/.ssh/odroid-cluster/cache/` - Binary cache signing keys

**The root key (`root@odroid-cluster`) serves two purposes:**
1. Inter-node SSH for distributed builds (nodes can SSH to each other as root)
2. GitHub deploy key for pulling the private repo directly on nodes

**Security note:** The cluster root key is NOT authorized on the desktop or MacBook - nodes cannot SSH back to those machines.

## Cluster Specifications

| Property | Value |
|----------|-------|
| Nodes | 7 × Odroid C4 |
| CPU | 4× Cortex-A55 per node (28 cores total) |
| RAM | 4GB per node (28GB total) |
| OS | NixOS 25.05 |
| Kernel | 6.6 LTS |
| Orchestration | K3s v1.32 (all nodes as servers) |
| Container Runtime | containerd (bundled with K3s) |
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
