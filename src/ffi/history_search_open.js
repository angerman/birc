// SPDX-License-Identifier: Apache-2.0
// Retained-fd private open (JS twin of the open_private effect in
// history_search_ffi.c): lstat plus O_NOFOLLOW open plus fstat admission,
// handing the numeric retained descriptor out as an affine File. Refusals
// close here and arrive as Fail: ENOENT (missing), EACCES (symlink,
// non-regular, foreign, or non-private), or the underlying errno.

function history_search_open_private(path) {
  const fs = require("fs");
  const name = io_bytes(path);
  if (name.includes(0)) {
    return io_fail(process.platform === "darwin" ? 92 : 84);
  }
  const buf = name.length > 0 ? Buffer.from(name) : "";
  let listed;
  try {
    listed = fs.lstatSync(buf);
  } catch (e) {
    return io_fail(-e.errno);
  }
  if (listed.isSymbolicLink()) {
    return io_fail(13);
  }
  let fd;
  try {
    fd = fs.openSync(
      buf,
      fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK
    );
  } catch (e) {
    const code = -e.errno;
    return io_fail(code === 40 || code === 62 ? 13 : code);
  }
  let info;
  try {
    info = fs.fstatSync(fd);
  } catch (e) {
    try {
      fs.closeSync(fd);
    } catch (_) {
      /* already closing */
    }
    return io_fail(-e.errno);
  }
  const admitted =
    info.isFile() &&
    info.uid === process.geteuid() &&
    (info.mode & 0o777) === 0o600;
  if (!admitted) {
    try {
      fs.closeSync(fd);
    } catch (_) {
      /* already closing */
    }
    return io_fail(13);
  }
  return io_done(fd);
}

io_eff(CID(open_private), history_search_open_private);
