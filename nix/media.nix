# SPDX-License-Identifier: Apache-2.0
{ writeShellScriptBin, python3 }:
let
  python = python3.withPackages (packages: [ packages.pillow ]);
in writeShellScriptBin "birc-image" ''
  exec ${python}/bin/python3 ${../src/media/image.py} "$@"
''
