# SPDX-License-Identifier: Apache-2.0
{ writeShellScriptBin, python3 }:
writeShellScriptBin "birc-preferences" ''
  # preferences_birc.py is stored alone; point it at the shared helper.
  export BIRC_CACHE_PY="''${BIRC_CACHE_PY:-${../src/media/_cache.py}}"
  exec ${python3}/bin/python3 ${../src/launcher/preferences_birc.py} "$@"
''
