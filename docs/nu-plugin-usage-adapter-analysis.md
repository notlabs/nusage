# A Nushell plugin as an adapter for usage specs

Analysis written against Nushell `main` at commit 36c057c (2026-10-26, version string
0.116.2, i.e. the unreleased 0.117 line) and jdx/usage at f357a6c (usage-lib 7.1.3).
File references below are paths inside those two checkouts.

## Short answer

Yes, the plugin protocol carries everything needed for the *input* side (typed
signatures, flags, positionals, completions, help), and it carries streaming in both
directions, so the *output* side can be done without buffering for `jsonl`-framed
outputs. Two things do not cross the protocol boundary and shape the design:

1. The new `type` keyword is a parser-level alias. It never reaches a plugin and a
   plugin cannot declare one. Signatures sent by a plugin carry fully expanded
   structural types (`record<passed: bool>`), which is what the alias would resolve to
   anyway.
2. `@structured` is an `extern`-only attribute. A plugin command has no attributes on
   the wire and never learns where its output is going, so it cannot replicate the
   "decode when piped, run as written when printed" behaviour. A plugin command always
   returns data.

Everything else is mapping work plus one architectural choice about where argument
validation lives. The version coupling is real but bounded: one rebuild per Nushell
release, nightlies within a release line work.

## What the two sides look like

### Nushell plugin protocol (0.117 line)

- Handshake: `ProtocolInfo { version, features }`, where `version` is the
  `nu-plugin-protocol` crate version. Compatibility is a caret match on the lower of the
  two versions after stripping the prerelease tag
  (`crates/nu-plugin-protocol/src/protocol_info.rs`). With 0.x versions that means
  0.117.0 ↔ 0.117.x ↔ 0.117.x-nightly all pass, and 0.118 refuses. So: rebuild per
  release, not per nightly.
- Signature call: the plugin answers `Vec<PluginSignature { sig: Signature, examples }>`
  (`crates/nu-protocol/src/plugin/signature.rs`). `Signature` is the same struct
  built-in commands use: positionals with `SyntaxShape`, flags with
  `Option<SyntaxShape>` + `required` + `Completion`, `input_output_types:
  Vec<(Type, Type)>`, `allows_unknown_args`, `rejects_unknown_flags`,
  `complete: Option<CommandWideCompleter>`. All of it is serde-serialised as is.
- `Type` includes `Record(cols)`, `Table(cols)`, `List`, `OneOf`, `Custom(name)`
  (`crates/nu-protocol/src/ty.rs`). Custom types in signatures landed in PR #19311
  (merged 2026-10-23, milestone 0.117.0).
- Run call: `CallInfo { name, call: EvaluatedCall, input }`. `EvaluatedCall` is
  `positional: Vec<Value>` and `named: Vec<(Spanned<String>, Option<Value>)>`. Nushell
  has already parsed, type-checked and evaluated the arguments. Short flags arrive
  resolved to their long names. The plugin sees nothing about stdout redirection.
- Streaming: `PipelineDataHeader::{Empty, Value, ListStream, ByteStream}`, then
  `Data(id, List(Value) | Raw(Result<Vec<u8>, LabeledError>))`, `End`, `Drop`, `Ack`.
  Backpressure is a high-water mark of unacknowledged chunks
  (`crates/nu-plugin-core/src/interface/stream/mod.rs`). `ByteStreamInfo` carries a
  `ByteStreamType` (`Binary`, `String`, `Unknown`) and `PipelineMetadata`, which has a
  `content_type` slot. Both directions stream; the plugin receives `PipelineData` and
  returns `PipelineData`.
- Completion: `PluginCommand::get_dynamic_completion` answers the `GetCompletion`
  call with `Vec<DynamicSuggestion>`. It is marked experimental in the trait.
