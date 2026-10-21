// SPDX-License-Identifier: Apache-2.0
// JS twin of the image/card fetch effect. JS suites keep helpers off or
// fake; C remains the production owner.

function media_load(_local, _source) {
  return io_tup(3, io_str(""));
}

function cards_load(_local, _source) {
  return io_tup(3, io_str(""));
}

io_eff(CID(media_load), media_load);
io_eff(CID(cards_load), cards_load);
