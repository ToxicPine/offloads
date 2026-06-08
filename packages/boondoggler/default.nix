{ pkgs, ... }:

pkgs.writeShellApplication {
  name = "boondoggler";
  runtimeInputs = with pkgs; [
    coreutils
    git
    gnused
    jq
    codex
  ];
  text = builtins.readFile ./boondoggler.sh;
}