- Engine calls available from inside a run: `find_decl`, `call_decl`, `eval_closure`,
  `get_env_vars`, `get_current_dir`, `enter_foreground`, `get_plugin_config`,
  `register_signal_handler` (`crates/nu-plugin/src/plugin/interface/mod.rs`).
- Caching: `plugin add` launches the plugin once, calls `get_signature()`, and stores
  the signatures in the registry file. `plugin use` loads from that file at parse time
  without launching the plugin (`crates/nu-cmd-plugin/src/commands/plugin/add.rs`,
  `crates/nu-protocol/src/plugin/registry_file/mod.rs`). The command set is frozen
  until `plugin add` runs again.
- Attributes: `Command::attributes()` defaults to empty and `PluginDeclaration` does
  not override it. `PluginSignature` has no attribute field. `parse_def.rs` rejects
  `@structured` on anything but `extern`.

### usage (7.x)

- `Spec` parses from KDL text, a `.kdl` file, or a script's `#USAGE` / `//USAGE` /
  `::USAGE` header comments (`Spec::parse_script`, `Spec::parse_script_str`,
  `Spec::parse_file` in `lib/src/spec/mod.rs`). Header parsing is exactly the
  "directives" case you described, and it needs no extra work.
- The model is `SpecCommand { subcommands, args: Vec<SpecArg>, flags: Vec<SpecFlag>,
  mounts, groups, outputs, exit_codes, effect, unknown_flags, ... }`. Args and flags are
  untyped strings on the wire: `ParseValue` is `Bool | String | MultiBool |
  MultiString`. Typing in usage comes from `choices`, `validate` expressions, the
  `<file>`/`<dir>` naming convention and `complete type=`.
- Outputs are new and are the "output use case": `output "json" media_type=...
  framing="json|jsonl|text" { schema ... }`, selected by a flag (`select`), with
  exit-code declarations (`docs/spec/reference/output.md`, `lib/src/spec/output.rs`).
  The schema is carried as an opaque string on purpose; usage-lib has no JSON
  dependency.
- The TS/Python SDK generators (`lib/src/sdk/`) are the reference semantics: build
  argv from typed args and flags, run the binary, return `{stdout, stderr, exit_code}`;
  with declared outputs add `execJson()` and a streaming iterator for `jsonl`.
- usage-lib pulls `usage-argv`, `indexmap`, `winnow` (pinned), `regex`, `serde`,
  `semver`, no process library. Light enough to embed in a plugin.
- `usage generate completion nu` already exists (`lib/src/complete/nu.rs`) but only
  produces a completer that shells out to `usage complete-word`. Nothing typed.

## Mapping the input side

Most of a usage `cmd` tree maps directly onto `Signature`:

| usage                               | Nushell `Signature`                                                |
| ----------------------------------- | ------------------------------------------------------------------ |
| `cmd "build"` under `bin "mycli"`   | a `PluginCommand` named `mycli build` (multi-word names are fine)  |
| `arg "<file>"`, `arg "[file]"`      | `required` / `optional` positional; `Filepath` or `Directory` shape by the `<file>`/`<dir>` convention or `complete type=`, else `String` |
| `arg "<x>..."`, `var=#true`         | `rest` positional with `SyntaxShape::String`                       |
| `flag "-f --force"`                 | `Flag { arg: None }` switch, short char kept                       |
| `flag "--user <user>"`              | `Flag { arg: Some(String) }`                                       |
| `required=#true` on a flag          | `Flag.required`                                                    |
| `choices "a" "b"`                   | `Completion::List` on the parameter; value validation at run time  |
| `complete run=` / `delegate=`       | `get_dynamic_completion` running the command and returning suggestions |
| `global=#true`                      | copy the flag into every descendant command's signature            |
| `help`, `long_help`, `help_md`      | `description`, `extra_description`                                 |
| `alias`                             | an extra `PluginCommand` with the alias name (nu has no alias field on signatures) |
| `unknown_flags="pass"`              | `allows_unknown_args = true`; `rejects_unknown_flags` for strict   |
| `output ... framing/schema`         | `input_output_types`, see below                                    |

