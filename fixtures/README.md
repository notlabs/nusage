# Fixtures

Hand-written targets for what nusage will produce. Each fixture is a usage-annotated Nushell
script (or a tree of them), the module a generator must emit for it byte for byte, the parsed
signatures that module yields, and cases pairing an invocation with the `$usage` record the
script must see. Nothing here is generated; the point is to settle the design in the output
before writing the thing that produces it.

```
fixtures/
  verify.nu                      # the harness; `mise run verify-fixtures`
  <name>/
    script.nu                    # a single-command script, or
    <bin>/mod.nu, <bin>/<cmd>.nu # a tree: directories are groups, files are commands, or
    <bin>.usage.kdl              # a binary's spec: the extern target
    fixture.nuon                 # optional: { requires_nu } to skip the Nushell checks below it
    expected/<bin>.nu            # the module: one `export def` or `export extern` per command
    expected/signatures.nuon     # `scope commands` for the root and every command a case names
    cases/<case>.nuon            # { argv, invoke?, usage, output?, complete? } or { cmd, complete? }
```

## The contract

A script declares its interface in `#USAGE` header lines (usage KDL, unchanged, so every usage
consumer reads it), has no `def main`, and reads its arguments from `$usage`:

```nu
{cmd: [db migrate], args: {target: prod}, flags: {verbose: true, dry_run: true, since: null, limit: 10}}
```

- `cmd` is the subcommand path, outermost first; `[]` at the root.
- `args` and `flags` are keyed by the usage name in `snake_case`, like `usage_<name>`.
- **Every declared name is present.** A switch not given is `false`, a valued flag or optional
  positional not given is `null`, a variadic or repeatable one is `[]`, a count flag is `0`, a
  declared `default` applies.
- Inherited (`global`) flags come first in `flags`, then the command's own, in declaration order.
- **Types come from KDL type annotations**, which usage parses and ignores:
  `arg (datetime)"<since>"`, `flag "--limit" { arg (int)"<n>" }`. Nushell type syntax is the
  annotation, quoted when it has `<`, `:` or spaces: `("list<string>")`. Without an annotation
  a value is `string`, `<file>`/`<dir>` are `path`, switches `bool`, variadics `list<string>`,
  counts `int`.
- **The output is declared the same way**, on the `output` node:
  `output ("list<string>")"nuon" default=#true`. `framing` and `media_type` describe how the
  value leaves the engine and are inert in-session.

Two entrypoints deliver that record and a script cannot tell them apart:

| Entrypoint  | How the arguments are typed                   | Where the script runs  |
| ----------- | --------------------------------------------- | ---------------------- |
| shim        | by the `def` signature in `expected/<bin>.nu` | the caller's engine    |
| interpreter | by usage's parser on argv, handed in as NUON  | a fresh `nu` process   |

Contract scripts return `$usage` so cases can assert it directly; a provider script returns a
value, and its case carries that under `output`.

## The shim

```nu
alias "attr usage" = echo

# Run migrations
@usage 'arg "<target>" help="Target environment" { choices run="./targets.nu" }'
@usage 'flag "--since" help="Only migrations after this time" { arg (datetime)"<since>" }'
export def "db migrate" [
    target: string@"db targets",  # Target environment
    --verbose (-v),               # Say more
    --since: datetime,            # Only migrations after this time
] {
    let usage = {
        cmd: [db migrate]
        args: {target: $target}
        flags: {verbose: $verbose, since: $since}
    }
    $in | run ../mycli/db/migrate.nu
}
```

Rules the hand-written modules follow, which a generator must reproduce:

- The module is named after the spec's `bin`, so `use expected/mycli.nu` gives `mycli`,
  `mycli db`, `mycli db migrate`. The root command is `export def main`; a group is a plain
  `export def db` so that `mycli db` on its own runs the group's `mod.nu`.
- Comments are Nushell's documentation channel, so `help` and the LSP show them: `about`
  is the comment line above the `def` (the description), `long_about` would follow it as a
  second paragraph (the extra description), and `help` on an arg or flag is the trailing
  comment on its line (the parameter description).
