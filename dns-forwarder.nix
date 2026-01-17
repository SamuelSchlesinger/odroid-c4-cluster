# DNS port forwarding: forward port 53 to K3s NodePort 30053
# This allows clients to query Blocky on the standard DNS port
{ config, pkgs, lib, ... }:

{
  # Enable IP forwarding (required for NAT)
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

  # Open DNS ports in firewall
  networking.firewall.allowedUDPPorts = [ 53 ];
  networking.firewall.allowedTCPPorts = [ 53 ];

  # NAT rules to redirect port 53 to NodePort 30053
  networking.nftables.enable = false;  # Use iptables for NAT
  networking.nat = {
    enable = true;
    internalInterfaces = [ "eth0" ];
    externalInterface = "eth0";
    forwardPorts = [
      # UDP DNS (primary)
      {
        destination = "127.0.0.1:30053";
        proto = "udp";
        sourcePort = 53;
      }
      # TCP DNS (for large responses)
      {
        destination = "127.0.0.1:30054";
        proto = "tcp";
        sourcePort = 53;
      }
    ];
  };
}