Things Nushell's parser cannot express, so they must be enforced after evaluation:

- Repeated flags (`var=#true` on a flag) and `count=#true`. Nushell flags are given
  once. Map to `--include: list<string>` and `--verbose: int`, and render back to
  repeated argv words.
- `negate="--no-color"`. Expose `--color: bool` or two switches.
- `conflicts`, `requires`, `required_if*`, `required_unless*`, `exclusive`, `group`,
  `requires_if`, `default_if`, `validate` expressions, `delimiter`, `double_dash`
  modes, `value_optional`, `default_missing`, `require_equals`, `var_min`/`var_max`,
  `env` fallbacks and `default` values (the `default_value` field on
  `Flag`/`PositionalArg` is only consumed for custom commands with a `var_id`).

The clean way to get all of those for free: at run time, render the `EvaluatedCall`
back into a `Vec<String>` argv and run it through usage's own
`Parser::new(&spec).with_env(...).parse(&argv)` before spawning the child. Nushell
does syntax, types and completion at parse time; usage does the relationship rules,
defaults and env fallbacks at run time, and produces the same diagnostics every other
usage consumer produces. Spans from the `EvaluatedCall` can be attached to the
`LabeledError` so errors point at the offending argument. The cost is that these
errors surface at run time rather than parse time, which is also how `extern`
behaves today.

Naming: registering `git status` as a plugin command shadows `^git status`, which is
the same thing an `extern` does and is the intended effect. `type` is now a reserved
word, so a spec with a `type` subcommand needs a rename rule.

## Mapping the output side

### What the plugin can and cannot do compared with `@structured`

`@structured [--format=json] { from json }` on an `extern` does three things
(`crates/nu-parser/src/known_external.rs`): appends the args after the command name,
checks `OutDest` to decide whether the output is being consumed by Nushell, and runs
the decode block only in that case. A plugin cannot see `OutDest`, so a nusage command
always selects the structured output and always decodes. For the overwhelming majority
of tools (anything whose human output is just a rendering of the same data) this is
better, not worse: the table renderer does the rendering. The cases where it hurts are
TUIs, progress bars and tools whose human output carries information the JSON lacks.
Offer an escape hatch: a `--raw` flag on every generated command that skips output
selection and streams bytes, and remind users that `^tool` always exists.

### Framing → PipelineData

| usage output                 | Plugin return                                                            |
| ---------------------------- | ------------------------------------------------------------------------ |
| `text` (default)             | `PipelineData::ByteStream` with `ByteStreamType::String`, streamed from the child's stdout; `content_type` metadata from `media_type` |
| `json`                       | read to end, parse, one `Value`; declared type from the schema            |
| `jsonl`                      | `PipelineData::ListStream` of `Value`s, one per line, truly streamed as `List(Value)` chunks with Ack backpressure |
| binary media types           | `ByteStream` with `ByteStreamType::Binary`                               |
| no `output` declared         | `ByteStream` of unknown type, i.e. exactly what `^tool` gives            |

Streaming facts worth knowing:

- A `ByteStream` built from a `ChildProcess` (`ByteStream::child`) surfaces a nonzero
  exit as an error chunk at the end of the stream, so the consumer sees partial output
  and then the error, the same as externals.
- Every byte goes child → plugin → engine, serialised as MsgPack. For bulk binary
  output that is one extra copy compared with `run-external`, which reads the child's
  pipe directly. For `jsonl` the per-record `Value` serialisation is the natural unit
  and the overhead is fine.
- Cancellation arrives as `Signal(SignalAction)` or `Drop(stream)`; the plugin must
  kill the child on either. `engine.register_signal_handler` plus `engine.signals()`
  cover it.
- Interactive tools need `engine.enter_foreground()`. The plugin's own stdio is the
  protocol channel unless the local-socket feature is in use, so terminal passthrough
  is a separate mode to design, not a default.
