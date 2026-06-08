{
  description = "Silly Tools, TiSslooly";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.automate-accounts = {
    url = "github:ToxicPine/automate-accounts";
    flake = false;
  };
  inputs.google-workspace-cli = {
    url = "github:googleworkspace/cli";
    flake = false;
  };

  outputs =
    { self, nixpkgs, nixpkgs-unstable, automate-accounts, google-workspace-cli, ... }:
    let
      skills = import ./skills.nix { lib = nixpkgs.lib; };

      forAllSystems =
        f:
        nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed (
          system:
          let
            pkgs = import nixpkgs {
              localSystem.system = system;
              config.allowUnfree = true;
            };
            unstablePkgs = import nixpkgs-unstable {
              localSystem.system = system;
              config.allowUnfree = true;
            };
          in
          f pkgs unstablePkgs
        );

      packagesWithSkills = [
        {
          name = "boondoggler";
          skillsPath = ./packages/boondoggler/skills;
        }
        {
          name = "offloader";
          skillsPath = ./packages/offloader/skills;
        }
        {
          name = "offloader-configurator";
          skillsPath = ./packages/offloader-configurator/skills;
        }
        {
          name = "offload";
          skillsPath = ./packages/offload/skills;
        }
        {
          name = "ghwc";
          skillsPath = ./packages/ghwc/skills;
        }
        {
          name = "ghwrc";
          skillsPath = ./packages/ghwrc/skills;
        }
        {
          name = "vusperize";
          skillsPath = ./packages/vusperize/skills;
        }
        {
          name = "nestail";
          skillsPath = ./packages/nestail/skills;
        }
        {
          name = "account-automation";
          skillsPath = automate-accounts + "/skills";
        }
        {
          name = "google-workspace";
          skillsPath = google-workspace-cli + "/skills";
        }
      ];
    in
    {
      packages = forAllSystems (
        pkgs: unstablePkgs:
        {
          boondoggler = pkgs.callPackage ./packages/boondoggler { };
          offloader = pkgs.callPackage ./packages/offloader { };
          offloader-configurator = pkgs.callPackage ./packages/offloader-configurator { };
          offloader-container = import ./packages/offloader-container/nix {
            system = pkgs.stdenv.hostPlatform.system;
          };
          offloader-transports = pkgs.callPackage ./packages/offloader-transports { };
          ghwc = pkgs.callPackage ./packages/ghwc { };
          ghwrc = pkgs.callPackage ./packages/ghwrc { };
          vusperize = pkgs.callPackage ./packages/vusperize { };
          nestail = pkgs.callPackage ./packages/nestail { };
          # poltrock = pkgs.callPackage ./packages/poltrock { };
          default = pkgs.writeShellApplication {
            name = "offloads";
            text = ''
              echo "hello from offloads"
            '';
          };
        }
        // skills.mkSkillsPackages pkgs packagesWithSkills
      );

      homeModules = skills.mkSkillsHomeModules {
        inherit self;
        packages = packagesWithSkills;
      };
    };
}
