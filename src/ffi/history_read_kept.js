// SPDX-License-Identifier: Apache-2.0
// JS twin of read_kept. Suites that run on bun have no C ring, so this
// returns every framed record and an empty name list. Bend still accepts
// each record, caps each buffer, and evicts. The native client uses the C
// ring in history_ffi.c and does not call this file.

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

function read_kept(path, _endpoint, _cap) {
  const fs = require("fs");
  const name = io_bytes(path);
  if (name.includes(0) || io_bytes(_endpoint).includes(0)) {
    return history_kept_pack(2, 92, history_kept_nil(), history_kept_nil());
  }
  const file = name.length > 0 ? Buffer.from(name) : "";
  let buf;
  try {
    buf = fs.readFileSync(file);
  } catch (err) {
    const code = history_kept_errno(err);
    return history_kept_pack(code === 2 ? 1 : 2, code, history_kept_nil(), history_kept_nil());
  }
  return history_kept_pack(0, 0, history_kept_nil(), history_kept_list(history_kept_lines(buf)));
}

io_eff(CID(read_kept), read_kept);
