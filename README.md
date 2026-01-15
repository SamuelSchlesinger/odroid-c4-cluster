# NixOS on Odroid C4 Cluster

Reproducible NixOS configuration for a 7-node Odroid C4 cluster using Tow-Boot.

## Quick Start

### 1. Build images on desktop (Linux)

```bash
# Copy config to desktop
scp -r ~/sysadmin/odroid-c4 samuel@desktop:~/sysadmin/

# SSH to desktop and build
ssh samuel@desktop
cd ~/sysadmin/odroid-c4
nix build .#packages.aarch64-linux.node1-sdImage -o result-node1
nix build .#packages.aarch64-linux.node2-sdImage -o result-node2
nix build .#packages.aarch64-linux.node3-sdImage -o result-node3
nix build .#packages.aarch64-linux.node4-sdImage -o result-node4
nix build .#packages.aarch64-linux.node5-sdImage -o result-node5
nix build .#packages.aarch64-linux.node6-sdImage -o result-node6
nix build .#packages.aarch64-linux.node7-sdImage -o result-node7
```

### 2. Transfer images to MacBook

```bash
mkdir -p ~/odroid-images
scp "samuel@desktop:~/sysadmin/odroid-c4/result-node*/sd-image/*.img.zst" ~/odroid-images/
```

### 3. Flash SD cards

```bash
cd ~/sysadmin/odroid-c4

# For each SD card:
./flash-with-towboot.sh ~/odroid-images/*node1*.img.zst /dev/disk8
# Label the SD card "node1", repeat for nodes 2-7
```

### 4. Boot and connect

1. Insert SD cards into Odroid C4s
2. Connect ethernet cables
3. Power on
4. Wait 2-3 minutes

```bash
ssh admin@node1.local
ssh admin@node2.local
# ... etc
```

## What's Configured

- **Bootloader:** Tow-Boot (written to each SD card)
- **SSH:** Key-only auth with your MacBook + desktop keys
- **User:** `admin` with passwordless sudo
- **mDNS:** Access via `nodeX.local`
- **Flakes:** Enabled for reproducible updates

## Files

```
odroid-c4/
├── flake.nix                    # 7 node definitions
├── configuration.nix            # System config (SSH, users, packages)
├── hardware-configuration.nix   # Odroid C4 hardware + Tow-Boot
├── flash-with-towboot.sh        # Flash script for macOS
├── odroid-C4-2023.07-007/       # Tow-Boot bootloader files
│   └── shared.disk-image.img
└── README.md
```

## Remote Updates

After initial deployment, update nodes without reflashing:

```bash
nixos-rebuild switch --flake .#node1 \
  --target-host admin@node1.local \
  --build-host admin@node1.local
```

## Adding Nodes

Edit `flake.nix`:

```nix
node8 = mkNode "node8";
```

Then add to the packages section:

```nix
node8-sdImage = self.nixosConfigurations.node8.config.system.build.sdImage;
```

## Troubleshooting

### Can't find node on network
- Wait up to 5 minutes for first boot
- Check router DHCP leases
- Connect a monitor to see boot messages

### SSH connection refused
- Verify node booted (check router for IP)
- Check your SSH key: `ssh-add -l`

### Build fails on desktop
- Ensure Nix has flakes enabled
- Check disk space: `df -h`
