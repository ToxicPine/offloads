{
  lib,
  pkgs,
  ...
}:

let
  sources = import ../../hm-base/npins;
  flake-compat = import sources.flake-compat;
  offloads = (flake-compat { src = sources.offloads; }).defaultNix;
  procps-container = pkgs.procps.override {
    withSystemd = false;
  };
  alsa-lib-container = pkgs.alsa-lib.overrideAttrs (_old: {
    postInstall = "";
  });
  codex-container = pkgs.symlinkJoin {
    name = "codex-container";
    paths = [ pkgs.codex ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/codex \
        --prefix PATH : ${lib.makeBinPath [ procps-container ]}
    '';
  };
  claude-code-container = pkgs.claude-code.override {
    alsa-lib = alsa-lib-container;
    procps = procps-container;
  };
  opencode-container = pkgs.symlinkJoin {
    name = "opencode-container";
    paths = [ pkgs.opencode ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/opencode \
        --prefix PATH : ${lib.makeBinPath [ procps-container ]}
    '';
  };
  # Internal port the OpenCode HTTP server binds to. Kept distinct from the
  # Nestail entrypoint port (4096) so OpenCode can be exposed on its own Fly
  # service. Overridable at runtime via OPENCODE_SERVER_PORT.
  opencodeDefaultPort = 4097;
  remote-control-supervisor = pkgs.writeShellApplication {
    name = "remote-control-supervisor";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      set -u

      name=
      stable_after=300
      initial_backoff=5
      max_backoff=300
      max_attempts=8

      while [ "$#" -gt 0 ]; do
        case "$1" in
          --name)
            name="$2"
            shift 2
            ;;
          --stable-after)
            stable_after="$2"
            shift 2
            ;;
          --initial-backoff)
            initial_backoff="$2"
            shift 2
            ;;
          --max-backoff)
            max_backoff="$2"
            shift 2
            ;;
          --max-attempts)
            max_attempts="$2"
            shift 2
            ;;
          --)
            shift
            break
            ;;
          *)
            echo "remote-control-supervisor: unknown argument: $1" >&2
            exit 2
            ;;
        esac
      done

      if [ -z "$name" ] || [ "$#" -eq 0 ]; then
        echo "remote-control-supervisor: usage: --name NAME -- COMMAND..." >&2
        exit 2
      fi

      state_dir="''${REMOTE_CONTROL_STATE_DIR:-$HOME/.local/state/$name-remote-control}"
      run_log="$state_dir/run.log"
      mkdir -p "$state_dir"

      log() {
        printf '%s %s\n' "$(date -Is)" "$*"
      }

      child_pid=
      terminate() {
        if [ -n "$child_pid" ] && kill -0 "$child_pid" 2>/dev/null; then
          kill "$child_pid" 2>/dev/null || true
          wait "$child_pid" 2>/dev/null || true
        fi
        exit 0
      }
      trap terminate INT TERM

      attempt=0
      backoff="$initial_backoff"

      while true; do
        started_at="$(date +%s)"
        log "starting $name remote control"

        "$@" >>"$run_log" 2>&1 &
        child_pid="$!"
        if wait "$child_pid"; then
          status=0
        else
          status="$?"
        fi
        child_pid=

        ended_at="$(date +%s)"
        ran_for=$((ended_at - started_at))

        if [ "$ran_for" -ge "$stable_after" ]; then
          log "$name ran for ''${ran_for}s; resetting restart backoff"
          attempt=0
          backoff="$initial_backoff"
        fi

        if [ "$status" -eq 0 ]; then
          log "$name exited successfully after ''${ran_for}s; restarting in ''${stable_after}s"
          attempt=0
          backoff="$initial_backoff"
          sleep "$stable_after"
          continue
        fi

        attempt=$((attempt + 1))
        if [ "$attempt" -ge "$max_attempts" ]; then
          log "$name exited with status $status after ''${ran_for}s; giving up after $attempt/$max_attempts attempts"
          exit "$status"
        fi

        log "$name exited with status $status after ''${ran_for}s; restart attempt $attempt/$max_attempts in ''${backoff}s"
        sleep "$backoff"
        backoff=$((backoff * 2))
        if [ "$backoff" -gt "$max_backoff" ]; then
          backoff="$max_backoff"
        fi
      done
    '';
  };
  remote-control-launcher = pkgs.writeShellApplication {
    name = "remote-control-launcher";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      set -u

      name=

      while [ "$#" -gt 0 ]; do
        case "$1" in
          --name)
            name="$2"
            shift 2
            ;;
          --)
            shift
            break
            ;;
          *)
            echo "remote-control-launcher: unknown argument: $1" >&2
            exit 2
            ;;
        esac
      done

      if [ -z "$name" ] || [ "$#" -eq 0 ]; then
        echo "remote-control-launcher: usage: --name NAME -- COMMAND..." >&2
        exit 2
      fi

      state_dir="$HOME/.local/state/$name-remote-control"
      supervisor_log="$state_dir/supervisor.log"
      pid_file="$state_dir/supervisor.pid"

      if ! mkdir -p "$state_dir"; then
        echo "remote-control-launcher: failed to create $state_dir" >&2
        exit 1
      fi

      if [ -r "$pid_file" ]; then
        old_pid="$(cat "$pid_file" 2>/dev/null || true)"
        if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
          kill "$old_pid" 2>/dev/null || true
          sleep 1
          if kill -0 "$old_pid" 2>/dev/null; then
            kill -KILL "$old_pid" 2>/dev/null || true
          fi
        fi
      fi

      (
        cd "$HOME" || exit 1
        export REMOTE_CONTROL_STATE_DIR="$state_dir"
        exec ${remote-control-supervisor}/bin/remote-control-supervisor \
          --name "$name" \
          --stable-after 300 \
          --initial-backoff 5 \
          --max-backoff 300 \
          --max-attempts 8 \
          -- "$@"
      ) >>"$supervisor_log" 2>&1 &

      supervisor_pid="$!"
      if ! echo "$supervisor_pid" >"$pid_file"; then
        echo "remote-control-launcher: failed to write $pid_file" >&2
        kill "$supervisor_pid" 2>/dev/null || true
        exit 1
      fi

      exit 0
    '';
  };
