# pqcoin configuration for the Odroid cluster
# Include this module in nodes that should run pqcoin
#
# The pqcoin NixOS module is provided by the pqcoin flake input.
# This file just provides cluster-specific configuration.

{ config, lib, ... }:

let
  # Toggle to enable/disable pqcoin mining
  # Set to false to speed up builds (pqcoin Rust compilation is slow)
  enablePqcoin = true;
in
{
  services.pqcoin = {
    enable = enablePqcoin;
    testnet = true;
    mine = true;

    rpc = {
      enable = true;
      bind = "0.0.0.0";
      port = 8332;
    };

    p2p = {
      port = 8333;
      # Seed peers: desktop and MacBook on Tailscale
      seedPeers = [
        "100.123.199.53:8333"   # desktop
        "100.120.248.123:8333"  # MacBook
      ];
    };

    logLevel = "info";
  };
}
