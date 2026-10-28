# nusage

Typed Nushell commands from usage-annotated scripts, and typed wrappers from usage specs of
binaries.
Early development.

- `nusage/`: the tool. `nusage --help` for the CLI, `fixtures/` for the hand-written modules
  the generator reproduces and the contract a script relies on, `cargo doc --workspace
  --no-deps` for the crates.
- `mise/`: the module for mise, generated from mise's own spec and the overlays there.
- `clap/`: the spec of a binary that ships none, read from the clap command its crate builds,
  once per version. Its README says how to add a binary.
- `jj/`: the module for jj, generated from the committed spec `clap/` reads from jj-cli;
  `mise run //jj:spec` writes it again for a new jj.
- `schemas/`: shared development scripts for output-schema conformance checks; the first
  reviewed schemas and fixtures are under `mise/`. See `schemas/README.md`.

Install the development tools with `mise install --monorepo`; `mise tasks --all` lists the
tasks, which run through the nusage built here. `mise run //mise:install` generates the mise
module and has every new interactive Nushell session load it, as `mise run //jj:install` does
the jj module. `mise dot apply` links the global fragment that installs the released nusage
for the user, with the `nu` it runs scripts in and the `usage` its completions run. The repository uses a single `main` bookmark with a colocated Git/Jujutsu checkout.
