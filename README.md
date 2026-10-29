# nusage

Typed Nushell commands from usage-annotated scripts, and typed wrappers from usage specs of
binaries.
Early development.

- `nusage/`: the tool. `nusage --help` for the CLI, `fixtures/` for the hand-written modules
  the generator reproduces and the contract a script relies on, `cargo doc --workspace
  --no-deps` for the crates. Two of them stand on their own: `nushell-schema`, the Nushell
  dialect of JSON Schema, and `openapi-usage`, an OpenAPI document as a usage spec with the
  HTTP mapping beside it.
- `catalog/`: the wrappers for other tools, a Nushell module package per tool under
  `catalog/lib/`, generated from each tool's spec, the schemas of its outputs and the
  overlays beside it. With `catalog/lib` on `$NU_LIB_DIRS`, `use mise *` names mise's
  commands as mise does, and `use jj *` jj's. `catalog/mise.toml` declares the entries and
  `catalog/tasks/catalog.nu` the layout; `catalog/clap/` reads the spec of a binary whose
  crate builds its clap command, as jj's is, and `catalog/schemas/` runs an output-schema
  suite, as both packages keep one.
- `intent/`: the direction, as claims that are checked where they can be; nothing there is
  settled.

An editor that runs `nusage lsp` where it would run `nu --lsp` checks a script nusage runs as
nusage runs it: Nushell knows `$usage` and its type, and holds each call of another script to
that script's header. Or leave the editor as it is and opt in through mise: after `mise dot
apply`, with `MISE_ENV=nusage-lsp` in the environment the editor starts from, every `nu`
mise starts is `nusage nu`, which serves `nusage lsp` when asked for `nu --lsp` and is
Nushell for anything else. `MISE_ENV=nusage-lsp,nusage-kakehashi` installs
[kakehashi](https://github.com/atusy/kakehashi) too, and `nu --lsp` then also highlights a
script's header as usage KDL and the scripts its `run=` names as Nushell or sh.

Install the development tools with `mise install --monorepo`; `mise tasks --all` lists the
tasks, which run through the nusage built here. `mise run //catalog:install` has every new
interactive Nushell session load the catalog's modules. `mise dot apply` links the global
fragment that installs the released nusage for the user, with the `nu` it runs scripts in and
the `usage` its completions run. The repository uses a single `main` bookmark with a colocated
Git/Jujutsu checkout.
