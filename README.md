# nusage

Typed Nushell commands from usage-annotated scripts, and typed wrappers from usage specs of
binaries.
Early development.

- `nusage/`: the tool. `nusage --help` for the CLI, `fixtures/` for the hand-written modules
  the generator reproduces and the contract a script relies on, `cargo doc --workspace
  --no-deps` for the crates. Two of them stand on their own: `nushell-schema`, the Nushell
  dialect of JSON Schema, and `openapi-usage`, an OpenAPI document as a usage spec with the
  HTTP mapping beside it.
- `mise/`: the module for mise, generated from mise's own spec and the overlays there, with
  the schemas of its outputs under `schemas/`.
- `jj/`: the module for jj, generated from the spec `clap/` reads from jj-cli, committed
  since writing it compiles jj-cli, with the schemas of its JSON outputs under `schemas/`;
  `mise run //jj:spec` writes the spec for a new jj.
- `clap/`: the spec of a binary that ships none, read from the clap command its crate
  builds. Its README says how to add a binary.
- `schemas/`: the runner of an output-schema suite and the overlay it declares, shared by
  the modules. Its README says what a suite is.

Install the development tools with `mise install --monorepo`; `mise tasks --all` lists the
tasks, which run through the nusage built here. `mise run //mise:install` and `mise run
//jj:install` generate a module and have every new interactive Nushell session load it. `mise
dot apply` links the global fragment that installs the released nusage for the user, with
the `nu` it runs scripts in and the `usage` its completions run. The repository uses a single
`main` bookmark with a colocated Git/Jujutsu checkout.
