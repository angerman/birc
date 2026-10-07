# SPDX-License-Identifier: Apache-2.0
{ writeShellScriptBin, python3 }:
writeShellScriptBin "birc-history-search" ''
  exec ${python3}/bin/python3 ${../src/launcher/search_probe_birc.py} "$@"
''
