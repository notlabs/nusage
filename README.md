# nusage

Typed Nushell commands from usage-annotated scripts, and typed wrappers from usage specs of
binaries. The project is nusage; the command is `nus`, and so is the shebang, `#!/usr/bin/env
nus`, and the prefix of what a generated module calls.
Early development.

- `nusage/`: the tool. `nus --help` for the CLI, `fixtures/` for the hand-written modules
  the generator reproduces and the contract a script relies on, `cargo doc --workspace
  --no-deps` for the crates. Two of them stand on their own: `nushell-schema`, the Nushell
  dialect of JSON Schema, and `openapi-usage`, an OpenAPI document as a usage spec with the
  HTTP mapping beside it, which `nus generate --http` turns into a module that calls the
  service as another calls a binary. `nus <script>` runs a script in the `nu` on PATH,
  as Nushell runs any script, with the typed commands of the scripts it calls defined
  before it: each binds the called script's `$usage` from its parameters and `run`s it, so
  a script calling a script stays in the same Nushell and gets the value back typed.
  `nu_plugin_nus` is nusage inside Nushell: the commands a module calls on its hot path,
  with the CLI's own signatures, served by one process across calls; `nus validate` holds
  documents to a schema. `mise run //nusage:plugins` registers it.
  A plugin is for what needs Rust in the interpreter, as a library only Rust reaches; a
  service or a binary is a module.
- `catalog/`: the wrappers for other tools, a Nushell module package per tool under
  `catalog/lib/`, generated from each tool's spec, the schemas of its outputs and the
  overlays beside it, and each released as the packslip package
  `packslip:github.com/notlabs/nusage/catalog/<tool>`. A project that installs one and
  includes `nusage/conf.d/nus.toml` calls its commands from a script without importing them:
  `jj log` there is the typed one. `catalog/mise.toml` declares the entries and
  `catalog/tasks/catalog.nu` the layout; `catalog/clap/` reads the spec of a binary whose
  crate builds its clap command, as jj's is, and `catalog/schemas/` runs an output-schema
  suite, as both packages keep one. `catalog/README.md` says how a project uses them.
- `intent/`: the direction, as claims that are checked where they can be; nothing there is
  settled.
- `mergiraf/`: Mergiraf, the structural merge tool `jj resolve` runs here, built from its
  published source with the patches beside it, which teach it Nushell and are written to be
  proposed upstream: `mise run //mergiraf:build`, and `//mergiraf:test` holds the build to
  the cases the patches carry.

Run `nus inspect script.nu | from json` to read the analyzer's resolved calls and
findings as values, without running the script. The output's contract is
`nusage/schemas/inspection.schema.json`; its command models are the ones `nus model`
prints. It reports the calls the analyzer resolves, not a complete dependency graph.

An editor that runs `nus lsp` where it would run `nu --lsp` checks a script nusage runs as
nusage runs it: Nushell knows `$usage` and its type, and holds each call of another script to
that script's header. Or leave the editor as it is: in a project that includes
`nusage/conf.d/nus.toml`, every `nu` mise starts is `nus nu`, which serves `nus lsp` when
asked for `nu --lsp` and is Nushell for anything else, so an editor that starts `nu` through
mise's shims gets nusage's server with the project's packages. Outside such a project, after
`mise dot apply`, `MISE_ENV=nus-lsp` in the environment the editor starts from does the same.
That `nus` is the one mise installs, so it must be a release that has `nus nu`: an older one
refuses it for every `nu` mise starts.
`MISE_ENV=nus-lsp,nus-kakehashi` installs
[kakehashi](https://github.com/atusy/kakehashi) too, and `nu --lsp` then also highlights a
script's header as usage KDL and the scripts its `run=` names as Nushell or sh. A project's
own `[wrappers.nu]` takes the place of this one; a project that wants a wrapper of its own,
for its environment, names nusage the same way, `command = "nus"` and `args = ["nu"]`
beside its `env`, and keeps nusage's server, which is Nushell for anything but `--lsp`.

An interactive Nushell gets the project's environment and packages from `nus activate nu`,
saved beside Nushell's configuration and used from `config.nu` in place of `mise activate
nu`:

```nu
nus activate nu | save --force ($nu.default-config-dir | path join nus.nu)
# in config.nu:
use ($nu.default-config-dir | path join nus.nu) *
```

The file is the same for every nusage and every machine, so it is saved once. In a checkout
of this repository `mise dot apply`, and so `mise bootstrap`, links it into place and adds the
line to `config.nu`, where Nushell keeps its configuration on Linux and macOS. The `*` brings
in its `mise`, so that `mise shell` sets a tool's version for the session as it does with
mise's own activation; the rest stays inside the module.

The environment mise resolves for the working directory and `MISE_ENV` is then an overlay,
`mise-<digest>`, and the typed commands of the packages it names, as `nus modules` writes
them, another, `nus-<digest>`, each named by what it holds. Before each prompt a hook runs
`mise env --json` and, when the result changed, hides the overlays of the last environment
and uses those of this one, so the line after a `cd` has the directory's tools and commands,
and leaving takes away everything they set; an environment met again has the same overlays
again. `$env.MISE_ENV = "…"` switches environments the same way, and `$env.MISE_ENV = null`
leaves them. Above them is the overlay `prompt`, where what is set at the prompt lands, so it
stays from one directory to the next; a `PATH` set there hides mise's for the rest of the
session. Take a variable away with `$env.NAME = null` rather than `hide-env`: Nushell brings
back what is hidden whenever an overlay is hidden, and so at the next change of environment.
`overlay list` shows them all. A shell that starts with mise's environment already set, as mise's `nu` wrapper,
an editor or an activated parent shell starts it, has it taken out first. A script, and
`nu --mcp`, keep the environment they started with.

Install the development tools with `mise install --monorepo`; `mise tasks --all` lists the
tasks, which run through the nus built here. `mise run //:link <project>` installs this
checkout's builds into mise as the nusage versions another project names, so that project
runs them as it would the releases. `mise dot apply` links the global
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
