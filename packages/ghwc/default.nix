{ pkgs, ... }:

pkgs.writeShellApplication {
  name = "ghwc";
  runtimeInputs = with pkgs; [
    coreutils
    gh
    git
  ];
  text = builtins.readFile ./ghwc.sh;
}
