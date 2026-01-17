# DNS firewall rules for Blocky
# Blocky binds directly to port 53 via Kubernetes hostPort
{ config, pkgs, lib, ... }:

{
  # Open DNS ports in firewall
  networking.firewall.allowedUDPPorts = [ 53 ];
  networking.firewall.allowedTCPPorts = [ 53 ];
}
