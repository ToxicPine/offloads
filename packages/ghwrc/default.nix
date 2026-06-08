{ pkgs, ... }:

pkgs.writeShellApplication {
  name = "ghwrc";
  runtimeInputs = with pkgs; [
    coreutils
    gh
    git
  ];
  text = builtins.readFile ./ghwrc.sh;
}
