# SPDX-License-Identifier: Apache-2.0
{ lib, stdenv, bend, clang, makeWrapper, openssl, cacert
, libnotify ? null
, profileBuild ? false }:

let
  notifyHelper =
    if stdenv.hostPlatform.isDarwin then "/usr/bin/osascript"
    else if libnotify != null then "${libnotify}/bin/notify-send"
    else throw "birc Linux package requires libnotify";
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
    # Hermetic build: keep Bun caches in the sandbox TMPDIR, never $HOME.
    export BIRC_BUN_TMPDIR_CACHE=1
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
    clang -std=c11 -O2 -Wall -Wextra -Werror src/ffi/keychain_birc.c -o keychain-birc
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
      --set-default BIRC_MEDIA_HELPER native \
      --set-default BIRC_CARDS_HELPER native \
      --set-default BIRC_UPLOAD_HELPER native \
      --set-default BIRC_PREFS_HELPER native \
      --set-default BIRC_SEARCH_HELPER native \
      --set-default BIRC_NOTIFY_HELPER "${notifyHelper}" \
      --set-default SSL_CERT_FILE "${cacert}/etc/ssl/certs/ca-bundle.crt"
    makeWrapper $PWD/keychain-birc $out/bin/keychain-birc \
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
