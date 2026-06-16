{ pkgs, ... }:

let
  # Pinned Hermes CLI, reusing the offloader-container's npins-pinned
  # hermes-agent package (its `sources` argument defaults to that pin). Only
  # `pkgs` is threaded in, so this needs no extra callPackage params and no
  # flake or container edits.
  hermes = import ../offloader-container/fs/hermes/package.nix { inherit pkgs; };

  denoDeps = pkgs.stdenvNoCC.mkDerivation {
    pname = "offloader-configurator-deno-deps";
    version = "0.1.0";
    src = ./.;

    nativeBuildInputs = [
      pkgs.deno
    ];

    buildPhase = ''
      runHook preBuild

      export DENO_DIR="$TMPDIR/deno-cache"
      deno cache \
        --vendor=true \
        --config deno.json \
        --lock deno.lock \
        src/main.ts

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      rm -f node_modules/.deno/.setup-cache.bin

      mkdir -p "$out"
      cp -R node_modules "$out/"

      runHook postInstall
    '';

    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    outputHash = "sha256-83LRLx0ESnL5CZ7Z6eRBpcXk6hyILs2qVEFLVoPFtdU=";
  };
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "offloader-configurator";
  version = "0.1.0";
  src = ./.;

  nativeBuildInputs = [
    pkgs.makeWrapper
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/share/offloader-configurator" "$out/bin"
    cp -R README.md deno.json deno.lock src "$out/share/offloader-configurator/"
    cp -R ${denoDeps}/node_modules "$out/share/offloader-configurator/"

    makeWrapper ${pkgs.deno}/bin/deno "$out/bin/offloader-configurator" \
      --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.claude-code pkgs.opencode hermes ]} \
      --add-flags "run" \
      --add-flags "--vendor=true" \
      --add-flags "--node-modules-dir=manual" \
      --add-flags "--config $out/share/offloader-configurator/deno.json" \
      --add-flags "--lock $out/share/offloader-configurator/deno.lock" \
      --add-flags "--allow-run" \
      --add-flags "--allow-read" \
      --add-flags "--allow-write" \
      --add-flags "--allow-env=OFFLOADER_CONFIG_TRANSPORT,HOME" \
      --add-flags "$out/share/offloader-configurator/src/main.ts"

    runHook postInstall
  '';
}
