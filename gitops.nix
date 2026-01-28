# GitOps auto-deploy: node1 builds and pushes to all nodes
{ config, pkgs, lib, ... }:

let
  hostname = config.networking.hostName;
  isLeader = hostname == "node1";
  flakeUrl = "git+ssh://git@github.com/SamuelSchlesinger/odroid-c4-cluster";
  revisionFile = "/var/lib/auto-deploy/revision";
  allNodes = [ "node1" "node2" "node3" "node4" "node5" "node6" "node7" ];
  otherNodes = [ "node2" "node3" "node4" "node5" "node6" "node7" ];

  # Leader script: builds all configs and pushes to all nodes
  leaderDeployScript = pkgs.writeShellScript "auto-deploy-leader" ''
    set -euo pipefail

    LOCK_FILE="/var/run/auto-deploy.lock"
    REVISION_FILE="${revisionFile}"
    LOG_PREFIX="[auto-deploy]"
    FLAKE_URL="${flakeUrl}"
    export GIT_SSH_COMMAND="${pkgs.openssh}/bin/ssh -i /root/.ssh/id_ed25519 -o StrictHostKeyChecking=accept-new"
    export NIX_SSHOPTS="-i /root/.ssh/id_ed25519 -o StrictHostKeyChecking=accept-new"

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

    # Get current deployed revision
    CURRENT_REV=$(cat "$REVISION_FILE" 2>/dev/null || echo "unknown")
    log "Current revision: $CURRENT_REV"

    # Fetch latest revision from GitHub
    LATEST_REV=$(${pkgs.git}/bin/git ls-remote "$FLAKE_URL" refs/heads/main 2>/dev/null | cut -f1 || echo "fetch-failed")

    if [ "$LATEST_REV" = "fetch-failed" ] || [ -z "$LATEST_REV" ]; then
      log "Failed to fetch latest revision from GitHub"
      exit 1
    fi

    log "Latest revision: $LATEST_REV"

    if [ "$CURRENT_REV" = "$LATEST_REV" ]; then
      log "Already up to date"
      exit 0
    fi

    log "New version detected! Building all configurations..."

    # Build all 7 configurations and store paths
    declare -A PATHS
    BUILD_FAILED=0

    # Force local builds - distributed builds cause outputs to stay on remote machines,
    # breaking nix copy. Use empty builders list.
    NO_BUILDERS=""

    for node in ${lib.concatStringsSep " " allNodes}; do
      log "Building $node..."
      if PATH_OUT=$(${pkgs.nix}/bin/nix build "$FLAKE_URL#nixosConfigurations.$node.config.system.build.toplevel" \
          --no-link --print-out-paths --refresh --builders "$NO_BUILDERS" 2>&1); then
        PATHS[$node]="$PATH_OUT"
        log "Built $node: $PATH_OUT"
      else
        log "ERROR: Failed to build $node"
        log "$PATH_OUT"
        BUILD_FAILED=1
        break
      fi
    done

    if [ "$BUILD_FAILED" -eq 1 ]; then
      log "Build failed, aborting deployment"
      exit 1
    fi

    log "All builds successful. Copying to remote nodes..."

    # Copy to nodes 2-7 (with retries)
    COPY_FAILED=0
    for node in ${lib.concatStringsSep " " otherNodes}; do
      log "Copying to $node..."
      RETRIES=3
      SUCCESS=0
      for i in $(seq 1 $RETRIES); do
        if ${pkgs.nix}/bin/nix copy --to "ssh://root@$node.local" "''${PATHS[$node]}" 2>&1; then
          log "Copied to $node successfully"
          SUCCESS=1
          break
        else
          log "Copy to $node failed (attempt $i/$RETRIES)"
          sleep 5
        fi
      done
      if [ "$SUCCESS" -eq 0 ]; then
        log "ERROR: Failed to copy to $node after $RETRIES attempts"
        COPY_FAILED=1
        break
      fi
    done

    if [ "$COPY_FAILED" -eq 1 ]; then
      log "Copy failed, aborting deployment (no nodes activated)"
      exit 1
    fi

    log "All copies successful. Activating on all nodes..."

    # Activate on all nodes, tracking failures
    ACTIVATION_FAILURES=""

    # Activate on node1 (self) first
    log "Activating on node1 (self)..."
    if ${pkgs.nix}/bin/nix-env -p /nix/var/nix/profiles/system --set "''${PATHS[node1]}" && \
       "''${PATHS[node1]}/bin/switch-to-configuration" switch; then
      log "Activated on node1 successfully"
      echo "$LATEST_REV" > "$REVISION_FILE"
    else
      log "ERROR: Activation failed on node1"
      ACTIVATION_FAILURES="node1 $ACTIVATION_FAILURES"
    fi

    # Activate on remote nodes
    for node in ${lib.concatStringsSep " " otherNodes}; do
      log "Activating on $node..."
      NODE_PATH="''${PATHS[$node]}"
      if ${pkgs.openssh}/bin/ssh -i /root/.ssh/id_ed25519 -o StrictHostKeyChecking=accept-new \
          "root@$node.local" "
            ${pkgs.nix}/bin/nix-env -p /nix/var/nix/profiles/system --set '$NODE_PATH' && \
            '$NODE_PATH/bin/switch-to-configuration' switch && \
            echo '$LATEST_REV' > '$REVISION_FILE'
          " 2>&1; then
        log "Activated on $node successfully"
      else
        log "ERROR: Activation failed on $node"
        ACTIVATION_FAILURES="$node $ACTIVATION_FAILURES"
      fi
    done

    if [ -n "$ACTIVATION_FAILURES" ]; then
      log "WARNING: Activation failed on: $ACTIVATION_FAILURES"
      log "Deployment partially complete"
      exit 1
    fi

    log "Deployment complete! All nodes updated to $LATEST_REV"
  '';
in
{
  # Ensure the auto-deploy state directory exists (all nodes)
  systemd.tmpfiles.rules = [
    "d /var/lib/auto-deploy 0755 root root -"
  ];

  # Auto-deploy service - only runs on leader (node1)
  systemd.services.auto-deploy = lib.mkIf isLeader {
    description = "GitOps auto-deploy from GitHub (leader)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    # Dependencies for building and deploying
    path = [ pkgs.git pkgs.openssh pkgs.nix ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = leaderDeployScript;

      # Run as root (needed for nixos-rebuild and SSH)
      User = "root";

      # Environment for SSH and Nix
      Environment = [
        "HOME=/root"
        "SSH_AUTH_SOCK="
      ];

      # Logging
      StandardOutput = "journal";
      StandardError = "journal";

      # Longer timeout for building all nodes
      TimeoutStartSec = "30min";
    };

    # Rate limit: allow frequent starts since timer runs every 15s
    unitConfig = {
      StartLimitIntervalSec = 300;
      StartLimitBurst = 30;
    };
  };

  # Timer to run auto-deploy - only on leader (node1)
  systemd.timers.auto-deploy = lib.mkIf isLeader {
    description = "GitOps auto-deploy timer";
    wantedBy = [ "timers.target" ];

    timerConfig = {
      OnBootSec = "1min";           # First run 1 minute after boot
      OnUnitActiveSec = "15min";    # Then every 15 minutes
      Persistent = true;            # Run immediately if missed
    };
  };
}
