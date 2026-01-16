# K3s Kubernetes cluster configuration
# All 7 nodes run as servers for maximum redundancy
{ config, pkgs, lib, ... }:

let
  # node1 is the initial server; others join it
  initialServer = "node1.local";

  # Determine if this node is the initial server
  isInitialServer = config.networking.hostName == "node1";
in
{
  services.k3s = {
    enable = true;
    role = "server";

    # Token file for cluster authentication (must exist on all nodes)
    tokenFile = "/etc/k3s/token";

    # Initial server bootstraps the cluster; others join it
    clusterInit = isInitialServer;
    serverAddr = lib.mkIf (!isInitialServer) "https://${initialServer}:6443";

    extraFlags = toString [
      "--disable=traefik"           # Skip ingress controller
      "--disable=servicelb"         # Skip load balancer
      "--flannel-backend=vxlan"     # Lightweight networking
      "--write-kubeconfig-mode=644" # Allow non-root kubeconfig access
    ];
  };

  # Ensure token directory exists
  systemd.tmpfiles.rules = [
    "d /etc/k3s 0755 root root -"
  ];

  # Firewall ports for K3s
  networking.firewall = {
    allowedTCPPorts = [
      6443  # Kubernetes API
      2379  # etcd client
      2380  # etcd peer
      10250 # Kubelet metrics
    ];
    allowedUDPPorts = [
      8472  # Flannel VXLAN
    ];
  };

  # Kubectl config for admin user
  environment.variables.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
}
