# nusage

Typed Nushell commands from usage-annotated scripts, and typed wrappers from usage specs of
binaries.
Early development.

- `nusage/`: the tool. `nusage --help` for the CLI, `fixtures/` for the hand-written modules
  the generator reproduces and the contract a script relies on, `cargo doc --workspace
  --no-deps` for the crates. Two of them stand on their own: `nushell-schema`, the Nushell
  dialect of JSON Schema, and `openapi-usage`, an OpenAPI document as a usage spec with the
  HTTP mapping beside it, which `nusage generate --http` turns into a module that calls the
  service as another calls a binary. `nusage-plugin` is what a Nushell plugin of ours shares:
  a plugin stands for a command line, its commands declared by the same usage spec, so
  `nu_plugin_nusage` serves `nusage validate` inside Nushell with the CLI's signature and
  `nu_plugin_jev` a judgment about a value by TypeSafe AI's model; `mise run
  //nusage:plugins` registers the plugins built here, and `//nusage:plugin-new <name>` stamps
  a new one from `nusage/plugin-template/`.
- `catalog/`: the wrappers for other tools, a Nushell module package per tool under
  `catalog/lib/`, generated from each tool's spec, the schemas of its outputs and the
  overlays beside it. With `catalog/lib` on `$NU_LIB_DIRS`, `use mise *` names mise's
  commands as mise does, and `use jj *` jj's. `catalog/mise.toml` declares the entries and
  `catalog/tasks/catalog.nu` the layout; `catalog/clap/` reads the spec of a binary whose
  crate builds its clap command, as jj's is, and `catalog/schemas/` runs an output-schema
  suite, as both packages keep one.
- `intent/`: the direction, as claims that are checked where they can be; nothing there is
  settled.
- `mergiraf/`: Mergiraf, the structural merge tool `jj resolve` runs here, built from its
  published source with the patches beside it, which teach it Nushell and are written to be
  proposed upstream: `mise run //mergiraf:build`, and `//mergiraf:test` holds the build to
  the cases the patches carry.

Run `nusage inspect script.nu | from json` to read the analyzer's resolved calls and
findings as values, without running the script. The output's contract is
`nusage/schemas/inspection.schema.json`; its command models are the ones `nusage model`
prints. It reports the calls the analyzer resolves, not a complete dependency graph.

An editor that runs `nusage lsp` where it would run `nu --lsp` checks a script nusage runs as
nusage runs it: Nushell knows `$usage` and its type, and holds each call of another script to
that script's header, and each `mise run` of a task whose file is one. Or leave the editor as it is and opt in through mise: after `mise dot
apply`, with `MISE_ENV=nusage-lsp` in the environment the editor starts from, every `nu`
mise starts is `nusage nu`, which serves `nusage lsp` when asked for `nu --lsp` and is
Nushell for anything else. That `nusage` is the released one, so the environment wants a
release that has `nusage nu`: an older one refuses it for every `nu` mise starts.
`MISE_ENV=nusage-lsp,nusage-kakehashi` installs
[kakehashi](https://github.com/atusy/kakehashi) too, and `nu --lsp` then also highlights a
script's header as usage KDL and the scripts its `run=` names as Nushell or sh. A project's
own `[wrappers.nu]` takes the place of this one; a project that wants a wrapper of its own,
for its environment, names nusage the same way, `command = "nusage"` and `args = ["nu"]`
beside its `env`, and keeps nusage's server, which is Nushell for anything but `--lsp`.

Install the development tools with `mise install --monorepo`; `mise tasks --all` lists the
tasks, which run through the nusage built here. `mise run //catalog:install` has every new
interactive Nushell session load the catalog's modules. `mise dot apply` links the global
fragment that installs the released nusage for the user, with the `nu` it runs scripts in and
the `usage` its completions run. The repository uses a single `main` bookmark with a colocated
Git/Jujutsu checkout.

`mise run '//...:check'` runs the full local checks. CI uses mise's native affected-project
selection for pull requests, with root formatting and selection-regression checks always
run on Linux. Core crates and shared configuration conservatively select all projects.
Main receives the full checks before release assembly. Formatting, documentation and
synthetic schema checks run once on Linux; `check:platform` keeps runtime tests and Clippy
on both Linux and macOS. The check roots and their dependencies are declared in
`mise.toml`; `mise run //:check-affected` verifies the selection, including new plugin crates.
