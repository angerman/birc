// SPDX-License-Identifier: Apache-2.0
// JS twin of the upload effect. JS suites keep helpers fake; C owns production.

function upload_put(_path) {
  return io_tup(3, io_tup(io_str(""), 0));
}

io_eff(CID(upload_put), upload_put);
