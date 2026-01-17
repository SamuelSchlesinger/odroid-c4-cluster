# DNS firewall rules for Blocky
# Blocky binds directly to port 53 via Kubernetes hostPort
{ config, pkgs, lib, ... }:

{
  # Open DNS ports in firewall
  networking.firewall.allowedUDPPorts = [
    53      # DNS (hostPort - not working yet)
    30053   # DNS NodePort (UDP)
  ];
  networking.firewall.allowedTCPPorts = [
    53      # DNS (hostPort - not working yet)
    30054   # DNS NodePort (TCP)
    30055   # Blocky metrics (for Prometheus scraping)
  ];
}
