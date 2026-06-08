{ pkgs, ... }:

# offloader transport adapters, shipped together so they land on PATH at once.
let
  openssh-client = pkgs.openssh.override {
    withFIDO = false;
    withPAM = false;
    withSecurityKey = false;
  };

  # Client-only tailscale: build just cmd/tailscale, dropping the tailscaled
  # daemon, its wrapped deps (iproute2/iptables/shadow/procps), and the systemd
  # unit — none of which `tailscale ssh` needs.
  tailscale-lite = pkgs.tailscale.overrideAttrs (_: {
    pname = "tailscale-lite";
    subPackages = [ "cmd/tailscale" ];
    outputs = [ "out" ];
    postInstall = "";
  });

  mkAdapter = name: runtimeInputs:
    pkgs.writeShellApplication {
      inherit name runtimeInputs;
      text = builtins.readFile (./. + "/${name}.sh");
    };
in
pkgs.symlinkJoin {
  name = "offloader-transports";
  paths = [
    (mkAdapter "offloader-ssh" [ openssh-client ])
    # tailscale ssh execs the system ssh, so openssh is needed too.
    (mkAdapter "offloader-tailscale" [ tailscale-lite openssh-client ])
    (mkAdapter "offloader-fly" [ pkgs.coreutils pkgs.flyctl ])
  ];
}
