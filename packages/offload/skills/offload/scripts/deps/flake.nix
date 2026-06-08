{
  description = "Local dependencies for the offload skill";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.offloads = {
    url = "github:ToxicPine/offloads";
    flake = false;
  };

  outputs =
    { self, nixpkgs, offloads, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);

      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          offloader-transports = pkgs.callPackage "${offloads.outPath}/packages/offloader-transports" { };
        in
        {
          inherit offloader-transports;
          default = offloader-transports;
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          packages = selfPackages: [
            pkgs.bashInteractive
            pkgs.coreutils
            pkgs.curl
            pkgs.flyctl
            pkgs.git
            pkgs.jq
            pkgs.openssh
            pkgs.openssl
            selfPackages.offloader-transports
          ];
        in
        {
          default = pkgs.mkShell {
            packages = packages self.packages.${system};
          };
        }
      );
    };
}