- stdin: when the pipeline feeds the command, copy a `ByteStream` input to the child's
  stdin on a thread; serialise `Value`/`ListStream` input as lines or JSON by a policy
  you choose. usage declares outputs but not inputs, so this stays a heuristic.
- Exit codes: usage's SDK returns stdout and the exit code together because a
  documented nonzero status may accompany valid output. Nushell has no slot for that.
  Choose: treat declared exit codes with help text as errors carrying that text, and
  provide a `complete`-style record mode (`{stdout, exit_code, ...}`) as a flag.

### JSON Schema → `Type`

usage carries the schema verbatim; the plugin parses it with `serde_json` and maps:

- `object` with `properties` → `record<k: T, ...>`; `array` of objects → `table<...>`;
  `array` of other → `list<T>`; `string`/`integer`/`number`/`boolean`/`null` →
  `string`/`int`/`float`/`bool`/`nothing`; `anyOf`/`oneOf` → `oneof<...>`;
  anything unresolvable (`$ref` to elsewhere, `additionalProperties`, no schema) →
  `any`, `record` or `list<any>` by framing.
- `jsonl` declares `nothing -> list<record<...>>` (the engine shows a table); `json`
  declares `nothing -> <mapped type>`; `text` declares `nothing -> string`.

Record types in Nushell are checked structurally, so a value with extra columns
should still type-check against the declared columns; verify this in the spike rather
than assuming it.

### Where `type` fits

Because aliases are parser state (`TypeAlias { name, shape }` in
`crates/nu-protocol/src/type_alias.rs`), the only way to give users a *named* type is a
companion `.nu` module with `export type CheckReport = record<...>` generated from the
same schema. That is a small, optional codegen that does not touch commands, and it
is not needed for the plugin to work. It is worth keeping as a later add-on since the
LSP and `help` can then show the name.

## Avoiding coupling to the engine's `Value`

With the Rust SDK the coupling is unavoidable at the boundary: `nu-plugin` depends on
`nu-engine`, `nu-protocol`, `nu-plugin-protocol` and `nu-plugin-core`, and `run` must
return `PipelineData` of `Value`s. The alternative of speaking the JSON/MsgPack protocol
directly (the 268-line Python example does this) only moves the coupling: the wire
shape of `Value` is `Value`'s serde derive and changes with the same cadence, and you
then own stream management and backpressure yourself. Not worth it.

What is worth it is confining the coupling to one thin crate:

1. `nusage-core` (no Nushell dependency). usage `Spec` → a neutral command model:
   commands, parameters with a small type enum (string, int, float, bool, path, dir,
   list-of, enum-of-choices), outputs with framing and a neutral structural type derived
   from the schema. Argv rendering from a neutral argument-value model. A child-process
   runner that yields framed events: bytes, lines, parsed `serde_json::Value`s, exit
   status. All of the usage-side logic, all of the tests, none of the churn.
2. `nu_plugin_nusage` (pinned to the Nushell version). Neutral model → `Signature`,
   `SyntaxShape`, `Type`; `EvaluatedCall` → neutral values; `serde_json::Value` →
   `nu_protocol::Value` (about fifty lines); framed events → `PipelineData`. Tested
   with `nu-plugin-test-support::PluginTest`, which runs real pipelines against the
   plugin in-process.

A further option for the output decode step: instead of converting JSON to `Value` in
the plugin, hand the child's stdout `ByteStream` to the engine's own `from json` or
`from json --objects` via `find_decl` + `call_decl` and return what comes back. That
reuses Nushell's decoders byte for byte, including for `csv`, `xml` and `yaml` media
types, at the price of an extra protocol round trip for the data. Reasonable for
`json`, questionable for high-volume `jsonl`. The in-plugin `serde_json` → `Value`
mapping is small enough that it is the better default, with `call_decl` kept for the
non-JSON media types.

