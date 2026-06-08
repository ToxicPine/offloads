{ pkgs, ... }:

pkgs.writeShellApplication {
  name = "offloader";
  runtimeInputs = with pkgs; [
    coreutils
    git
    gnugrep
    util-linux
  ];
  text = builtins.readFile ./offloader.sh;
}
