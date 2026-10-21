// SPDX-License-Identifier: Apache-2.0
// JS twin of the preferences file effect. JS suites keep preferences
// disabled; a nonempty path is refused so C remains the production owner.

function prefs_load(path, _host, _port) {
  const name = io_bytes(path);
  if (name.length === 0) {
    return io_tup(0, io_str(""));
  }
  return io_tup(3, io_str(""));
}

function prefs_save(path, _host, _port, _body) {
  const name = io_bytes(path);
  return name.length === 0 ? 0 : 3;
}

io_eff(CID(prefs_load), prefs_load);
io_eff(CID(prefs_save), prefs_save);
