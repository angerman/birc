# SPDX-License-Identifier: Apache-2.0
{ writeShellScriptBin, python3, cacert }:
let
  python = python3.withPackages (packages: [ packages.pillow ]);
in writeShellScriptBin "birc-image" ''
  export SSL_CERT_FILE="''${SSL_CERT_FILE:-${cacert}/etc/ssl/certs/ca-bundle.crt}"
  exec ${python}/bin/python3 ${../src/media/image.py} "$@"
''
