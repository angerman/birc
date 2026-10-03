# SPDX-License-Identifier: Apache-2.0
{ lib, stdenv, bend, clang, makeWrapper, callPackage, python3, openssl, cacert
, profileBuild ? false }:

let
  media = callPackage ./media.nix {};
  upload = callPackage ./upload.nix {};
  preferences = callPackage ./preferences.nix {};
in stdenv.mkDerivation {
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

  nativeBuildInputs = [ bend clang makeWrapper ];
  buildInputs = [ openssl ];

  buildPhase = ''
    runHook preBuild
    ${lib.optionalString profileBuild ''
      birc_stage_started=$SECONDS
      printf 'birc-build stage=codegen begin\n' >&2
    ''}
    ${if profileBuild then ''
      bend src/bend/app.bend -o birc_bend.c &
      birc_codegen_pid=$!
      printf 'birc-build stage=codegen pid=%s\n' "$birc_codegen_pid" >&2
      wait "$birc_codegen_pid"
    '' else ''
      bend src/bend/app.bend -o birc_bend.c
    ''}
    ${lib.optionalString profileBuild ''
      printf 'birc-build stage=codegen elapsed_s=%s\n' "$((SECONDS - birc_stage_started))" >&2
      birc_stage_started=$SECONDS
      printf 'birc-build stage=native begin\n' >&2
    ''}
    clang -std=c11 -O2 -pthread -w -Isrc/ui -Isrc/ffi \
      -isystem ${lib.getDev openssl}/include birc_bend.c \
      -L${lib.getLib openssl}/lib -Wl,-rpath,${lib.getLib openssl}/lib \
      -lssl -lcrypto -o birc
    ${lib.optionalString profileBuild ''
      printf 'birc-build stage=native elapsed_s=%s\n' "$((SECONDS - birc_stage_started))" >&2
    ''}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/libexec
    cp birc $out/bin/birc
    wrapProgram $out/bin/birc \
      --set-default BIRC_MEDIA_HELPER "${media}/bin/birc-image" \
      --set-default BIRC_UPLOAD_HELPER "${upload}/bin/birc-upload" \
      --set-default BIRC_PREFS_HELPER "${preferences}/bin/birc-preferences" \
      --set-default SSL_CERT_FILE "${cacert}/etc/ssl/certs/ca-bundle.crt"
    cp src/launcher/keychain_birc.py $out/libexec/keychain_birc.py
    makeWrapper ${python3}/bin/python3 $out/bin/keychain-birc \
      --add-flags $out/libexec/keychain_birc.py \
      --set-default BIRC_PROGRAM "$out/bin/birc"
    runHook postInstall
  '';

  meta = {
    description = "Terminal IRC client written in Bend 2 + timui.h";
    homepage = "https://github.com/angerman/birc";
    license = lib.licenses.asl20;
    mainProgram = "birc";
  };
}
