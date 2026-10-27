# `run` instead of `source`, and what else already exists

Fifth note. Prompted by the observation that the shim should use `run`, not `source`. This
checks that against Nushell 0.116.1 (the pinned binary), Nushell `main` at 36c057c (the 0.117
line), and usage 7.1.3, and sweeps both projects for capabilities the earlier notes missed.

## Why `source` was wrong

`source` is a parse-time splice: the script's block is parsed into the enclosing scope and its
statements run there. Inside a shim that means the script's `$env` changes, `let` variables and
`def`s all land in the shim's scope, every script in a module is parsed when the module is, and
a `let usage` in one body is the same kind of thing as any variable the script declares. It
worked in the fixtures because the fixtures are tiny.

## What `run` is

Added in 0.114 (`crates/nu-command/src/misc/run.rs`, parser side in
`crates/nu-parser/src/parse_source.rs`). A parser keyword: `run <file> ...args`, with
`--full-reparse`. Verified on 0.116.1:

| Behaviour                                                       | Result                                     |
| --------------------------------------------------------------- | ------------------------------------------ |
| Script references `$usage` declared by the caller               | works; the script is parsed in the caller's scope |
| Pipeline input                                                  | reaches the script as `$in`                |
| `$env` set inside the script                                    | does not leak back                         |
| `let` inside the script                                         | does not leak back                         |
| `def` inside the script                                         | declared in the parsing scope (inside a `def` body that scope is local, so harmless there) |
| `$env.CURRENT_FILE`, `$env.FILE_PWD`                            | the script's own                           |
| Path relative to the module file, from inside an `export def`   | resolves                                   |
| Runtime (non-constant) path                                     | refused: the path is read at parse time    |
| Script edited after the module was parsed                       | stale until re-`use` or `--full-reparse`   |
| Script with `def main [...]`, arguments after the path          | bound to `main`'s signature                |
| `def "main db migrate"` subcommands                             | not dispatched; only `main` is found (`find_main_block_id_in_script`) |

On the 0.117 line `run` goes further (`crates/nu-command/tests/commands/run.rs`, PR #19272 for
issue #19266): arguments are checked against `main`'s signature at parse time, unknown flags are
rejected unless `main` is `--wrapped`, short flags bind like a call, `run x.nu --help` shows
`main`'s help, and attributes on `main` are honoured. On 0.116.1 the same call silently runs
`main` with the extra words dropped.

So the shim body is `$in | run ../script.nu`, and the fixtures, harness and README now say so.
All 19 checks pass unchanged, which confirms the record contract did not depend on `source`.

Three channels can carry `$usage` into a script under `run`, all verified:

1. A free `$usage` in the script, declared by the caller before `run`. This is what the shim
   does. It relies on the script being parsed in the caller's scope, which is how `run` is built
   and how `source` behaves, but it is not something the docs promise.
2. `$env`: `with-env { nusage: $usage } { $in | run script.nu }` and `$env.nusage` in the
   script. Non-string env values are fine inside a session. Documented, slightly uglier.
3. `def main [usage: record]` in the script and `run script.nu $usage`. Explicit and typed, but
   it puts a signature in the script, which the design avoids.

Keep 1, and keep 2 as the fallback if a future `run` parses scripts in a clean scope.

## Capabilities checked and where they fit

Nushell, present in 0.116.1 unless marked:

- **`nu script.nu` with `def "main db migrate"`.** Nushell's own subcommand convention for a
  single script file: `nu script.nu db migrate prod` dispatches, and `--help` lists the
  subcommands. `run` does not dispatch these. Relevant if a shebang script wants a subcommand
  tree without a directory; the `mod.nu` tree is the module-side equivalent.
- **`run` argument binding to `main`** (0.117). A script that carries its own `def main`
  signature gets typed parsing, rejection of unknown flags and `--help` through `run`, in the
  caller's session, with no shim. The shim exists because the signature is generated from the
  header rather than written in the script; if that ever flips, `run` alone covers the
  in-session case and `nu script.nu` the shebang case.
- **Alias-backed attributes.** `alias "attr requires" = echo` makes `@requires key [identity]`
  inert metadata on a `def`, visible in `scope commands`, readable by the command's own body.
  No engine change.
- **`commandline complete --input`.** Returns the `{token, place, buffer}` record a completer
  receives, with `place.command` holding the parsed words, so dependent completions can be
  developed and tested without a REPL.
- **`path self`.** A command can learn its own file at parse time.
- **`scope commands`.** Parsed signatures as data, including completion lists and defaults;
  the right replacement for help-text snapshots.
- **`@structured` on `extern`, `type` aliases, custom types in signatures, `extern --strict`**
  (0.117). Covered in the earlier notes.
- **`nu --lsp`, `nu --ide-check`, `--ide-ast`, `--ide-hover`, `--ide-complete`.** The
  diagnostics seam; no third-party extension point, diagnostics come from the parser.
- **`nu --mcp`** (since 0.108, `crates/nu-mcp`). Exposes `list_commands`, `command_help` and
  `evaluate` to agents. Not a scripting feature, but note that `usage mcp` serves the same
  audience from the spec side.
- **`nu-dap`.** A debug adapter; irrelevant here.

usage 7.1.3:

- **Sidecar spec files** (7.0.2): a `.<script>.usage.kdl` beside a script is read instead of the
  header comments, by `usage exec` and by completion. A second way to attach a spec to a `.nu`
  file without touching it; worth supporting alongside `#USAGE`.
- **`usage exec`** with a quoted interpreter string, delivering `usage_*` env vars. Still no
  `usage nu`, and no typed delivery, so the interpreter wrapper remains nusage's.
- **No structured export of a parse result.** `usage g json` exports the spec, not
  `ParseOutput`. The `$usage` record is nusage's contract.
- **Effect v4 exporter** (7.1.0), **MCP server**, **`usage-dynamic` / `mount`**, **SDKs with
  `jsonl` streaming**: all spec-side, none overlapping the shim.
- usage already tracks Nushell: 7.1.1 fixed a 0.116 deprecation warning in its generated
  completer.

## What this changes in the plan

- The shim body is `$in | run <path>`; done.
- The interpreter prelude is `let usage = (...); $in | run /abs/script.nu`; done in the harness.
- `--full-reparse` is the development-loop switch: a `nusage dev` mode can emit it so script
  edits are live without re-`use`-ing the module.
- Scripts needing a subcommand tree under the shebang entrypoint can use `def "main sub"` in one
  file instead of a directory; the generator can target either.
- Nothing found replaces the generator, the attribute vocabulary, or the `$usage` contract.
