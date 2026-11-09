# nusage: bootstrap with `mise plugins link nusage-graph ./graph/plugin`

Typed Nushell commands from usage-annotated scripts, and typed wrappers from the usage specs of binaries and services.
The command is `nus`, and so is the shebang, `#!/usr/bin/env nus`. Early development.

- `crates/`: `nus` and its crates; `nus --help` for the CLI, and each crate's documentation, `cargo doc --workspace --no-deps`, for what it is.
- `catalog/`: a generated module package per tool under `catalog/packages/`, each released as `packslip:github.com/notlabs/nusage/catalog/<tool>`.
- `mergiraf/`: Mergiraf, the structural merge tool `jj resolve` runs here, built with patches that teach it Nushell.

## Scripts

`nus script.nu` runs a script in the `nu` on PATH, with `$usage` bound from its arguments.
A script that calls another, `./other.nu ...`, calls a typed Nushell command defined for it, so the other script runs in the same Nushell and returns its value.
Such a call follows Nushell's rules rather than usage's:

| Declaration | `nus script.nu ...` | Call from another script |
| --- | --- | --- |
| Required flag | Omission is rejected | Omission gives `null` unless a default applies |
| `choices` | Other values are rejected | The choices are completions only |
| Flag `env` fallback | An omitted flag reads the variable | No fallback |

A script's spec is its `#USAGE` header, or the hidden `.<filename>.usage.kdl` beside it when present.
`include` paths resolve against that file, and `mount` adds the spec its command prints.
Type annotations such as `arg (int)"<n>"` are kept from the header and the sidecar, not from included or mounted specs, where the value stays a string.

`nus inspect script.nu | from json` gives the calls the analyzer resolves and its findings without running the script, as `crates/nusage/schemas/inspection.schema.json` describes.

## Editors

`nus lsp` is Nushell's language server with nusage's view of a script: `$usage` and its type, and each call of another script held to that script's header.
In a project that includes `share/nusage.toml`, `nu` is `nus nu`, which serves `nus lsp` when asked for `nu --lsp`, so an editor that starts `nu` through mise gets it; that `nus` is the release mise installs, so it needs one that has `nus nu`.
Elsewhere, after `mise dot apply`, `MISE_ENV=nus-lsp` in the editor's environment does the same, and `MISE_ENV=nus-lsp,nus-kakehashi` adds [kakehashi](https://github.com/atusy/kakehashi), which highlights a script's header as KDL.
A project with its own `[wrappers.nu]` keeps nusage's server with `command = "nus"` and `args = ["nu"]`.

## Interactive Nushell

`nus activate nu` takes the place of `mise activate nu`:

```nu
nus activate nu | save --force ($nu.default-config-dir | path join nus.nu)
# in config.nu:
use ($nu.default-config-dir | path join nus.nu)
```

The file is the same for every nusage and every machine; in a checkout of this repository, `mise dot apply` links it into place with an autoloaded file that uses it, leaving `config.nu` alone.
Before each prompt, the environment mise resolves for the directory and `MISE_ENV` becomes an overlay, and the typed commands of its packages another, so leaving a project takes away everything they set; `$env.MISE_ENV = null` leaves an environment.
What is set at the prompt stays across directories, though a `PATH` set there hides mise's for the rest of the session, and `mise shell` works as it does with mise's own activation.
Take a variable away with `$env.NAME = null`, not `hide-env`, which Nushell undoes at the next change of environment.
A shell that starts with mise's environment already set has it taken out first; a script and `nu --mcp` keep the environment they started with.

## Development

Infrastructure entrypoints use explicit relative imports of the committed catalog modules.
The root includes `share/nusage.toml` for tool pins and the `nu` wrapper.
Libraries and Nutest suites use relative imports because Nushell parses them without a script prelude; no catalog bootstrap release or `NU_LIB_DIRS` is needed.
The built `target/install/bin/nus` is on the development PATH; `//:build` refreshes it.

After linking the plugin, `mise tasks ls --all` refuses once while writing the graph; run it again.
Run `mise run //:build` to install the local binaries, then `mise install --monorepo` for the remaining tools.
The build runs `cargo build --workspace --locked` once and copies the workspace's binary artifacts from Cargo's JSON messages into `target/install/bin`, including Nushell plugins.
Mise tracks the Cargo workspace inputs and installed binaries so an unchanged build is skipped.
The local binaries are build products on PATH; `[deps.nus]` refreshes them through `//:build`.
The user-facing `share/nusage.toml` still installs the released tool.
Run tasks normally:

```sh
mise run '//catalog/...:check'
mise run //crates/nusage-spec:check
```

Run the pipeline locally with `mise run ci` before pushing.
The first run is cold; reruns reuse the container and its warm tool and Cargo caches.

The environment plugin discovers `//graph/...:provider` tasks, runs them under Nu, and projects their records into ignored crate task fragments and `.mise/conf.d/_projects.toml`.
A changed project graph is written and the command refuses with `project graph changed; run the command again`; the next command reads it.
Mise caches the hook's result against provider input records in its env cache. This needs a session key, supplied automatically by `mise activate` and inside `mise exec` and tasks. A bare shell without activation recomputes the graph on every command. Set `MISE_ENV_CACHE=0` to force a recompute; the plugin has no cache of its own. `//graph:check` validates provider JSON Lines against the output contract through `nus validate` after the tool is built.

Each crate's check runs its tests, Clippy and documentation checks, with transitive Cargo inputs; the `nusage` crate's also holds `nus` to the fixtures.
`mise run //...:check` checks every project; `//:build` installs the distributed binaries.

Mr Boxington manages build targets under the ignored `.cache/mbx-targets` directory.
The repository's discovery exclusions, `target` among them, keep build artifacts out of the project graph.

Infrastructure tests are co-located `*_test.nu` suites run by Nutest; each config root owns its test task and declares its inputs:

```sh
mise run //:test
mise run //catalog:test
```

`//graph:test`, included in the root check, tests the affected-selection matrix in isolated JJ workspaces with independent Git baselines.
It inspects `--affected-json` and forgets each workspace and removes its temporary directory after success or failure.
