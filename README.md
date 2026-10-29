# nusage

Typed Nushell commands from usage-annotated scripts, and typed wrappers from usage specs of
binaries.
Early development.

- `nusage/`: the tool. `nusage --help` for the CLI, `fixtures/` for the hand-written modules
  the generator reproduces and the contract a script relies on, `cargo doc --workspace
  --no-deps` for the crates.
- `catalog/`: the wrappers for other tools, a Nushell module package per tool under
  `catalog/lib/`, generated from each tool's spec, the schemas of its outputs and the
  overlays beside it. With `catalog/lib` on `$NU_LIB_DIRS`, `use mise *` names mise's
  commands as mise does, and `use jj *` jj's. `catalog/mise.toml` declares the entries and
  `catalog/tasks/catalog.nu` the layout; `catalog/clap/` reads the spec of a binary whose
  crate builds its clap command, as jj's is, and `catalog/schemas/` runs an output-schema
  suite, as both packages keep one.

An editor that runs `nusage lsp` where it would run `nu --lsp` checks a script nusage runs as
nusage runs it: Nushell knows `$usage` and its type, and holds each call of another script to
that script's header.

Install the development tools with `mise install --monorepo`; `mise tasks --all` lists the
tasks, which run through the nusage built here. `mise run //catalog:install` has every new
interactive Nushell session load the catalog's modules. `mise dot apply` links the global
fragment that installs the released nusage for the user, with the `nu` it runs scripts in and
the `usage` its completions run. The repository uses a single `main` bookmark with a colocated
Git/Jujutsu checkout.
