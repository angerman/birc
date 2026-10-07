# SPDX-License-Identifier: Apache-2.0
# The birc-notify wrapper always ships its backend explicitly. Linux exports
# the absolute nix-provisioned libnotify backend via BIRC_NOTIFY_SEND_DEFAULT
# (never ambient PATH, never PATH append/prepend, so an ambient impostor can
# never shadow it); only an explicit BIRC_NOTIFY_SEND override selects
# another backend. The absolute store path in the wrapper text is the
# provenance the installed tests check. macOS has no nix backend: notify.py
# pins the OS-owned /usr/bin/osascript with BIRC_OSASCRIPT as the only
# override.
{ writeShellScriptBin, python3, stdenv, lib, libnotify ? null }:
writeShellScriptBin "birc-notify" ''
  ${lib.optionalString (stdenv.isLinux && libnotify != null) ''export BIRC_NOTIFY_SEND_DEFAULT="${libnotify}/bin/notify-send"''}
  exec ${python3}/bin/python3 ${../src/media/notify.py} "$@"
''
