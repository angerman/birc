# SPDX-License-Identifier: Apache-2.0
{ writeShellScriptBin, python3, cacert }:
let
  python = python3.withPackages (packages: [ packages.pillow ]);
in writeShellScriptBin "birc-image" ''
  export SSL_CERT_FILE="''${SSL_CERT_FILE:-${cacert}/etc/ssl/certs/ca-bundle.crt}"
  # image.py is stored alone; the sibling helper is not beside that path.
  export BIRC_CACHE_PY="''${BIRC_CACHE_PY:-${../src/media/_cache.py}}"
  exec ${python}/bin/python3 ${../src/media/image.py} "$@"
''
