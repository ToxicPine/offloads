{
  sources ? import ./npins,
}:
{
  lib,
  pkgs,
  ...
}:

let
  system = pkgs.stdenv.hostPlatform.system;
  hermes = import ../hermes {
    inherit pkgs;
    inherit sources;
  };
  flake-compat = import sources.flake-compat;
  offloadsFlake = (flake-compat { src = sources.offloads; }).defaultNix;
  offloads = offloadsFlake.packages.${system};
  nestail = offloads.nestail;
  openssh-container = pkgs.openssh.override {
    withFIDO = false;
    withPAM = false;
    withSecurityKey = false;
  };
  does-nothing = pkgs.runCommand "empty-bin" { } "mkdir -p $out/bin";
  util-linux-minimal = pkgs.util-linuxMinimal;
  procps-container = pkgs.procps.override {
    withSystemd = false;
  };
  alsa-lib-container = pkgs.alsa-lib.overrideAttrs (_old: {
    postInstall = "";
  });
  ffmpeg-container = pkgs.ffmpeg-headless.override {
    alsa-lib = alsa-lib-container;
    withOpenmpt = false;
    withPulse = false;
  };
  claude-code-container = pkgs.claude-code.override {
    alsa-lib = alsa-lib-container;
    procps = procps-container;
  };
  tmux-container = pkgs.tmux.override {
    withSystemd = false;
  };
  codex-container = pkgs.symlinkJoin {
    name = "codex-container";
    paths = [ pkgs.codex ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/codex \
        --prefix PATH : ${lib.makeBinPath [ procps-container ]}
    '';
  };
  opencode = import ../opencode.nix { inherit pkgs; };
in

{
  imports = [
    hermes.hmModule
  ];

  i18n.glibcLocales = pkgs.glibcLocalesUtf8;

  home = {
    stateVersion = "25.11";

    sessionPath = [
      "$HOME/.nix-profile/bin"
      "$HOME/.local/state/nix/profiles/home-manager/home-path/bin"
    ];

    sessionVariables = {
      NIX_REMOTE = "daemon";
    };

    packages = with pkgs; [
      codex-container
      claude-code-container
      opencode.package
      nestail
      offloads.ghwc
      offloads.ghwrc
      offloads.vusperize
      openssh-container
      procps-container
      curl
      git
      gh
      tmux-container
    ];

    activation.seedHermesSoul = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -n "''${DRY_RUN:-}" ]; then
        echo "Would seed default Hermes SOUL.md if absent"
      else
        install -d -m 0700 "$HOME/.hermes"
        if [ ! -e "$HOME/.hermes/SOUL.md" ]; then
          install -m 0660 ${./SOUL.md} "$HOME/.hermes/SOUL.md"
        fi
      fi
    '';

    activation.cacheHomeManagerGeneration = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      cache="file:///data/nix-cache?compression=zstd&parallel-compression=true"

      if [ -n "''${DRY_RUN:-}" ]; then
        echo "Would export Home Manager generation closure to local Nix cache: $newGenPath"
      else
        if mkdir -p /data/nix-cache; then
          touch /data/nix-cache/.copy-lock 2>/dev/null || true
          chmod 0666 /data/nix-cache/.copy-lock 2>/dev/null || true
          ${util-linux-minimal}/bin/flock /data/nix-cache/.copy-lock \
            ${pkgs.nix}/bin/nix copy --to "$cache" "$newGenPath" \
            || echo "Warning: failed to export Home Manager generation to local Nix cache" >&2
        else
          echo "Warning: failed to create local Nix cache directory" >&2
        fi
      fi
    '';
  };

  programs = {
    home-manager.enable = true;

    hermes-agent = {
      enable = true;

      packageOverrides = {
        ffmpeg = ffmpeg-container;
        openssh = openssh-container;
        wl-clipboard = does-nothing;
        xclip = does-nothing;
        dependencyGroups = [
          "cli"
          "mcp"
          "acp"
          "web"
          "messaging"
        ];
      };

      settings = {
        gateway = {
          host = "::";
          port = 8080;
        };

        model = {
          default = "gpt-5.5";
          provider = "openai-codex";
          base_url = "https://chatgpt.com/backend-api/codex";
        };

        approvals.mode = "off";
        security = {
          tirith_enabled = false;
          redact_secrets = false;
        };
        terminal.backend = "local";

        platforms.telegram.extra = { };
        platforms.webhook = {
          enabled = true;
          extra = {
            port = 8644;
          };
        };
      };
    };

    bash = {
      enable = true;
      initExtra = ''[[ "$PWD" == "/" ]] && cd'';
      shellAliases = {
        ll = "ls -la";
      };
    };

    tmux = {
      enable = true;
      package = tmux-container;
      terminal = "screen-256color";
    };
  };

  systemd.user.enable = false;
}
