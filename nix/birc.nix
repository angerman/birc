# SPDX-License-Identifier: Apache-2.0
{ lib, stdenv, bend, clang }:

stdenv.mkDerivation {
  pname = "birc";
  version = "0.1.0";

  src = lib.cleanSourceWith {
    src = ./..;
    filter = path: type:
      let
        base = baseNameOf path;
      in
        base == "src" ||
        lib.hasPrefix (toString ./../src) (toString path);
  };

  nativeBuildInputs = [ bend clang ];

  buildPhase = ''
    runHook preBuild
    export HOME="$TMPDIR"
    bend src/bend/app.bend -o birc_bend.c
    clang -std=c11 -O2 -pthread -w -Isrc/ui -Isrc/ffi birc_bend.c -o birc
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp birc $out/bin/birc
    runHook postInstall
  '';

  meta = {
    description = "Formally verified terminal IRC client written in Bend 2 + timui.h";
    homepage = "https://github.com/angerman/birc";
    license = lib.licenses.asl20;
    mainProgram = "birc";
  };
}
