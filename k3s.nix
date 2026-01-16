# K3s Kubernetes cluster configuration
# 3 server nodes (node1-3) for HA control plane, 4 agent nodes (node4-7) for workloads
{ config, pkgs, lib, ... }:

let
  # Toggle to enable/disable K3s cluster
  # Set to false to save energy when Kubernetes is not needed
  enableK3s = true;

  # node1 is the initial server; other servers join it
  initialServer = "node1.local";

  # Server nodes run control plane + etcd (3 nodes = tolerates 1 failure)
  serverNodes = [ "node1" "node2" "node3" ];

  # Agent nodes run workloads only (no control plane overhead)
  agentNodes = [ "node4" "node5" "node6" "node7" ];

  hostname = config.networking.hostName;
  isServer = builtins.elem hostname serverNodes;
  isAgent = builtins.elem hostname agentNodes;
  isInitialServer = hostname == "node1";
in
{
  services.k3s = {
    enable = enableK3s;
    role = if isServer then "server" else "agent";

    # Token file for cluster authentication (must exist on all nodes)
    tokenFile = "/etc/k3s/token";

    # Initial server bootstraps the cluster; others join it
    clusterInit = isInitialServer;
    serverAddr = lib.mkIf (!isInitialServer) "https://${initialServer}:6443";

    extraFlags = toString (
      # Server-specific flags
      (lib.optionals isServer [
        # Traefik is a reverse proxy/ingress controller that routes external HTTP
        # traffic to pods. Disabled because: (1) it uses ~100MB RAM per node which
        # is significant on 4GB ARM boards, (2) we use NodePort for simplicity,
        # (3) no external load balancer exists for this home cluster anyway.
        "--disable=traefik"
        "--disable=servicelb"         # No external LB in home network
        "--flannel-backend=host-gw"   # Direct routing (all nodes on same L2 network)
        "--write-kubeconfig-mode=644" # Allow non-root kubeconfig access
      ])
      # TLS SANs only needed on initial server
      ++ (lib.optionals isInitialServer [
        "--tls-san=node1.local"
        "--tls-san=node2.local"
        "--tls-san=node3.local"
        "--tls-san=node4.local"
        "--tls-san=node5.local"
        "--tls-san=node6.local"
        "--tls-san=node7.local"
      ])
    );
  };

  # Ensure token directory exists
  systemd.tmpfiles.rules = [
    "d /etc/k3s 0755 root root -"
  ];

  # Firewall ports for K3s (only opened when K3s is enabled)
  networking.firewall = lib.mkIf enableK3s {
    allowedTCPPorts =
      [ 10250 ]  # Kubelet metrics (all nodes)
      ++ lib.optionals isServer [
        6443  # Kubernetes API (servers only)
        2379  # etcd client (servers only)
        2380  # etcd peer (servers only)
      ];
    allowedUDPPorts = [
      8472  # Flannel VXLAN (all nodes)
    ];
  };

  # Kubectl config for admin user (only set when K3s is enabled, servers only)
  environment.variables = lib.mkIf (enableK3s && isServer) {
    KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
  };
}
