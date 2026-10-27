# Revision: scripts as subcommands, a usage table instead of argv

Follow-up to `nu-plugin-usage-adapter-analysis.md`. The first analysis assumed the
plugin wraps an external binary and renders argv. This one takes the stated design:
subcommands are Nushell script files, their usage spec lives in `#USAGE` header
directives, the scripts declare no `def main`, and they receive their arguments as a
structured `$usage` value rather than argv or `usage_*` environment variables.

Same upstream checkouts as before: Nushell `main` 36c057c (0.117 line), usage f357a6c.

## What holds up

- **argv and env vars are lossy, as stated.** usage's own `ParseValue` is
  `Bool | String | MultiBool | MultiString`, and the script contract is one string per
  `usage_<name>` variable with shell-words joining for lists. Nothing typed survives.
- **The plugin already holds the lossless form.** `EvaluatedCall` carries real
  `Value`s: ints, paths, lists, records, dates, durations, whatever the signature
  declared. Building a `$usage` record from them is a direct mapping, no serialisation.
- **Headers in `.nu` files parse today.** `Spec::parse_script` extracts
  `#USAGE` lines from any file whose first line starts with `#!`
  (`lib/src/spec/mod.rs`, `split_script`). Without a shebang the whole file is read as
  KDL, so every script needs `#!/usr/bin/env nu` on line one even though nothing will
  exec it through that line. The `#` prefix is the right one for Nushell comments.
- **A lossless carrier exists if a value must cross a process boundary.** The `nuon`
  crate (`crates/nuon`) gives `to_nuon`/`from_nuon` for every value kind except
  closures and custom values; `to msgpack`/`from msgpack --objects` do the same with
  native date, duration and filesize encoding and streaming on the way back.

## What usage does not supply

usage has no Nushell runner and no directory-of-scripts convention. Its shells are
bash, zsh, fish and PowerShell plus `usage exec <interpreter>`, all of which deliver
values as environment variables. `mod.nu` is Nushell's directory-module convention:
`mycli/mod.nu` is the module root and `mycli/build.nu`, `mycli/db/mod.nu`,
`mycli/db/migrate.nu` are its submodules. Mapping that tree onto a command tree is
nusage's job, and so is assembling one `Spec` from per-file headers: parse each
header with `Spec::parse_script_str`, take its root `cmd` as the subcommand, hang it
under the directory path, and let `mod.nu`'s header hold what belongs to the parent
(`name`, `bin`, global flags, CLI-wide `output` and `exit_code`).

## The constraint that decides the architecture

A plugin cannot evaluate Nushell source in the calling engine. The engine calls
available from a plugin are `FindDecl`, `CallDecl`, `EvalClosure` (needs a closure
that already exists in the engine), `GetBlockIR`, config and env access
(`crates/nu-plugin-protocol/src/lib.rs`). `source`, `use` and `overlay` are parser
keywords: `source` parses the file into a block in the current working set at parse
time and splices a call to it into the pipeline (`crates/nu-parser/src/parse_source.rs`).
There is no "parse this text" call and no way to mint a block id from the plugin side.

So "the plugin owns the typed signature" and "the caller's engine runs the script"
cannot both be true in one process without a generated shim. That leaves two
execution models. Both share the signature mapping, the `$usage` shape and the
header-to-spec assembly from the first analysis; they differ only in where the script
runs.

## Model A: plugin-hosted, script runs in a child `nu`

The plugin registers one command per script, built from its header. On a call:

1. Convert `EvaluatedCall` into the `$usage` record (see shape below). Values stay
   typed. Nothing is rendered to strings.
2. Serialise the record with `nuon::to_nuon` and spawn the user's `nu` binary with a
   prelude, for example:

   ```
   nu --stdin -c 'let usage = <nuon literal>; source /abs/mycli/build.nu'
   ```

   `source` sees `$usage` because the sourced block is spliced into the scope that
   declared it. The pipeline input from the caller is copied to the child's stdin, so
   `$in` works at the script's top level. Environment comes from `get_env_vars()`,
   working directory from `get_current_dir()`.
3. The child's stdout comes back as a `ByteStream`. For scripts whose header declares
   an `output`, the prelude appends the framing (`| to json --objects` for `jsonl`,
   `| to nuon` or `| to msgpack` for lossless single values) and the plugin decodes:
   either `serde_json` → `Value` in-plugin, or hand the bytes to the engine's own
   `from msgpack --objects` through `call_decl` so dates and durations round-trip
   without the plugin touching `Value` construction. `jsonl`/msgpack-objects framing
   gives a true `ListStream` back to the caller.

What this costs:

- A second engine per invocation: process start plus config load. Use
  `--no-config-file` and forward env for speed, or let the user's config load for
  fidelity; this is a measurable trade and the spike should measure it.
- The script runs outside the caller's scope. The caller's custom commands, aliases,
  overlays and `$env` mutations are invisible to it, and its own `$env` changes do
  not come back.