- One module-local `alias "attr usage" = echo` makes `@usage` a constant attribute. It is not
  exported and does not reach the user's scope.
- **Every header node except `name`, `bin` and `about` is copied verbatim into a `@usage`
  attribute** above the `def`, in header order. `scope commands` returns them as
  `[usage, '<the node>']` rows, so usage-lib can parse them back and nothing in the header is
  lost, annotations included.
- A KDL type annotation becomes the parameter's type; an `output` annotation becomes the
  command's output type.
- Static `choices` become an inline completer, `string@[tar zip]`; Nushell does not validate
  against it.
- `choices run="./targets.nu"` naming a sibling script in the tree makes that sibling command
  the parameter's completer: `target: string@"db targets"`. A provider declares no flags and
  is emitted without the inherited globals, because Nushell binds only the token positional
  when it calls a completer and any flag variable in the body would be unbound (verified on
  0.116.1; a provider header with its own flags is a generation error). The generator checks
  the provider's declared output against what a completer may return (`list<string>` or a
  list of completion records). Providers are emitted before the commands that name them.
- A repeatable flag (`var=#true`) is `list<string> = []`, a count flag (`count=#true`) is
  `int = 0`, because Nushell flags cannot repeat. A case whose argv repeats a flag carries the
  Nushell spelling in `invoke`.
- The body is always `let usage = {...}` then `$in | run <path>`. `run` executes the script in
  an isolated scope that still sees `$usage` and `$in`; nothing leaks back. The path is relative
  to the module file.
- Layout is whatever nufmt (pinned in `mise.toml`) produces. `mise run fmt-check` holds the
  modules and the harness to it, so a generator can target nufmt's output.

## The extern module

A `<bin>.usage.kdl` describes a binary Nushell runs from `PATH`, so the module is `extern`s,
one per `cmd`, each carrying the binary's full name (`demo`, `demo install`) and imported with
`use demo.nu *`. The same rules apply with these differences:

- `extern --strict`, so an undeclared flag is a parse error, as a usage spec means it to be.
- Defaults are not written: a binary applies its own, and `extern` would ignore them.
- An `output` with `framing="json"` or `"jsonl"` becomes `@structured [args] { from json }` or
  `{ from json --objects }`. The args select it: a `select="--json"` on the output is that
  switch, a `select "--format"` on the command is `--format=json`; a default or sole structured
  output needs none. Its type annotation is the extern's output type.
- `complete "name" run="..."` and `choices run="..."` become a non-exported helper,
  `def "complete name" [] { ^sh -c "..." | lines }`, with `parse "{value}:{description}"` when
  `descriptions=#true`, and the parameter names the helper. A binary cannot be a completer, so
  here the helper is the only way.
- `extern --strict` and `@structured` are Nushell 0.117 syntax; `fixture.nuon` says so and the
  harness skips the fixture's Nushell checks on an older version. The Rust test still holds the
  generator to the expected module.

## The interpreter prelude

What `nusage script.nu <argv>` will run once it exists, and what the harness runs today:

```
NUSAGE_ARGS='<nuon>' nu [--stdin] -c 'let usage = ($env.NUSAGE_ARGS | from nuon); $in | run /abs/script.nu'
```

## Running

```
mise run verify-fixtures               # all fixtures, against the pinned nu
nu fixtures/verify.nu fixtures/minimal
mise run update-fixture-signatures     # after changing a header or a shim on purpose
```

Per case the harness runs the shim and the interpreter and compares the returned value, asks
for completions where the case says `complete`, and finally compares the parsed signatures and
attributes of every named command with `expected/signatures.nuon`. A failing row prints the
expected and actual values.

## Not here

`mount` (rejected at assembly), `export type` aliases (0.117), `$in`-consuming scripts,
`choices env=`, and `choices run=` on a script naming anything but a sibling `.nu` provider.
