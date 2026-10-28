# nusage

Typed Nushell commands from usage-annotated scripts, and typed wrappers from usage specs of
binaries.
Early development.

- `nusage/`: the tool. `nusage --help` for the CLI, `fixtures/` for the hand-written modules
  the generator reproduces and the contract a script relies on, `cargo doc --workspace
  --no-deps` for the crates.
- `mise/`: the module for mise, generated from mise's own spec and the overlays there.

Install the development tools with `mise install --monorepo`; `mise tasks --all` lists the
tasks, which run through the nusage built here. `mise dot apply` links the global fragment that
installs the released nusage for the user. The repository uses a single `main` bookmark with a colocated Git/Jujutsu checkout.
