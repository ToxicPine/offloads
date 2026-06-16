# OpenCode server ports, shared by the image (nix/system.nix) and the Home
# Manager activation (fs/hm-user/user/home.nix). `external` is the public Fly
# port and must match the dedicated service in fly.toml.
{
  internal = 4097;
  external = 8443;
}
