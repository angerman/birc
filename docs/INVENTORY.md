# birc.c inventory (M0.1)

Classification of every non-trivial symbol in `src/ui/birc.c`.
Target: pure → Bend; TimUI/draw → FFI; threads/socket → Bend net + thin FFI.

| Symbol | Kind | Threads | Destination |
|---|---|---|---|
| `LK_*` / `IrcLine` / `IrcBuffer` / `IrcClient` | model | UI | Bend `client.bend` |
| `ts_now` | IO (clock) | UI | Bend foreign or omit in demos |
| `buf_find` / `buf_get` / `buf_logf` | pure* | UI | Bend (`buf_log` takes ready String) |
| `nick_strip` / `nick_index` / `nick_add` / `nick_del` / `nick_rename` | pure | UI | Bend |
| `irc_feed` | pure | UI | Bend `feed` |
| `IrcNet` / `net_send` / `net_write_*` / `net_dial` / `net_nap` / `net_post_line` / `irc_worker` | IO + pthread | worker | Bend net (M4) + `Timui.post` FFI |
| `irc_submit` | pure | UI | Bend `submit` |
| `draw_rich` / `draw_scrollback` / `nick_cell` | TimUI | UI | FFI `Timui.draw` (coarse ViewModel) |
| `irc_client_init` / `DEMO_LINES` / `irc_replay_file` | pure / file IO | UI | Bend fixtures + optional File FFI |
| `main` | TimUI loop + argv | UI | Bend `app.bend` main |

\* `buf_logf` formats then mutates — Bend splits format from append.

Also `src/ui/irc_proto.h`: entire file is a **duplicate** of Bend `irc.bend` parse/classify; delete after M5.