- Closures and custom values cannot be arguments; NUON refuses them.
- Interactive scripts need `enter_foreground()` and the terminal-passthrough caveat
  from the first analysis.

What it buys: no generated files anywhere, one binary, the `plugin add` cycle as the
only registration step, signatures and help that update when headers change (after
re-adding the plugin).

## Model B: engine-hosted through a thin shim module

The plugin, at `plugin add` or via a `nusage sync` command, writes a module into a
cache directory, one `export def` per script, mechanically derived from the header:

```nu
# ~/.cache/nusage/mycli/mod.nu
export def "db migrate" [
    target: string,
    --dry-run,
]: nothing -> table<name: string, applied: bool> {
    let usage = { cmd: "db migrate", args: { target: $target }, flags: { dry_run: $dry_run } }
    source /abs/mycli/db/migrate.nu
}
```

The user's config has one static line: `use <cache path>/mycli`. The script runs in
the caller's engine, in scope, lossless, with `$in` flowing, with closures allowed as
arguments, with `type` aliases available (the shim can declare them from the output
schema), with `--env` possible when a script should mutate the caller's environment.
The plugin keeps the non-trivial runtime pieces as plain commands the shim calls:
`nusage validate` for the relationship rules usage enforces (`conflicts`, `requires`,
`required_if`, groups, `validate` expressions), `nusage complete` for dynamic
completions, `nusage spec` for `help`-adjacent rendering.

This is the generated-code route the brief wanted to avoid. It is also the only route
to in-engine execution with today's protocol, and the generated part is five lines per
command with no logic in it. Treating it as a cache the plugin maintains rather than
source the user owns keeps the ergonomics close to a plugin. Verify in the spike that
`source` inside a `def` body resolves `$usage` from the enclosing `let`; the parser
splices the block into the current scope, so it should, but it has not been confirmed
here.

A third path, worth an upstream issue rather than a dependency: a plugin signature
that names a script path the engine `source`s itself. That is Model B with the shim
written by the engine instead of by the plugin.

## The `$usage` value

Keep the shape close to usage's `ParseOutput` so the same mental model serves every
usage consumer:

```nu
{
  cmd: "db migrate",          # canonical path, space-joined, like usage_cmd
  cmds: ["db", "migrate"],
  args: { target: "prod" },
  flags: { dry_run: true, env: null },
  origins: { env: "default" }  # cli | env | default, once usage re-validation runs
}
```

Fidelity is "what usage can represent, typed where Nushell already knows the type":
`<file>` and `<dir>` arrive as paths, `choices` as strings, switches as bools,
variadics as lists, `count=#true` as an int, repeated flags as lists. Names are
snake-cased the way `usage_<name>` already does.

For types usage cannot express (ints, datetimes, durations, records), do not bend
usage's KDL; usage-lib validates its grammar and other consumers (completions,
docs, MCP) must keep reading the same header. Add a second directive the plugin owns:

```nu
#!/usr/bin/env nu
#USAGE arg "<since>" help="Only entries after this time"
#USAGE flag "--limit <n>" help="Max entries"
#NUSAGE type since=datetime limit=int
#NUSAGE output table<name: string, at: datetime>
```

`#USAGE` stays a valid usage spec everywhere; `#NUSAGE` upgrades the Nushell signature
and the `$usage` value. Where no `#NUSAGE` line exists, the usage-level fidelity is
the default.

Validation of relationship rules no longer needs real argv: usage's `Parser` only
needs presence and string forms to check `conflicts`, `requires`, `required_if` and
`validate`, so render a presence-only argv for the check and discard it. The values
the script receives never pass through it.

## What changes against the first analysis

- The external-binary runner, argv rendering for execution, and exit-code policy for
  foreign tools drop out of the core path. They remain useful as a separate "wrap an
  existing CLI" mode built on the same spec model, which is where usage's `output`
  declarations with JSON Schema came from in the first place.
- Output typing for scripts comes from `#NUSAGE output` or, in Model B, from the shim's
  declared output type, not from JSON Schema.
- Streaming in Model A is line-framed NUON/JSON/msgpack from the child back to a
  `ListStream`; in Model B there is no boundary and the script's own pipeline streams.
- The layered crate design stands: a core crate with no Nushell dependency owns header
  assembly, the `#NUSAGE` directive, the `$usage` shape and the shim template; the
  plugin crate owns `Signature`/`Value` mapping and, in Model A, the child-process
  runner.

## Suggested order

1. Spike Model A on Nushell `main` with a two-script `mycli/` directory: confirm
   header assembly, `$usage` through NUON, `$in` through stdin, `jsonl` back as a
   `ListStream`, and measure the per-call cost of the child engine with and without
   config loading.
2. In the same spike, hand-write the Model B shim for one command and confirm
   `source` inside a `def` body sees `$usage`. That settles whether B is viable before
   any generator exists.
3. Decide the default on the measured cost. If the child engine is cheap enough for
   the intended scripts, ship A and keep B as `nusage sync` for people who need
   in-scope execution. If not, B becomes the default and the plugin is the runtime
   behind it.
