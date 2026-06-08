{ pkgs, ... }:

pkgs.writeShellApplication {
  name = "vusperize";
  runtimeInputs = with pkgs; [
    coreutils
    jq
  ];
  text = builtins.readFile ./vusperize.sh;
}
