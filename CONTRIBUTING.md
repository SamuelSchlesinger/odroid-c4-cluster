# Contributing to Odroid C4 Cluster

Thank you for your interest in contributing to this NixOS cluster project! Whether you're fixing a bug, adding a feature, or improving documentation, your help is appreciated.

## Getting Started

### Prerequisites

1. **Nix installed** with flakes enabled
2. **SSH access** to cluster nodes (or access to the desktop build machine)
3. **Git** for version control

### Setup

```bash
git clone git@github.com:SamuelSchlesinger/odroid-c4-cluster.git
cd odroid-c4-cluster
```

## Making Changes

### 1. Edit Configuration Files

- `configuration.nix` - Base system settings, packages, users
- `k3s.nix` - Kubernetes cluster configuration
- `monitoring.nix` - Prometheus and Grafana setup
- `gitops.nix` - Auto-deploy service
- `flake.nix` - Node definitions and build outputs

### 2. Validate Your Changes

```bash
nix flake check
```

### 3. Test on a Single Node First

Before deploying to all nodes, test on one:

```bash
ssh admin@node1.local "sudo nixos-rebuild switch --flake 'git+ssh://git@github.com/SamuelSchlesinger/odroid-c4-cluster#node1'"
```

Verify the change works as expected before proceeding.

### 4. Deploy to All Nodes

Once validated, push your changes and GitOps will auto-deploy within ~20 seconds:

```bash
git push origin main
```

## Commit Messages

- Use **imperative mood**: "Add feature" not "Added feature"
- Keep the summary line brief (50 chars or less)
- Add detail in the body if needed

Examples:
- `Add htop to system packages`
- `Fix firewall rule for Prometheus`
- `Update flake inputs to latest nixpkgs`

## Pull Request Process

1. Fork the repository
2. Create a feature branch
3. Make your changes and test thoroughly
4. Submit a PR with a clear description of what and why
5. Wait for review

## Code Style Guidelines

- **Keep it simple** - Avoid over-engineering; make minimal necessary changes
- **Document why, not what** - Code shows what; comments explain why
- **Prefer edits over new files** - Don't create unnecessary files
- **Test before committing** - Run `nix flake check` at minimum

## Getting Help

If you have questions or run into issues:

1. Check `CLUSTER-GUIDE.md` for detailed documentation
2. Check `CLAUDE.md` for operational procedures
3. Open an issue on GitHub

## Important Notes

- **Never** run `nix flake update` without planning to rebuild all nodes
- **Never** modify security settings (SSH keys, firewall) without explicit approval
- The `flake.lock` must stay in sync with deployed nodes
