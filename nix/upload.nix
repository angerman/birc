# SPDX-License-Identifier: Apache-2.0
{ writeShellScriptBin, python3, cacert }:
writeShellScriptBin "birc-upload" ''
  export SSL_CERT_FILE="''${SSL_CERT_FILE:-${cacert}/etc/ssl/certs/ca-bundle.crt}"
  # upload.py is stored alone; point it at the shared helper.
  export BIRC_CACHE_PY="''${BIRC_CACHE_PY:-${../src/media/_cache.py}}"
  exec ${python3}/bin/python3 ${../src/media/upload.py} "$@"
''
