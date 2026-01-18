{ config, lib, pkgs, ... }:

let
  cfg = config.services.circuit-zoo;
in {
  options.services.circuit-zoo = {
    enable = lib.mkEnableOption "Circuit Zoo distributed search worker";

    databaseUrl = lib.mkOption {
      type = lib.types.str;
      default = "host=192.168.4.25 user=samuel dbname=samuel port=5432";
      description = "PostgreSQL connection string";
    };

    n = lib.mkOption {
      type = lib.types.int;
      default = 5;
      description = "Number of input variables";
    };

    maxSize = lib.mkOption {
      type = lib.types.int;
      default = 14;
      description = "Maximum circuit size to search";
    };

    binaryPath = lib.mkOption {
      type = lib.types.path;
      default = /opt/circuit_zoo;
      description = "Path to the circuit_zoo binary";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.circuit-zoo = {
      description = "Circuit Zoo distributed search worker";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.binaryPath} -n ${toString cfg.n} -s ${toString cfg.maxSize} -d '${cfg.databaseUrl}' -w ${config.networking.hostName}";
        Restart = "always";
        RestartSec = "10s";
        # Run as unprivileged user
        DynamicUser = true;
        # Resource limits to prevent OOM
        MemoryMax = "3G";
        CPUQuota = "350%";  # 3.5 cores
      };
    };
  };
}
