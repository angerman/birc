# CLI parse: missing values, bad numbers, --connect vs --demo. Assert.
import Base
import ./expect.bend as E
import ../../src/bend/args.bend as Args

def xs1(+a: String) -> List<&2, String>:
  a <> Nil{}

def xs2(+a: String, +b: String) -> List<&2, String>:
  a <> b <> Nil{}

def xs_live() -> List<&2, String>:
  "--connect" <> "10.0.0.1" <> "--port" <> "6667" <> "--nick" <> "z" <> "--channel" <> "#x" <> "--frames" <> "4" <> Nil{}

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("num_ok", Args.show_num(Args.parse_u32("12")), "True:12")
    Unit <- E.must_eq("num_u32_max", Args.show_num(Args.parse_u32("4294967295")), "True:4294967295")
    Unit <- E.must_eq("num_u32_overflow", Args.show_num(Args.parse_u32("4294967296")), "False:0")
    Unit <- E.must_eq("num_bad", Args.show_num(Args.parse_u32("abc")), "False:0")
    Unit <- E.must_eq("num_empty", Args.show_num(Args.parse_u32("")), "False:0")
    Unit <- E.must_eq(
      "default",
      Args.show_parsed(Args.parse(Nil{})),
      "good:demo=True frames=0 host= port=6667 nick=birc chan=#birc replay="
    )
    Unit <- E.must_eq(
      "connect",
      Args.show_parsed(Args.parse(xs_live())),
      "good:demo=False frames=4 host=10.0.0.1 port=6667 nick=z chan=#x replay="
    )
    Unit <- E.must_eq(
      "missing_connect",
      Args.show_parsed(Args.parse(xs1("--connect"))),
      "bad:birc: missing value"
    )
    Unit <- E.must_eq(
      "bad_frames",
      Args.show_parsed(Args.parse(xs2("--frames", "xyz"))),
      "bad:birc: expected a number"
    )
    Unit <- E.must_eq(
      "unknown",
      Args.show_parsed(Args.parse(xs1("--nope"))),
      "bad:birc: unknown option --nope"
    )
    Unit <- E.must_eq(
      "help",
      Args.show_parsed(Args.parse(xs1("--help-irc"))),
      "bad:usage: birc [--frames N] [--connect HOST] [--port N] [--nick N] [--channel #c] [--replay FILE] [--demo] [--help-irc]"
    )
    Unit <- E.must_eq(
      "demo_after_connect",
      Args.show_parsed(Args.parse("--connect" <> "10.0.0.1" <> "--demo" <> Nil{})),
      "good:demo=True frames=0 host=10.0.0.1 port=6667 nick=birc chan=#birc replay="
    )
    Unit <- E.must_eq(
      "replay",
      Args.show_parsed(Args.parse(xs2("--replay", "fixtures/demo.irc"))),
      "good:demo=True frames=0 host= port=6667 nick=birc chan=#birc replay=fixtures/demo.irc"
    )
    Unit <- E.must_eq(
      "missing_replay",
      Args.show_parsed(Args.parse(xs1("--replay"))),
      "bad:birc: missing value"
    )
    Unit <- E.must_eq(
      "frames_cap",
      Args.show_parsed(Args.parse(xs2("--frames", "65536"))),
      "bad:birc: --frames too large"
    )
    IO.print("args_demo=ok")
