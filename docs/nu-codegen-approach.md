# Generating Nushell code from usage specs

Third note in the series. The pivot: skip the plugin for now and generate Nushell
source from usage specs. Two questions: which Nushell constructs to target for which
case, and how to emit them in Rust in a way that is not ad hoc string building.

Checked against Nushell `main` 36c057c (0.117 line) and usage f357a6c.

## 1. Which construct for which case

Nushell has three declaration forms that matter here. They are not interchangeable.

### `def`: a command with a body

```nu
@example "migrate prod" { mycli db migrate prod --dry-run }
export def "db migrate" [
    target: string@[dev staging prod],
    --dry-run,
    --limit (-n): int = 10,
]: nothing -> table<name: string, applied: bool> {
    let usage = { cmd: "db migrate", args: { target: $target }, flags: { dry_run: $dry_run, limit: $limit } }
    source /abs/mycli/db/migrate.nu
}
```

This is the target for scripts-as-subcommands with a `$usage` value. The body is
five lines of boilerplate: build the record from the parameters, `source` the script.
`source` splices the parsed file into the enclosing scope, so the script sees
`$usage` and `$in`, runs in the caller's engine, and its last pipeline is the
command's output. Nothing crosses a process boundary; closures are legal arguments;
`--env` is available when a script should mutate the caller's environment.

Signature syntax to generate: `name: type`, `name?: type` (optional), `...rest: list<type>`,
`--flag`, `--flag (-f)`, `--flag: type`, `= default` (any NUON literal),
`type@completer-command` or `type@[a b c]` (an inline list; `parse_completer` accepts a
string naming a command or a list of strings), `: in -> out` or `: [in1 -> out1, in2 -> out2]`.

### `extern`: a signature for an external binary

```nu
@structured [--format=json] { from json }
export extern --strict "mycli build" [
    target: string@[debug release],
    --output (-o): path,
    --release,
]: nothing -> record<ok: bool>
```

This is the target for wrapping an existing CLI that has a usage spec (the
`--usage-spec` / `__usage_spec__` convention, or a `.usage.kdl` next to it). There is no
body: calling `mycli build` runs the `mycli` binary from `PATH` with argv rendered by
Nushell. That is the lossy path by construction, so `extern` is right for binaries and
wrong for scripts that should receive `$usage`. Two new modifiers on this line:
`--strict` makes an undeclared flag a parse error (`rejects_unknown_flags`), and
`@structured [args] { decode }` adds the args and runs the decode block only when
the output is consumed by Nushell, leaving terminal output alone. Map usage
`output "json" framing="json"` with its `select` flag onto `@structured`, and the
schema onto the extern's output type.

A script on `PATH` with a `#!/usr/bin/env nu` shebang could also be the target of an
`extern`, but then it receives argv, which is exactly what the `$usage` design avoids.

### `type`: a named type alias

```nu
export type MigrationRow = record<name: string, applied: bool>
export def "db migrate" [...]: nothing -> list<MigrationRow> { ... }
```

Only reachable through generated code (it is parser state, never on the plugin
protocol). Generate one per declared output schema or `#NUSAGE output`, so `help`
and the LSP show a name rather than a structural type.

### Attributes worth emitting

