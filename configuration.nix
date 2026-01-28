{ config, pkgs, lib, ... }:

let
  hostname = config.networking.hostName;

  # All build machines in the cluster
  allBuildMachines = [
    { hostName = "node1.local"; sshUser = "root"; sshKey = "/root/.ssh/id_ed25519"; system = "aarch64-linux"; maxJobs = 4; speedFactor = 1; supportedFeatures = [ "nixos-test" "big-parallel" ]; }
    { hostName = "node2.local"; sshUser = "root"; sshKey = "/root/.ssh/id_ed25519"; system = "aarch64-linux"; maxJobs = 4; speedFactor = 1; supportedFeatures = [ "nixos-test" "big-parallel" ]; }
    { hostName = "node3.local"; sshUser = "root"; sshKey = "/root/.ssh/id_ed25519"; system = "aarch64-linux"; maxJobs = 4; speedFactor = 1; supportedFeatures = [ "nixos-test" "big-parallel" ]; }
    { hostName = "node4.local"; sshUser = "root"; sshKey = "/root/.ssh/id_ed25519"; system = "aarch64-linux"; maxJobs = 4; speedFactor = 1; supportedFeatures = [ "nixos-test" "big-parallel" ]; }
    { hostName = "node5.local"; sshUser = "root"; sshKey = "/root/.ssh/id_ed25519"; system = "aarch64-linux"; maxJobs = 4; speedFactor = 1; supportedFeatures = [ "nixos-test" "big-parallel" ]; }
    { hostName = "node6.local"; sshUser = "root"; sshKey = "/root/.ssh/id_ed25519"; system = "aarch64-linux"; maxJobs = 4; speedFactor = 1; supportedFeatures = [ "nixos-test" "big-parallel" ]; }
    { hostName = "node7.local"; sshUser = "root"; sshKey = "/root/.ssh/id_ed25519"; system = "aarch64-linux"; maxJobs = 4; speedFactor = 1; supportedFeatures = [ "nixos-test" "big-parallel" ]; }
  ];

  # Exclude the current node from its own builder list to avoid self-referential builds
  buildMachines = builtins.filter (m: m.hostName != "${hostname}.local") allBuildMachines;
in
{
  # System basics
  system.stateVersion = "24.11";

  networking = {
    hostName = lib.mkDefault "odroid-c4";

    # Use DHCP on all interfaces (systemd-networkd handles naming)
    useDHCP = true;

    # Firewall - allow SSH and node_exporter
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 9100 ];
    };
  };

  # Time zone - adjust as needed
  time.timeZone = "America/New_York";

  # Locale
  i18n.defaultLocale = "en_US.UTF-8";

  # User configuration
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    # SSH public keys for passwordless access
    openssh.authorizedKeys.keys = [
      # MacBook
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOv/btyrQGVnaGQCLEdkOGKtGgSN2TmdFMgDyst4tpaz samuelschlesinger@Samuels-MacBook-Pro.local"
      # Desktop
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMXkHnuxSPuZfVl1vMa6h4H230X3s1f3ch4oZGKTz91f samuel@desktop"
    ];
    # No password set - SSH key only
    # For emergency console access, set one after first boot:
    #   sudo passwd admin
  };

  # Allow admin to use sudo without password
  security.sudo.wheelNeedsPassword = false;

  # SSH server configuration
  services.openssh = {
    enable = true;
    settings = {
      # Allow root login with SSH keys only (required for centralized GitOps)
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  # SSH client config for distributed builds - keepalives prevent stalls
  programs.ssh.extraConfig = ''
    Host *.local
      ServerAliveInterval 30
      ServerAliveCountMax 3
  '';

  # mDNS for hostname.local discovery
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };

  # Node exporter for Prometheus metrics (all nodes)
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    enabledCollectors = [
      "systemd"
      "processes"
    ];
  };

  # Basic packages
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    tmux
    curl
    wget
    kubectl     # Kubernetes CLI
  ];

  # Enable flakes and nix settings
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      trusted-users = [ "root" "admin" ];
      # Binary cache
      substituters = [ "https://cache.nixos.org" ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "odroid-cluster:h/8zXapPMFf2htwIuN5Pgu5e59wubGIJjbAeO+5GPK8="
      ];
      # Sign builds with cluster key (for nix copy between nodes)
      secret-key-files = "/etc/nix/cache-priv-key.pem";

      # Resilience settings for distributed builds (mitigate Nix bug #5701)
      builders-use-substitutes = true;  # Let builders fetch from cache directly
      connect-timeout = 10;              # Fail fast on unreachable nodes
      fallback = true;                   # Fall back to local build if remote fails
    };

    # Distributed builds: node1 can use all nodes to build faster
    # Each node excludes itself from the builder list (see buildMachines variable above)
    distributedBuilds = true;
    inherit buildMachines;
  };

  # Automatic garbage collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # Enable root SSH for centralized deployments (key-based only)
  users.users.root.openssh.authorizedKeys.keys = [
    # Cluster root key for centralized GitOps deployments
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBNJtdWB67MZTwLn8dyyyPV4pvQAWpfUeZ3TwKLjCnXw root@odroid-cluster"
  ];
}
