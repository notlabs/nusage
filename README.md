# nusage

Typed Nushell commands from usage-annotated scripts, and typed externs from usage specs.
Early development.

- `nusage --help`: the CLI.
- `fixtures/`: the hand-written modules the generator reproduces, and the contract a script
  relies on.
- `cargo doc --workspace --no-deps`: the crates.
- `mise tasks`: the developer workflow.

Install the development tools with `mise install`. The repository uses a single `main`
bookmark with a colocated Git/Jujutsu checkout.
