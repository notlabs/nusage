# nusage

Typed Nushell commands from usage-annotated scripts. Early development.

A Nushell script declares its interface in a [usage](https://usage.jdx.dev) header, has no
`def main`, and reads its arguments from `$usage`. nusage generates a module that defines one
typed command per script, with completions, help and the header carried along as attributes,
whose body hands the script its record and `run`s it.

```
nusage generate mycli/ --out mycli.nu    # a tree: mod.nu is the root, x.nu a subcommand
nusage generate greet.nu                 # a single script, module on stdout
nusage spec mycli/                       # the assembled usage spec, as KDL
```

Where things are documented, each next to what it documents:

- `nusage --help` and each subcommand's `--help`: the CLI, from its own usage spec.
- `fixtures/README.md`: the contract between a script, its header and the generated module.
  The fixtures under it are the hand-written targets the generator must reproduce.
- `cargo doc --workspace --no-deps`: the crates. `nusage-spec` reads headers and assembles a
  tree, `nusage-model` makes every usage-to-Nushell decision, `nusage-nu` writes Nushell,
  `nusage` is the CLI and the shim target.
- `mise tasks`: the developer workflow. `mise run check` runs all of it.

Install the development tools with `mise install`. The repository uses a single `main`
bookmark with a colocated Git/Jujutsu checkout.
