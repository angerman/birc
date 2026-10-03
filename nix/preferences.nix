# SPDX-License-Identifier: Apache-2.0
{ writeShellScriptBin, python3 }:
writeShellScriptBin "birc-preferences" ''
  exec ${python3}/bin/python3 ${../src/launcher/preferences_birc.py} "$@"
''
