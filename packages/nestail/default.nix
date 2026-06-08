{
  lib,
  stdenvNoCC,
  deno,
  makeWrapper,
}:

let
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./deno.json
      ./deno.lock
      ./src
    ];
  };

  denoDeps = stdenvNoCC.mkDerivation {
    pname = "nestail-deno-deps";
    inherit version src;

    nativeBuildInputs = [
      deno
    ];

    buildPhase = ''
      runHook preBuild

      export DENO_DIR="$TMPDIR/deno-cache"
      deno cache \
        --vendor=true \
        --config deno.json \
        --lock deno.lock \
        src/cli.ts

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      rm -f node_modules/.deno/.setup-cache.bin

      mkdir -p "$out"
      if [ -d node_modules ]; then
        cp -R node_modules "$out/"
      fi
      if [ -d vendor ]; then
        cp -R vendor "$out/"
      fi

      runHook postInstall
    '';

    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    outputHash = "sha256-phFhKX+q+BvGSgYomAdGK+uZgoT8c1BzwBj5sH+DHTM=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "nestail";
  inherit version src;

  nativeBuildInputs = [
    makeWrapper
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/share/nestail" "$out/bin"
    cp -R deno.json deno.lock src "$out/share/nestail/"
    if [ -d ${denoDeps}/node_modules ]; then
      cp -R ${denoDeps}/node_modules "$out/share/nestail/"
    fi
    if [ -d ${denoDeps}/vendor ]; then
      cp -R ${denoDeps}/vendor "$out/share/nestail/"
    fi

    makeWrapper ${deno}/bin/deno "$out/bin/nestail" \
      --add-flags "run" \
      --add-flags "--vendor=true" \
      --add-flags "--node-modules-dir=manual" \
      --add-flags "--config $out/share/nestail/deno.json" \
      --add-flags "--lock $out/share/nestail/deno.lock" \
      --add-flags "--allow-net=0.0.0.0,127.0.0.1,localhost" \
      --add-flags "--allow-env=SCRAMJET_HOST,SCRAMJET_PORT,NESTAIL_AUTH_SECRET,NESTAIL_TRUST_PROXY_HEADERS" \
      --add-flags "$out/share/nestail/src/cli.ts"

    runHook postInstall
  '';
}
