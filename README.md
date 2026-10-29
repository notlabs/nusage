# nusage

Typed Nushell commands from usage-annotated scripts, and typed wrappers from usage specs of
binaries.
Early development.

- `nusage/`: the tool. `nusage --help` for the CLI, `fixtures/` for the hand-written modules
  the generator reproduces and the contract a script relies on, `cargo doc --workspace
  --no-deps` for the crates.
- `mise/`: the module for mise, generated from mise's own spec and the overlays there, with
  the schemas of its outputs under `schemas/`.
- `jj/`: the module for jj, generated from the spec `clap/` reads from jj-cli, committed
  since writing it compiles jj-cli, with the schemas of its JSON outputs under `schemas/`;
  `mise run //jj:spec` writes the spec for a new jj.
- `clap/`: the spec of a binary that ships none, read from the clap command its crate
  builds. Its README says how to add a binary.
- `schemas/`: the runner of an output-schema suite and the overlay it declares, shared by
  the modules. Its README says what a suite is.

An editor that runs `nusage lsp` where it would run `nu --lsp` checks a script nusage runs as
nusage runs it: Nushell knows `$usage` and its type, and holds each call of another script to
that script's header, and each `mise run` of a task whose file is one. Or leave the editor as it is and opt in through mise: after `mise dot
apply`, with `MISE_ENV=nusage-lsp` in the environment the editor starts from, every `nu`
mise starts is `nusage nu`, which serves `nusage lsp` when asked for `nu --lsp` and is
Nushell for anything else. `MISE_ENV=nusage-lsp,nusage-kakehashi` installs
[kakehashi](https://github.com/atusy/kakehashi) too, and `nu --lsp` then also highlights a
script's header as usage KDL and the scripts its `run=` names as Nushell or sh. A project's
own `[wrappers.nu]` takes the place of this one; a project that wants a wrapper of its own,
for its environment, names nusage the same way, `command = "nusage"` and `args = ["nu"]`
beside its `env`, and keeps nusage's server, which is Nushell for anything but `--lsp`.

Install the development tools with `mise install --monorepo`; `mise tasks --all` lists the
tasks, which run through the nusage built here. `mise run //mise:install` and `mise run
//jj:install` generate a module and have every new interactive Nushell session load it. `mise
dot apply` links the global fragment that installs the released nusage for the user, with
the `nu` it runs scripts in and the `usage` its completions run. The repository uses a single
`main` bookmark with a colocated Git/Jujutsu checkout.
