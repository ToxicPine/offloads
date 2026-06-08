{
  description = "Scramjet local route proxy";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      packages.${system} = {
        nestail = pkgs.callPackage ./default.nix { };

        default = self.packages.${system}.nestail;
      };

      apps.${system}.default = {
        type = "app";
        program = "${self.packages.${system}.default}/bin/nestail";
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          pkgs.deno
        ];
      };
    };
}
