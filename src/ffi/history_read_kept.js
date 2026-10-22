// SPDX-License-Identifier: Apache-2.0
// JS twin of read_kept. Suites that run on bun have no C ring, so this
// returns every framed record and an empty name list. A final symlink is
// refused before the read (lstat, then open with O_NOFOLLOW) and is stage 2.
// Bend still accepts each record, caps each buffer, and evicts. The native
// client uses the C ring in history_ffi.c and does not call this file.

function history_kept_errno(err) {
  const n = err && typeof err.errno === "number" ? err.errno : 0;
  return n < 0 ? -n : n;
}

function history_kept_pack(stage, err, names, lines) {
  return io_tup(stage, io_tup(err, io_tup(names, lines)));
}

function history_kept_nil() {
  return { $: "Nil" };
}

function history_kept_list(items) {
  let xs = history_kept_nil();
  for (let i = items.length; i > 0; i -= 1) {
    xs = { $: "Con", head: items[i - 1], tail: xs };
  }
  return xs;
}

function history_kept_utf8(bytes) {
  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch (_) {
    return null;
  }
}

function history_kept_lines(buf) {
  const lines = [];
  let start = 0;
  for (let i = 0; i < buf.length; i += 1) {
    if (buf[i] !== 10) continue;
    const n = i - start;
    if (n > 0 && n <= 8192) {
      const text = history_kept_utf8(buf.subarray(start, i));
      if (text !== null) {
        lines.push(history_kept_list(text.split("\t")));
      }
    }
    start = i + 1;
  }
  return lines;
}

function history_kept_eloop() {
  const os = require("os");
  const errno = os.constants && os.constants.errno;
  return errno && typeof errno.ELOOP === "number" ? errno.ELOOP : 62;
}

function history_kept_flags(fs) {
  const c = fs.constants;
  return c.O_RDONLY | (c.O_NOFOLLOW || 0) | (c.O_NONBLOCK || 0) | (c.O_CLOEXEC || 0);
}

function history_kept_fail(err) {
  const code = history_kept_errno(err);
  return history_kept_pack(code === 2 ? 1 : 2, code, history_kept_nil(), history_kept_nil());
}

// lstat rejects a symlink before any read. O_NOFOLLOW covers a replace
// between that check and the open. Regular files still return every record.
function read_kept(path, _endpoint, _cap) {
  const fs = require("fs");
  const name = io_bytes(path);
  if (name.includes(0) || io_bytes(_endpoint).includes(0)) {
    return history_kept_pack(2, 92, history_kept_nil(), history_kept_nil());
  }
  const file = name.length > 0 ? Buffer.from(name) : "";
  let st;
  try {
    st = fs.lstatSync(file);
  } catch (err) {
    return history_kept_fail(err);
  }
  if (st.isSymbolicLink()) {
    return history_kept_pack(2, history_kept_eloop(), history_kept_nil(), history_kept_nil());
  }
  let fd;
  try {
    fd = fs.openSync(file, history_kept_flags(fs));
    const buf = fs.readFileSync(fd);
    fs.closeSync(fd);
    return history_kept_pack(0, 0, history_kept_nil(), history_kept_list(history_kept_lines(buf)));
  } catch (err) {
    if (typeof fd === "number") {
      try { fs.closeSync(fd); } catch (_) { /* the open error is the result */ }
    }
    return history_kept_fail(err);
  }
}

io_eff(CID(read_kept), read_kept);
