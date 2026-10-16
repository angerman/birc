# SPDX-License-Identifier: Apache-2.0
# Bounded helper-process spawn. IO only: a proof module must not import this.
# A failed spawn that reports exit 0 is not helper success.
import Base

type Spec is Data:
  Spec{env_var: String, default_name: String, out_cap: U32, deadline_ms: U32}

# Exit 0 from a spawn failure is a failure. Never read it as helper success.
def spawn_code(+code: U32) -> U32:
  Bool.pick(U32, U32.is_zero(code), 1, code)

def name_got(got: Result<&1, &1, U32 & String, String>, +default_name: String) -> String:
  match got:
    case Fail{_}: default_name
    case Done{+value}: Bool.pick(String, String.is_empty(value), default_name, value)

def name_opt_of(empty: Bool, +value: String) -> Maybe<&2, String>:
  match empty:
    case True{}: None{}
    case False{}: Some{value}

def name_opt_str(+value: String) -> Maybe<&2, String>:
  name_opt_of(String.is_empty(value), value)

# Empty resolved name means unconfigured. Notify uses this so a missing helper
# spawns nothing; callers with a real default_name never see None.
def name_opt_got(got: Result<&1, &1, U32 & String, String>, +default_name: String) -> Maybe<&2, String>:
  name_opt_str(name_got(got, default_name))

def name(spec: Spec) -> IO(String):
  match spec:
    case Spec{+env_var, +default_name, _, _}:
      do IO<String>:
        got : Result<&1, &1, U32 & String, String> <- IO.get_env(env_var)
        return name_got(got, default_name)

def name_opt(spec: Spec) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    value : String <- name(spec)
    return name_opt_str(value)

def run_named(+program: String, spec: Spec, args: List<&1, String>, +stdin: String) -> IO(Result<&1, &1, U32 & String, U32 & (String & String)>):
  match spec:
    case Spec{_, _, +out_cap, +deadline_ms}:
      Process.run(program, args, stdin, out_cap, deadline_ms)

def run(+spec: Spec, args: List<&1, String>, +stdin: String) -> IO(Result<&1, &1, U32 & String, U32 & (String & String)>):
  do IO<Result<&1, &1, U32 & String, U32 & (String & String)>>:
    helper : String <- name(spec)
    run_named(helper, spec, args, stdin)
