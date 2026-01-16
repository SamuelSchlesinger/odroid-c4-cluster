# K3s Kubernetes cluster configuration
# All 7 nodes run as servers for maximum redundancy
{ config, pkgs, lib, ... }:

let
  # Toggle to enable/disable K3s cluster
  # Set to false to save energy when Kubernetes is not needed
  enableK3s = false;

  # node1 is the initial server; others join it
  initialServer = "node1.local";

  # Determine if this node is the initial server
  isInitialServer = config.networking.hostName == "node1";
in
{
  services.k3s = {
    enable = enableK3s;
    role = "server";

    # Token file for cluster authentication (must exist on all nodes)
    tokenFile = "/etc/k3s/token";

    # Initial server bootstraps the cluster; others join it
    clusterInit = isInitialServer;
    serverAddr = lib.mkIf (!isInitialServer) "https://${initialServer}:6443";

    extraFlags = toString ([
      # Traefik is a reverse proxy/ingress controller that routes external HTTP
      # traffic to pods. Disabled because: (1) it uses ~100MB RAM per node which
      # is significant on 4GB ARM boards, (2) we use NodePort for simplicity,
      # (3) no external load balancer exists for this home cluster anyway.
      "--disable=traefik"
      "--disable=servicelb"         # No external LB in home network
      "--flannel-backend=vxlan"     # Lightweight networking
      "--write-kubeconfig-mode=644" # Allow non-root kubeconfig access
    ] ++ (if isInitialServer then [
      # TLS SANs for mDNS hostnames (required for other nodes to join via .local)
      "--tls-san=node1.local"
      "--tls-san=node2.local"
      "--tls-san=node3.local"
      "--tls-san=node4.local"
      "--tls-san=node5.local"
      "--tls-san=node6.local"
      "--tls-san=node7.local"
    ] else []));
  };

  # Ensure token directory exists
  systemd.tmpfiles.rules = [
    "d /etc/k3s 0755 root root -"
  ];

  # Firewall ports for K3s (only opened when K3s is enabled)
  networking.firewall = lib.mkIf enableK3s {
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

  # Kubectl config for admin user (only set when K3s is enabled)
  environment.variables = lib.mkIf enableK3s {
    KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
  };
}
