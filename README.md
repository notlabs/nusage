# nusage

Typed Nushell commands from usage-annotated scripts, and typed wrappers from usage specs of
binaries.
Early development.

- `nusage/`: the tool. `nusage --help` for the CLI, `fixtures/` for the hand-written modules
  the generator reproduces and the contract a script relies on, `cargo doc --workspace
  --no-deps` for the crates.
- `catalog/`: the wrappers for other tools, a Nushell module package per tool under
  `catalog/lib/`, generated from each tool's own spec and the overlays beside it. With
  `catalog/lib` on `$NU_LIB_DIRS`, `use mise *` names mise's commands as mise does.
  `catalog/mise.toml` declares the entries and `catalog/tasks/catalog.nu` the layout.

Install the development tools with `mise install --monorepo`; `mise tasks --all` lists the
tasks, which run through the nusage built here. `mise run //catalog:install` has every new
interactive Nushell session load the catalog's modules. `mise dot apply` links the global
fragment that installs the released nusage for the user, with the `nu` it runs scripts in and
the `usage` its completions run. The repository uses a single `main` bookmark with a colocated
Git/Jujutsu checkout.
