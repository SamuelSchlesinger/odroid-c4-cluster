# GitOps auto-deploy: nodes automatically deploy when GitHub repo changes
{ config, pkgs, lib, ... }:

let
  hostname = config.networking.hostName;
  flakeUrl = "git+ssh://git@github.com/SamuelSchlesinger/odroid-c4-cluster";

  # Script to check for updates and deploy
  autoDeployScript = pkgs.writeShellScript "auto-deploy" ''
    set -euo pipefail

    LOCK_FILE="/var/run/auto-deploy.lock"
    LOG_PREFIX="[auto-deploy]"

    log() {
      echo "$LOG_PREFIX $1"
    }

    # Prevent concurrent runs
    if [ -f "$LOCK_FILE" ]; then
      pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
      if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        log "Another deployment is running (PID $pid), skipping"
        exit 0
      fi
    fi
    echo $$ > "$LOCK_FILE"
    trap "rm -f $LOCK_FILE" EXIT

    log "Checking for updates..."

    # Get current system's flake revision
    CURRENT_REV=$(${pkgs.coreutils}/bin/cat /run/current-system/flake-revision 2>/dev/null || echo "unknown")
    log "Current revision: $CURRENT_REV"

    # Fetch latest revision from GitHub (using root's SSH key)
    LATEST_REV=$(${pkgs.git}/bin/git ls-remote ${flakeUrl} refs/heads/main 2>/dev/null | ${pkgs.coreutils}/bin/cut -f1 || echo "fetch-failed")

    if [ "$LATEST_REV" = "fetch-failed" ] || [ -z "$LATEST_REV" ]; then
      log "Failed to fetch latest revision from GitHub"
      exit 1
    fi

    log "Latest revision: $LATEST_REV"

    if [ "$CURRENT_REV" = "$LATEST_REV" ]; then
      log "Already up to date"
      exit 0
    fi

    log "New version detected! Deploying..."

    # Run nixos-rebuild switch
    if ${pkgs.nixos-rebuild}/bin/nixos-rebuild switch \
      --flake "${flakeUrl}#${hostname}" \
      --refresh \
      --option accept-flake-config true; then
      log "Deployment successful!"

      # Record the deployed revision
      echo "$LATEST_REV" > /run/current-system/flake-revision
    else
      log "Deployment FAILED!"
      exit 1
    fi
  '';
in
{
  # Store the current flake revision on deployment
  system.activationScripts.recordFlakeRevision = ''
    if [ -n "''${FLAKE_REV:-}" ]; then
      echo "$FLAKE_REV" > /run/current-system/flake-revision
    fi
  '';

  # Auto-deploy service
  systemd.services.auto-deploy = {
    description = "GitOps auto-deploy from GitHub";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = autoDeployScript;

      # Run as root (needed for nixos-rebuild)
      User = "root";

      # Use root's SSH key for GitHub access
      Environment = [
        "HOME=/root"
        "SSH_AUTH_SOCK="
      ];

      # Logging
      StandardOutput = "journal";
      StandardError = "journal";
    };

    # Don't fail the system if this fails
    unitConfig = {
      StartLimitIntervalSec = 300;
      StartLimitBurst = 3;
    };
  };

  # Timer to run auto-deploy every 5 minutes
  systemd.timers.auto-deploy = {
    description = "GitOps auto-deploy timer";
    wantedBy = [ "timers.target" ];

    timerConfig = {
      OnBootSec = "2min";           # First run 2 minutes after boot
      OnUnitActiveSec = "5min";     # Then every 5 minutes
      RandomizedDelaySec = "30s";   # Stagger across nodes to avoid thundering herd
      Persistent = true;            # Run immediately if missed (e.g., system was off)
    };
  };
}
