# mergiraf

[Mergiraf](https://mergiraf.org) is the structural merge tool `jj resolve` runs in this
repository: it parses the three sides of a conflict with tree-sitter and merges the trees, so
two commands added to the same module, or two keys to the same record, merge cleanly, and what
it cannot merge keeps its markers.
It does not know Nushell yet, so it is built here from its published source,
pinned in `mise.toml`, with the patches under `patches/` applied in name order;
each patch's message says what it changes, and whether it is meant for upstream.
The first says what the Nushell profile merges and what stays a conflict.

When both sides add to a record written on one line,
Mergiraf separates the additions with a newline; `jj fix` runs nufmt afterwards.
A file the grammar cannot parse gets the ordinary line-based merge.
A conflict in a generated `catalog/lib/*/mod.nu` is not merged:
take either side and run `mise run //catalog:generate`.

The patches are offered under Mergiraf's license, GPL-3.0-only;
nothing else of Mergiraf is kept in this repository.
