# OpenCode server package and ports, shared by the image (nix/system.nix) and
# the Home Manager config (fs/hm-base, fs/hm-user). `ports.external` is the
# public Fly port and must match the dedicated service in fly.toml.
{ pkgs }:

let
  procps-container = pkgs.procps.override { withSystemd = false; };
in
{
  ports = {
    internal = 4097;
    external = 8443;
  };

  # opencode wrapped with a systemd-free procps so its subprocess management
  # works inside the container.
  package = pkgs.symlinkJoin {
    name = "opencode-container";
    paths = [ pkgs.opencode ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/opencode \
        --prefix PATH : ${pkgs.lib.makeBinPath [ procps-container ]}
    '';
  };
}