in
{
  imports = [
    (import ../../hm-base { })
    offloads.homeModules."boondoggler-skills"
    offloads.homeModules."ghwc-skills"
    offloads.homeModules."ghwrc-skills"
    offloads.homeModules."vusperize-skills"
    offloads.homeModules."nestail-skills"
    ./managed.nix
  ];

  home.file = {
    ".codex/packages/standalone/current/codex" = {
      source = "${codex-container}/bin/codex";
      force = true;
    };
  };

  home.activation.startCodexRemoteControl = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    [ -n "''${DRY_RUN:-}" ] && exit 0

    if ! ${remote-control-launcher}/bin/remote-control-launcher \
      --name codex \
      -- \
      ${codex-container}/bin/codex remote-control start
    then
      echo "Warning: failed to launch Codex remote control supervisor" >&2
    fi

    true
  '';

  home.activation.startClaudeRemoteControl = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    [ -n "''${DRY_RUN:-}" ] && exit 0

    if ! ${remote-control-launcher}/bin/remote-control-launcher \
      --name claude \
      -- \
      ${claude-code-container}/bin/claude remote-control --permission-mode bypassPermissions
    then
      echo "Warning: failed to launch Claude remote control supervisor" >&2
    fi

    true
  '';

  # OpenCode HTTP server (https://opencode.ai/docs/server/), supervised exactly
  # like the Codex/Claude remote controls above. It only boots when
  # OPENCODE_SERVER_PASSWORD is present in the environment: OpenCode reads that
  # variable to enable HTTP basic auth (username defaults to "opencode", or set
  # OPENCODE_SERVER_USERNAME). Refusing to start without it avoids ever exposing
  # an unauthenticated server. The password is consumed by the `opencode serve`
  # process straight from the inherited environment, never passed on the CLI.
  #
  # CORS: the server sits behind the Fly TLS proxy and is reached from a browser
  # at the public hostname (HOSTNAME is set to `<app>.fly.dev` during Fly
  # provisioning), so that origin is allowlisted for cross-origin browser
  # clients. Extra origins (e.g. a non-standard external port) can be added via
  # OPENCODE_SERVER_CORS as a comma-separated list.
  home.activation.startOpencodeServer = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    if [ -z "''${DRY_RUN:-}" ]; then
      if [ -n "''${OPENCODE_SERVER_PASSWORD:-}" ]; then
        opencode_port="''${OPENCODE_SERVER_PORT:-${toString opencodeDefaultPort}}"

        cors_args=()
        if [ -n "''${HOSTNAME:-}" ]; then
          cors_args+=(--cors "https://''${HOSTNAME}" --cors "http://''${HOSTNAME}")
        fi
        if [ -n "''${OPENCODE_SERVER_CORS:-}" ]; then
          IFS=',' read -ra extra_cors <<<"''${OPENCODE_SERVER_CORS}"
          for origin in "''${extra_cors[@]}"; do
            # trim surrounding whitespace
            origin="''${origin#"''${origin%%[![:space:]]*}"}"
            origin="''${origin%"''${origin##*[![:space:]]}"}"
            [ -n "$origin" ] && cors_args+=(--cors "$origin")
          done
        fi

        if ! ${remote-control-launcher}/bin/remote-control-launcher \
          --name opencode \
          -- \
          ${opencode-container}/bin/opencode serve \
          --hostname 0.0.0.0 \
          --port "$opencode_port" \
          "''${cors_args[@]}"
        then
          echo "Warning: failed to launch OpenCode server supervisor" >&2
        fi
      else
        echo "OPENCODE_SERVER_PASSWORD not set; skipping OpenCode server launch" >&2
      fi
    fi

    true
  '';
}
