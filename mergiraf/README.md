# mergiraf

[Mergiraf](https://mergiraf.org) is the structural merge tool `jj resolve` runs in this
repository: it parses the three sides of a conflict with tree-sitter and merges the trees, so
two commands added to the same module, or two keys to the same record, merge cleanly, and what
it cannot merge keeps its markers. It does not know Nushell yet, so it is built here from its
published source, pinned in `mise.toml`, with the patches under `patches/` applied in name
order. `mise run //mergiraf:build` builds it into the repository's `.bin`, and the root's
`jj.toml` sets `ui.merge-editor` to `mergiraf`.

- `0001-Add-Nushell-support.patch`: the language profile and its test cases, written to be
  proposed upstream.
- `0002-Print-the-leading-source-of-mixed-trees.patch`: a fix in Mergiraf's printer for
  grammars whose element lists start before their first element, as tree-sitter-nu's record
  and list bodies do; without it a merged record lost the newline after its opening brace.
  Also written to be proposed upstream.
- `0003-Depend-on-tree-sitter-nu-from-its-repository.patch`: the grammar as a git dependency,
  since it is not on crates.io, which upstream requires; publishing the grammar comes before
  proposing the other two.

## What the profile merges

The `def`s and `extern`s of a block commute, keyed by name, since Nushell declares them before
it parses the block. Record entries commute, keyed by their key, in scripts and NUON files, and
so do the names one `use` imports, `use foo [a b c]`. Whole `use` statements keep their order,
since the last import of a name wins, so concurrent additions at the same place stay a
conflict. Everything else keeps its order: pipelines, `let`, `const` and `alias`, each of
which may depend on the one before; lists and tables, whose order is data; match arms, where
the first match wins; command parameters, which the grammar does not tell apart by kind. Two
sides adding the same key to a record with different values stay a conflict.

When both sides add to a record written on one line, Mergiraf separates the additions with a
newline; `jj fix` runs nufmt afterwards. A file the grammar cannot parse gets the ordinary
line-based merge. A conflict in a generated `catalog/lib/*/mod.nu` is not merged: take either
side and run `mise run //catalog:generate`.

The patches are offered under Mergiraf's license, GPL-3.0-only; nothing else of Mergiraf is
kept in this repository.