`@example "desc" { code } --result value`, `@search-terms a b`, `@category name`,
`@deprecated "msg"`, `@complete <command>` or `@complete external` (command-wide
completer; the latter delegates to the external's own completion), `@structured`
(extern only). usage `help`/`long_help` become the `#` doc comment above the
declaration, which is what `help` renders.

### Module layout

One `mod.nu` per spec with `export def "a b c"` multi-word names is the simplest
and works for any depth. Nested `export module` blocks or a directory with
`mod.nu` plus submodule files are equivalent and only matter for how the user
imports (`use mycli` vs `use mycli db`). For the scripts case, the generated module
lives in a cache directory and `source`s the user's scripts by absolute path, so the
user's own `mycli/` tree stays free of generated files.

### What changes versus the plugin plan

The engine coupling you were worried about mostly disappears. Generated code
depends on 0.117 *syntax*, not on any Nushell crate at runtime. The generator itself
can be dependency-free, and validation can run through the pinned `nu` binary.
The remaining gaps are the parse-time ones: the relationship rules usage enforces
(`conflicts`, `requires`, `required_if`, groups, `validate`) still need a runtime
check, which in generated code is a call in the body to a small checker, either a
Nushell function shipped alongside the module or a `usage`/`nusage` binary.

## 2. How to emit it

### What Nushell gives you

- `nuon::to_nuon(&Value, config)` (`crates/nuon`): the canonical way to render any
  literal: defaults, `@example --result` values, the `$usage` record skeleton. Covers
  every value kind except closures and custom values. Use it for every literal and
  never hand-escape a value.
- `nu_utils::{needs_quoting, escape_quote_string, as_raw_string}`
  (`crates/nu-utils/src/quoting.rs`): the quoting rules the engine itself uses for
  bare words and strings. The decision "does `git status` need quotes as a command
  name" is theirs to make.
- `impl Display for Type` and `impl Display for SyntaxShape` (`crates/nu-protocol`):
  render `record<x: int, y: int>`, `list<string>`, `oneof<int, string>` exactly as
  the parser reads them. If you build `Type` values, printing is solved.
- No AST-to-source printer exists for declarations, and no stable formatter: `nufmt`
  is an unstable snapshot package and Topiary needs a query file for tree-sitter-nu.
  Plan to produce well-formatted output directly rather than format afterwards.
- `nu-parser` is a library: `nu_cmd_lang::create_default_context()`, a
  `StateWorkingSet`, `nu_parser::parse(...)`, then inspect `working_set.parse_errors`.
  That is a round-trip test of every generated file without spawning a process. It
  pulls `nu-engine` as a dev-dependency, which is acceptable in tests. The `nu-check`
  command does the same from the pinned binary for CI without any crate dependency.

### The pattern: a typed syntax model, then one printer

Model the subset of Nushell you emit as plain Rust data, and give it exactly one
rendering path. The structure carries the invariants (a rest parameter is last,
an `extern` has no body, a `@structured` only sits on an `extern`, an inline
completer list is a list of bare words), and the printer owns every quoting and
layout decision.

```rust
pub struct Module { pub items: Vec<Item> }

pub enum Item {
    TypeAlias { export: bool, name: Ident, ty: Type },
    Def(Decl),
    Extern(Decl),
}

pub struct Decl {
    pub export: bool,
    pub doc: Vec<String>,                 // "# ..." lines above the declaration
    pub attrs: Vec<Attr>,
    pub modifiers: Modifiers,             // env, wrapped (def); strict (extern)
    pub name: CommandName,                // quoted by the printer when needed
    pub params: Params,                   // required, optional, rest, flags: ordered by construction
    pub io: Vec<(Type, Type)>,
    pub body: Option<Body>,               // None for extern, enforced by Item
}

pub enum Attr {
    Example { desc: String, code: Code, result: Option<Literal> },
    SearchTerms(Vec<String>),
    Category(String),
    Deprecated(Option<String>),
    Complete(Completer),
    Structured { args: Vec<String>, decode: Code },
}

pub struct Param {
    pub name: Ident,
    pub shape: Shape,                     // string, int, path, list<...>, record<...>, Alias(name)
    pub completer: Option<Completer>,     // Command(name) | List(Vec<String>)
    pub default: Option<Literal>,         // rendered with nuon
}

pub enum Literal { Nuon(String) }         // produced only by nuon::to_nuon
pub enum Code { Verbatim(String) }        // bodies are a separate, small concern
```

`Ident` and `CommandName` are newtypes whose constructors validate (no leading `-`,
flag names map to `snake_case` variables, reserved words like `type` are refused or
renamed with an explicit rule). Once a value is inside the model it is known to
print correctly, so the printer never has to defend against bad input.

For the printer, two reasonable choices:

- **`Display` with a small indent writer.** Fine for this subset. Signatures are the
  only thing that needs line-breaking, and a fixed rule (one parameter per line when
  more than two, trailing commas) is readable and stable for snapshots.
- **The `pretty` crate** (Wadler-style documents) when you want signatures that fold
  onto one line when short and break when long. Worth it if the output is meant to
  be read often; overkill if it is a cache the user never opens.

Bodies are where templating earns its place. The `$usage` shim and the
`@structured` decode blocks are small, parametric, and better written as a template
than as an AST. `genco` is the strongest fit here: `impl_lang!` defines a language
in a few lines, `quote!` handles indentation and interpolation, and the result is a
`Tokens` value that slots into `Code::Verbatim` through one function. Tera (which
usage-lib already uses for its docs) or minijinja work too; they are strings with
better ergonomics, so keep every identifier and literal that reaches them already
rendered by the model, never raw.

What to avoid: writing the whole file through a template. Templates have no idea
what a Nushell identifier is, and every escaping bug from the first analysis's
"lossy argv" category comes back as a quoting bug in generated code.

### Tests that make it safe to change

1. **Snapshot** every generated module with `insta`, one spec fixture per feature
   (multi-word names, optional positionals, rest, short flags, defaults, choices,
   `@structured`, type aliases).
2. **Round-trip parse** every snapshot through `nu-parser` and assert no parse
   errors; also assert the parsed `Signature` equals the one you intended to emit,
   which catches "it parsed, but as something else".
3. **Run** one fixture through the pinned `nu` binary: `use` the module, call
   `help mycli build`, call the command with `--dry-run`, check `$usage` came
   through as a record. mise already pins the binary; move the pin to 0.117 when it
   ships, or point it at a nightly until then.

### Where it could live

usage-lib already has generator targets (`lib/src/sdk/typescript`,
`lib/src/sdk/python`, the completion scripts, Markdown and manpages) with a
hand-rolled `Writer` and snapshot tests. A `usage generate sdk --language nu` target
that emits `extern` + `@structured` from a spec would fit that catalogue and is a
plausible upstream contribution, since it needs nothing beyond the spec. The
`$usage` shim with `def` + `source` and the `#NUSAGE` type directive are nusage's
own and should stay here; they are the part usage has no vocabulary for.
