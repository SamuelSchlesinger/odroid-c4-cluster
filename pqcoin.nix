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

  hostname = config.networking.hostName;
  isNode1 = hostname == "node1";
in
{
  # Use the new multi-instance module API
  services.pqcoin.instances.testnet = {
    enable = enablePqcoin;
    network = "testnet";
    mine = true;

    rpc = {
      enable = true;
      bind = "0.0.0.0";
      port = 8332;
    };

    p2p = {
      port = 8333;
      # node1 is the seed peer for the cluster
      # Other nodes connect to node1, which acts as the hub
      # Note: pqcoin requires IP address, not hostname
      seedPeers = if isNode1 then [] else [ "192.168.4.250:8333" ];
    };

    logLevel = "info";
  };
}
