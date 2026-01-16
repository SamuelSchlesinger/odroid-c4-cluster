# Monitoring stack for node1 (Prometheus + Grafana)
{ config, pkgs, ... }:

{
  # Prometheus - metrics aggregation
  services.prometheus = {
    enable = true;
    port = 9090;

    scrapeConfigs = [
      {
        job_name = "cluster";
        static_configs = [{
          targets = [
            "node1.local:9100"
            "node2.local:9100"
            "node3.local:9100"
            "node4.local:9100"
            "node5.local:9100"
            "node6.local:9100"
            "node7.local:9100"
          ];
        }];
      }
    ];
  };

  # Grafana - dashboards
  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "0.0.0.0";
        http_port = 3000;
      };
      security = {
        admin_user = "admin";
        admin_password = "admin";  # Change on first login
      };
    };

    # Auto-provision Prometheus data source
    provision = {
      datasources.settings.datasources = [{
        name = "Prometheus";
        type = "prometheus";
        url = "http://localhost:9090";
        isDefault = true;
      }];
    };
  };

  # Open firewall ports for Prometheus and Grafana
  networking.firewall.allowedTCPPorts = [ 9090 3000 ];
}
