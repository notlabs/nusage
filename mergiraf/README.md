# mergiraf

[Mergiraf](https://mergiraf.org) is the structural merge tool `jj resolve` runs in this
repository: it parses the three sides of a conflict with tree-sitter and merges the trees, so
two commands added to the same module, or two keys to the same record, merge without a word
from anyone, and what it cannot merge keeps its markers. Mergiraf does not know Nushell yet,
so it is built here from its published source with the patches beside it applied.

- `mise.toml`: the source, pinned as a mise tool with its checksum, and the tasks.
  `mise run //mergiraf:build` applies the patches and builds the release binary into the repository's
  `.bin`, where the root's `[env] _.path` finds it. `//mergiraf:test` builds the same patched
  source with Cargo's dev profile into `target/mergiraf-test/mergiraf`, then merges all 11
  Nushell cases with the flags `jj resolve` uses and checks the exact output and exit code.
  Tests leave the release binary in `.bin` alone. Cargo and Mr Boxington reuse builds by
  their source, toolchain and platform identity. `//mergiraf:check` holds the patches to
  the pinned source without building; `//mergiraf:check:platform` runs it on both CI platforms.
  In GitHub Actions a failure of any of them is an annotation on the file at fault, a patch or this configuration, through the module at `.mise/lib/actions.nu` that
  the lint and the catalog's check annotate with too.
- `patches/`: the changes, as a series `git format-patch` wrote against the source as
  published, applied in name order.
  - `0001-Add-Nushell-support.patch`: the language profile, its test cases under
    `tests/data/nushell/working/` in Mergiraf's layout, and the line in its list of languages.
    Written to be proposed upstream as it is.
  - `0002-Print-the-leading-source-of-mixed-trees.patch`: a fix in Mergiraf's printer for
    grammars whose element lists start before their first element, as tree-sitter-nu's record
    and list bodies do; without it a merged record lost the newline after its opening brace.
    Mergiraf's own suite passes with it. Written to be proposed upstream as it is.
  - `0003-Depend-on-tree-sitter-nu-from-its-repository.patch`: the grammar as a git
    dependency, pinned to a revision, because it is not on crates.io. Upstream takes grammars
    from crates.io only, so this one is replaced there by a one-line dependency once the
    grammar is published; publishing it is the first step of proposing the other two.
- `mise.lock`: the pinned source, as `mise lock` writes it.

The root's `jj.toml` sets `ui.merge-editor` to `mergiraf`, and jj's built-in configuration
of the tool does the rest: it hands Mergiraf the three sides with Git-style markers and reads
its result back, recording as a conflict what came back with markers. `jj resolve
--tool :builtin` or an editor take it from there, and `jj resolve --list` shows what is left.

## What the profile knows

Nushell predeclares the `def`s and `extern`s of a block before parsing its pipelines, so
their order in a script, a module or any block does not matter: they commute, keyed by name.
Whole `use` statements keep their order: two modules can export the same command name,
and the last import then determines which command runs. Concurrent additions at the same
import position stay a conflict, even when the names happen to be distinct. Regression
cases cover colliding imports both at the top level and inside a block.
Record entries commute, keyed by their key, in scripts and in NUON files alike; the named
commands a single `use` imports, `use foo [a b c]`, commute too. Strings, interpolated
strings and the shebang are merged as a whole. Everything else
keeps its order and a concurrent change to the same place in it stays a conflict: pipelines,
`let`, `const` and `alias`, since each may depend on the one before; lists and tables, since
their order is data; match arms, since the first match wins; command parameters, since the
grammar does not tell a flag from a positional by node kind. Two sides adding the same key to
a record with different values stay a conflict too.

The grammar's separators between entries are hidden tokens, so when both sides add to the
same record Mergiraf separates the additions with a newline, where the record was written on
one line too; `jj fix` runs nufmt over the `.nu` files afterwards. The grammar is a work in
progress: of this repository's Nushell files three in a hundred and fourteen do not parse,
two generated modules and the fixture harness, and a file Mergiraf cannot parse gets the
ordinary line-based merge, markers and all.

The generated modules under `catalog/lib/*/mod.nu` are compared byte for byte with the
generator's output, so a conflict in one is not merged at all: take either side and run
`mise run //catalog:generate`.

The patches are changes to Mergiraf and are offered under its license, GPL-3.0-only; nothing
of Mergiraf is kept in this repository beyond them.
