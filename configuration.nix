{ config, pkgs, lib, ... }:

{
  # System basics
  system.stateVersion = "24.11";

  networking = {
    hostName = lib.mkDefault "odroid-c4";

    # Use DHCP on all interfaces (systemd-networkd handles naming)
    useDHCP = true;

    # Firewall - allow SSH
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];
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
      # Cluster inter-node keys
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGJMIjIb1qAgKWU086/kUyIBKd9XyjVWbF4hynKEBM0N node1@odroid-cluster"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGJxhsHA7yi4xjIWU/02GVgf2+rgTV42sBCLUQQW6weK node2@odroid-cluster"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL/+JcifKBcX5BpYUA4djZYGULZf1KhCsMz6k2khtC+D node3@odroid-cluster"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJtJ/2a3fUEpN8sb/cwt3YCJiW2maoKT09J7g7XGTFVk node4@odroid-cluster"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDHXcKemfTwa6pi3DCF4cyvokTep9vkBi41TP9I8k92W node5@odroid-cluster"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDC0uDTQ1qhaxtmUa/MH/EuTzdTEDqvjHvkdX5lQB+zV node6@odroid-cluster"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINMWheVDO8zSLoF3CCwM9YwsDYhjvZlMW9jwPFKsMLrZ node7@odroid-cluster"
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
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

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

  # Basic packages
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    tmux
    curl
    wget
  ];

  # Enable flakes and distributed builds
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      trusted-users = [ "root" "admin" ];
      # Trust builds signed by our cluster
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "odroid-cluster:h/8zXapPMFf2htwIuN5Pgu5e59wubGIJjbAeO+5GPK8="
      ];
      # Sign all builds with our cluster key
      secret-key-files = "/etc/nix/cache-priv-key.pem";
    };

    # Enable distributed builds across the cluster
    distributedBuilds = true;

    # All cluster nodes as build machines (4 cores each)
    buildMachines = [
      { hostName = "node1.local"; sshUser = "root"; sshKey = "/root/.ssh/id_ed25519"; system = "aarch64-linux"; maxJobs = 4; speedFactor = 1; supportedFeatures = [ "nixos-test" "big-parallel" ]; }
      { hostName = "node2.local"; sshUser = "root"; sshKey = "/root/.ssh/id_ed25519"; system = "aarch64-linux"; maxJobs = 4; speedFactor = 1; supportedFeatures = [ "nixos-test" "big-parallel" ]; }
      { hostName = "node3.local"; sshUser = "root"; sshKey = "/root/.ssh/id_ed25519"; system = "aarch64-linux"; maxJobs = 4; speedFactor = 1; supportedFeatures = [ "nixos-test" "big-parallel" ]; }
      { hostName = "node4.local"; sshUser = "root"; sshKey = "/root/.ssh/id_ed25519"; system = "aarch64-linux"; maxJobs = 4; speedFactor = 1; supportedFeatures = [ "nixos-test" "big-parallel" ]; }
      { hostName = "node5.local"; sshUser = "root"; sshKey = "/root/.ssh/id_ed25519"; system = "aarch64-linux"; maxJobs = 4; speedFactor = 1; supportedFeatures = [ "nixos-test" "big-parallel" ]; }
      { hostName = "node6.local"; sshUser = "root"; sshKey = "/root/.ssh/id_ed25519"; system = "aarch64-linux"; maxJobs = 4; speedFactor = 1; supportedFeatures = [ "nixos-test" "big-parallel" ]; }
      { hostName = "node7.local"; sshUser = "root"; sshKey = "/root/.ssh/id_ed25519"; system = "aarch64-linux"; maxJobs = 4; speedFactor = 1; supportedFeatures = [ "nixos-test" "big-parallel" ]; }
    ];
  };

  # Automatic garbage collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # Enable root SSH for distributed builds (key-based only)
  users.users.root.openssh.authorizedKeys.keys = [
    # Cluster root key for distributed builds
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBNJtdWB67MZTwLn8dyyyPV4pvQAWpfUeZ3TwKLjCnXw root@odroid-cluster"
  ];
}
