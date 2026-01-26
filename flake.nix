{
  description = "NixOS configuration for Odroid C4 cluster";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    pqcoin = {
      url = "github:SamuelSchlesinger/pqcoin/dev";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, pqcoin, ... }:
  let
    # Helper to create a node configuration
    mkNode = hostname: nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        ./hardware-configuration.nix
        ./configuration.nix
        ./k3s.nix
        ./gitops.nix
        pqcoin.nixosModules.default
        ./pqcoin.nix  # Enable pqcoin mining on all nodes
        { networking.hostName = hostname; }
      ];
    };
  in {
    nixosConfigurations = {
      # Generic configuration
      odroid-c4 = mkNode "odroid-c4";

      # node1 - monitoring hub (Prometheus + Grafana) + K3s initial server
      node1 = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          ./hardware-configuration.nix
          ./configuration.nix
          ./k3s.nix
          ./monitoring.nix
          ./gitops.nix
          pqcoin.nixosModules.default
          ./pqcoin.nix  # Enable pqcoin mining
          { networking.hostName = "node1"; }
        ];
      };

      # Other nodes
      node2 = mkNode "node2";
      node3 = mkNode "node3";
      node4 = mkNode "node4";
      node5 = mkNode "node5";
      node6 = mkNode "node6";
      node7 = mkNode "node7";
    };

    # SD card image outputs
    packages.aarch64-linux = {
      sdImage = self.nixosConfigurations.odroid-c4.config.system.build.sdImage;
      node1-sdImage = self.nixosConfigurations.node1.config.system.build.sdImage;
      node2-sdImage = self.nixosConfigurations.node2.config.system.build.sdImage;
      node3-sdImage = self.nixosConfigurations.node3.config.system.build.sdImage;
      node4-sdImage = self.nixosConfigurations.node4.config.system.build.sdImage;
      node5-sdImage = self.nixosConfigurations.node5.config.system.build.sdImage;
      node6-sdImage = self.nixosConfigurations.node6.config.system.build.sdImage;
      node7-sdImage = self.nixosConfigurations.node7.config.system.build.sdImage;
    };
  };
}
