{ lib }:

let
  skillNames =
    skillsPath:
    builtins.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir skillsPath));

  mkSkillsPackage =
    pkgs: name: skillsPath:
    pkgs.runCommandLocal "${name}-skills" { } ''
      mkdir -p "$out"
      cp -R ${skillsPath}/. "$out/"
    '';

  mkSkillsHomeModule =
    {
      self,
      packageName,
      skillsPath,
      skillsPackageName ? "${packageName}-skills",
      targetRoots ? [
        ".cursor/skills"
        ".agents/skills"
        ".claude/skills"
        ".hermes/skills"
      ],
    }:
    let
      names = skillNames skillsPath;
    in
    { pkgs, ... }:
    let
      system = pkgs.stdenv.hostPlatform.system;
    in
    {
      home.file = builtins.listToAttrs (
        lib.flatten (
          map (
            targetRoot:
            map (skillName: {
              name = "${targetRoot}/${skillName}";
              value.source = "${self.packages.${system}.${skillsPackageName}}/${skillName}";
            }) names
          ) targetRoots
        )
      );
    };

  mkSkillsPackages =
    pkgs: packages:
    builtins.listToAttrs (
      map (package: {
        name = "${package.name}-skills";
        value = mkSkillsPackage pkgs package.name package.skillsPath;
      }) packages
    );

  mkSkillsHomeModules =
    { self, packages }:
    builtins.listToAttrs (
      map (package: {
        name = "${package.name}-skills";
        value = mkSkillsHomeModule {
          inherit self;
          packageName = package.name;
          skillsPath = package.skillsPath;
        };
      }) packages
    );
in
{
  inherit
    mkSkillsHomeModule
    mkSkillsHomeModules
    mkSkillsPackage
    mkSkillsPackages
    skillNames
    ;
}
