# OpenCode server package and ports, shared by the image (nix/system.nix) and
# the Home Manager config (fs/hm-base, fs/hm-user). `ports.external` is the
# public Fly port and must match the dedicated service in fly.toml.
{ pkgs }:

{
  ports = {
    internal = 4097;
    external = 8443;
  };

  package = pkgs.opencode;
}
