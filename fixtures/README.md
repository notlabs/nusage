# Fixtures

Hand-written targets for what nusage will produce. Each fixture is a usage-annotated Nushell
script (or a tree of them), the module a generator must emit for it byte for byte, the `help`
text that module gives, and cases pairing an invocation with the `$usage` record the script
must see. Nothing here is generated; the point is to settle the design in the output before
writing the thing that produces it.

```
fixtures/
  verify.nu                      # the harness; `mise run verify-fixtures`
  <name>/
    script.nu                    # a single-command script, or
    <bin>/mod.nu, <bin>/<cmd>.nu # a tree, where directories are groups and files are commands
    expected/<bin>.nu            # the shim module: one `export def` per command
    expected/help.txt            # `help <bin> ...` for the root and every command a case names
    cases/<case>.nuon            # { argv, invoke?, usage }
```

## The contract

A script declares its interface in `#USAGE` header lines (plain usage KDL, so every other usage
consumer can read it), has no `def main`, and reads its arguments from `$usage`:

```nu
{ cmd: [db migrate], args: { target: prod }, flags: { verbose: true, dry_run: true } }
```

- `cmd` is the subcommand path, outermost first; `[]` at the root.
- `args` and `flags` are keyed by the usage name in `snake_case`, like `usage_<name>`.
- **Every declared name is present.** A switch not given is `false`, a valued flag or optional
  positional not given is `null`, a variadic or repeatable one is `[]`, a count flag is `0`.
  usage's own output omits what was not given; `$usage` does not, so scripts never need `?`.
- Inherited (`global`) flags come first in `flags`, then the command's own, in declaration order.
- Types are what the Nushell signature says: `<file>` and `<dir>` positionals are `path`,
  everything else is `string` until a `#NUSAGE type` line (not yet in any fixture) says otherwise.

Two entrypoints deliver that record and a script cannot tell them apart:

| Entrypoint  | How the arguments are typed                   | Where the script runs  |
| ----------- | --------------------------------------------- | ---------------------- |
| shim        | by the `def` signature in `expected/<bin>.nu` | the caller's engine    |
| interpreter | by usage's parser on argv, handed in as NUON  | a fresh `nu` process   |

The fixture scripts return `$usage` itself so the cases can assert it directly.

## The shim

```nu
# Run migrations
export def "db migrate" [
    target: string@[dev staging prod],  # Target environment
    --verbose (-v),                     # Say more
    --dry-run,                          # Plan without applying
] {
    let usage = {
        cmd: [db migrate]
        args: {target: $target}
        flags: {verbose: $verbose, dry_run: $dry_run}
    }
    $in | run ../mycli/db/migrate.nu
}
```

Rules the hand-written modules follow, which a generator must reproduce:

- The module is named after the spec's `bin`, so `use expected/mycli.nu` gives `mycli`,
  `mycli db`, `mycli db migrate`. The root command is `export def main`; a group is a plain
  `export def db` so that `mycli db` on its own runs the group's `mod.nu`.
- `about` becomes the doc comment above the `def`; `help` on an arg or flag becomes the trailing
  comment on its line. `help` shows both.
- `choices` become an inline completer, `string@[dev staging prod]`. Nushell does not validate
  against it; that stays with the runtime check usage performs.
- A repeatable flag (`var=#true`) is `list<string> = []`, a count flag (`count=#true`) is
  `int = 0`, because Nushell flags cannot repeat. A case whose argv repeats a flag carries the
  Nushell spelling in `invoke`.
- A `default=` is written as a Nushell default on the parameter.
- The body is always `$in | run <path>`. `run` (Nushell 0.114+) executes the script in an
  isolated scope: the script sees `$usage` and `$in`, and its `$env` changes and variables do
  not leak back. `source` was wrong here: it splices the script into the module's scope. The
  path is relative to the module file, which is how `run` resolves it, and it is read at parse
  time, so a script edit is picked up by re-`use`-ing the module (or `run --full-reparse`).
- Layout is whatever nufmt (pinned in `mise.toml`) produces: one parameter per line with trailing
  commas and aligned comments, the record one field per line without commas. `mise run fmt-check`
  holds the expected modules and the harness to it, so a generator can target nufmt's output
  rather than a layout of its own.

## The interpreter prelude

What `nusage script.nu <argv>` will run once it exists, and what the harness runs today:

```
NUSAGE_ARGS='<nuon>' nu [--stdin] -c 'let usage = ($env.NUSAGE_ARGS | from nuon); $in | run /abs/script.nu'
```

The record travels in an environment variable so no user data is ever spliced into a command
line. `--stdin` is passed only when stdin is not a terminal.

## Running

```
mise run verify-fixtures          # all fixtures, against the pinned nu
nu fixtures/verify.nu fixtures/minimal
mise run update-fixture-help      # after changing a header or a shim on purpose
```

The harness runs each case through both entrypoints and compares the returned record with
`usage`, then compares `help` output with `expected/help.txt`. A failing row prints the expected
and actual records.

## What is deliberately not here yet

`#NUSAGE type` and `#NUSAGE output` (typed coercions, `export type` aliases, declared output
types), `default`/`env` fallbacks resolved by usage rather than by the signature, `requires` and
`conflicts` relationship checks, `$in`-consuming scripts, and anything needing 0.117 syntax.
Each wants its own fixture once the contract above has been looked at.