## Discovery, configuration and the `plugin add` cycle

Because signatures are cached at `plugin add` time, the plugin needs a deterministic
notion of "which specs" that it can compute without the engine (the `Signature` call
happens before any engine context is available to `Plugin::commands()`):

- A directory of `.usage.kdl` files and scripts with `#USAGE` headers, e.g.
  `$XDG_CONFIG_HOME/nusage/`, plus an env var override, read at startup.
- Specs obtained by running `tool --usage-spec` or `tool __usage_spec__` are the
  upstream convention for clap/Rust tools; support it but cache the KDL on disk so
  `plugin add` stays fast and deterministic.
- Changing the spec set means `plugin add nu_plugin_nusage` again. Document it; a
  `nusage reload` command can call `plugin add` through `call_decl` to make it one
  step.
- usage `mount` nodes (commands discovered at run time by running a command) do not
  fit the cached-signature model. Resolve mounts at `plugin add` time and accept
  staleness, or expose a generic untyped `nusage run <bin> ...` for them.

## Fit with the mise.toml pin

`mise.toml` pins `nu = "0.116.1"`. Everything above targets 0.117 (`type`,
`@structured` for reference, custom types in signatures, `rejects_unknown_flags`). The
build must depend on Nushell crates from git `main` until 0.117.0 ships, then on the
release, and the pinned `nu` binary used for integration tests must move with it.

## Effort

1. Spike, two to three days: one hand-built plugin with one spec on Nushell `main`.
   Verify `plugin add` → `help mycli build` → typed flags → `jsonl` as a `ListStream`
   through `where` → Ctrl-C kills the child. This settles the record-subtyping and
   streaming questions empirically.
2. `nusage-core`, one to two weeks: spec model, argv rendering, re-validation through
   usage's `Parser`, schema → neutral type, runner with framing and exit-code policy.
3. Plugin crate, about one week: signature mapping, value conversion, streams,
   signals, foreground, `--raw`, dynamic completion.
4. Discovery and config, a few days, plus docs on the `plugin add` cycle.
5. Optional: `export type` companion module generation; `call_decl` decode path for
   non-JSON media types; the `extern` + `@structured` codegen backend from the same
   neutral model for people who prefer scripts over a plugin.

## Sources

- Nushell `main` 36c057c: `crates/nu-plugin-protocol/src/{lib.rs,protocol_info.rs,evaluated_call.rs}`,
  `crates/nu-protocol/src/{signature.rs,ty.rs,type_alias.rs,plugin/signature.rs,plugin/registry_file/mod.rs,pipeline/byte_stream.rs}`,
  `crates/nu-parser/src/{known_external.rs,parse_def.rs,parse_type_alias.rs}`,
  `crates/nu-cmd-lang/src/core_commands/{attr/structured.rs,type_.rs}`,
  `crates/nu-plugin/src/plugin/{command.rs,interface/mod.rs}`,
  `crates/nu-plugin-core/src/interface/mod.rs`, `crates/nu-plugin-engine/src/declaration.rs`,
  `crates/nu-cmd-plugin/src/commands/plugin/add.rs`.
- usage f357a6c: `lib/src/spec/{mod.rs,arg.rs,flag.rs,cmd.rs,output.rs,complete.rs}`,
  `lib/src/parse.rs`, `lib/src/sdk/`, `lib/src/complete/nu.rs`,
  `docs/spec/reference/{output.md,arg.md,flag.md,cmd.md}`, `docs/cli/{scripts.md,sdk.md}`.
- [Allow Custom Types to be used in type signatures, nushell PR #19311](https://github.com/nushell/nushell/pull/19311)
- [attr structured documentation PR for 0.117.0](https://github.com/nushell/nushell.github.io/pull/2273)
- [Custom command attributes, nushell PR #14906](https://github.com/nushell/nushell/pull/14906)
