{ config, lib, pkgs, ... }:

let
  cfg = config.services.circuit-zoo;

  # Build circuit_zoo from source
  circuit-zoo-bin = pkgs.rustPlatform.buildRustPackage {
    pname = "circuit-zoo";
    version = "0.1.0";
    src = ./circuit-zoo;
    cargoLock.lockFile = ./circuit-zoo/Cargo.lock;
  };
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
  };

  config = lib.mkIf cfg.enable {
    systemd.services.circuit-zoo = {
      description = "Circuit Zoo distributed search worker";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${circuit-zoo-bin}/bin/circuit_zoo -n ${toString cfg.n} -s ${toString cfg.maxSize} -d '${cfg.databaseUrl}' -w ${config.networking.hostName}";
        Restart = "always";
        RestartSec = "10s";
        DynamicUser = true;
        MemoryMax = "3G";
        CPUQuota = "350%";
      };
    };
  };
}
