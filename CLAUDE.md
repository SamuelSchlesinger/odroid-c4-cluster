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
| SSH to node | `ssh admin@node1.local` (or via desktop as jump host `ssh -J samuel@desktop admin@node1.local`) |
| Build image | On desktop: `nix build .#node1-sdImage` |
| **Deploy changes** | `git commit && git push` (GitOps auto-deploys within ~20s) |
| Manual deploy | `ssh admin@node1.local "sudo systemctl start auto-deploy"` |
| Check GitOps status | `ssh admin@node1.local "journalctl -u auto-deploy -n 20"` |
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

**Setup**: The go-links nginx proxy runs on the desktop. DNS resolution is via `/etc/hosts` on each client machine (pointing `go` to the desktop's Tailscale IP).

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

### Node Hostnames

Nodes are accessible via mDNS: `node1.local` through `node7.local`. IPs are assigned via DHCP.

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

**Access**: Use `go/grafana` or `http://node1.local:3000`.

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

## GitOps Auto-Deploy

The cluster automatically deploys changes when you push to GitHub. No manual deployment needed.

### How It Works

1. Each node runs a systemd timer that checks GitHub every 15 seconds
2. If a new commit is detected, `nixos-rebuild switch` runs automatically
3. The deployed revision is stored in `/var/lib/auto-deploy/revision`

### Usage

Just commit and push:
```bash
git add -A && git commit -m "your change" && git push
```

Within ~20 seconds, all nodes will detect and deploy the change.

### Monitoring GitOps

```bash
# Check recent deploy activity
ssh admin@node1.local "journalctl -u auto-deploy -n 20"

# Check current deployed revision
ssh admin@node1.local "cat /var/lib/auto-deploy/revision"

# Check timer status
ssh admin@node1.local "systemctl status auto-deploy.timer"

# Manually trigger deploy (if needed)
ssh admin@node1.local "sudo systemctl start auto-deploy"
```

### Key Files

- `gitops.nix` - Auto-deploy service and timer configuration
- `/var/lib/auto-deploy/revision` - Stored revision on each node

### Troubleshooting GitOps

If auto-deploy fails:
```bash
# Check logs for errors
ssh admin@node1.local "journalctl -u auto-deploy -n 50"

# Common issues:
# - GitHub SSH access: check /root/.ssh/id_ed25519 exists
# - Network: ensure node can reach github.com
# - Disk space: run nix-collect-garbage -d
```

## Kubernetes (K3s)

The cluster runs K3s with 3 server nodes (control plane) and 4 agent nodes (workers). This provides fault tolerance for 1 server failure while keeping etcd responsive.

### Architecture

- **Server nodes**: node1, node2, node3 (control plane + etcd)
- **Agent nodes**: node4, node5, node6, node7 (workers only)
- **Runtime**: containerd (bundled with K3s)
- **Networking**: Flannel VXLAN
- **Initial server**: node1 (has `--cluster-init`)
- **Token file**: `/etc/k3s/token` on all nodes

### Enabling/Disabling K3s

K3s can be toggled on or off to save energy when Kubernetes is not needed. Edit `k3s.nix` and change the `enableK3s` variable:

```nix
# In k3s.nix, line 8
enableK3s = true;   # Set to false to disable K3s
```

When disabled:
- K3s service won't start on any node
- K3s-related firewall ports are closed
- Saves ~200-400MB RAM per node

**To disable K3s:**
1. Edit `k3s.nix`: set `enableK3s = false;`
2. Commit and push: `git add -A && git commit -m "Disable K3s" && git push`
3. Deploy to all nodes (see [Deploying to All Nodes](#deploying-to-all-nodes))

**To re-enable K3s:**
1. Edit `k3s.nix`: set `enableK3s = true;`
2. Commit and push
3. Deploy to all nodes
4. The cluster will reform automatically (node1 bootstraps, others rejoin via token)

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
| `gitops.nix` | Auto-deploy service (15s polling) | Rarely |
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
3. **GitOps handles deployment automatically** - all nodes will detect and deploy within ~20 seconds

To monitor the rollout:
```bash
ssh -J samuel@desktop admin@node1.local "journalctl -u auto-deploy -f"
```

### Manual Deployment (if GitOps fails)

Normally GitOps handles deployment automatically. If you need to deploy manually:

```bash
# Trigger GitOps on all nodes
for i in 1 2 3 4 5 6 7; do
  ssh -J samuel@desktop admin@node$i.local "sudo systemctl start auto-deploy" &
done
wait

# Or bypass GitOps entirely (emergency)
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
| Orchestration | K3s v1.32 (3 servers + 4 agents) |
| Container Runtime | containerd (bundled with K3s) |
| Network | Gigabit Ethernet, DHCP, mDNS |
| SSH User | `admin` (passwordless sudo) |

## Troubleshooting

### Node unreachable
1. Check if other nodes work (network issue vs single node)
2. Try IP instead of mDNS (check router DHCP leases for current IP)
3. Physical check: power LED, ethernet link lights

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
