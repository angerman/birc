# SPDX-License-Identifier: Apache-2.0
{ writeShellScriptBin, python3, cacert, runCommand }:
let
  python = python3.withPackages (packages: [ packages.pillow ]);
  # cards.py imports its sibling image.py by path, so both must land in one
  # directory; referencing cards.py alone orphans it in the store. image.py in
  # turn loads the shared cache helper the same way, so _cache.py must be a
  # sibling too or birc-cards fails at import.
  helpers = runCommand "birc-cards-helpers" { } ''
    mkdir -p $out
    cp ${../src/media/cards.py} $out/cards.py
    cp ${../src/media/image.py} $out/image.py
    cp ${../src/media/_cache.py} $out/_cache.py
  '';
in writeShellScriptBin "birc-cards" ''
  export SSL_CERT_FILE="''${SSL_CERT_FILE:-${cacert}/etc/ssl/certs/ca-bundle.crt}"
  export BIRC_CACHE_PY="''${BIRC_CACHE_PY:-${helpers}/_cache.py}"
  exec ${python}/bin/python3 ${helpers}/cards.py "$@"
''
