# nusage

Typed Nushell commands from usage-annotated scripts, and typed wrappers from the usage specs of binaries and services.
The command is `nus`, and so is the shebang, `#!/usr/bin/env nus`. Early development.

- `nusage/`: `nus` and its crates; `nus --help` for the CLI, and each crate's documentation, `cargo doc --workspace --no-deps`, for what it is.
- `catalog/`: a generated module package per tool under `catalog/lib/`, each released as `packslip:github.com/notlabs/nusage/catalog/<tool>`.
- `intent/`: where the project is going, as claims checked where they can be.
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

`nus inspect script.nu | from json` gives the calls the analyzer resolves and its findings without running the script, as `nusage/schemas/inspection.schema.json` describes.

## Editors

`nus lsp` is Nushell's language server with nusage's view of a script: `$usage` and its type, and each call of another script held to that script's header.
In a project that includes `nusage/conf.d/nus.toml`, `nu` is `nus nu`, which serves `nus lsp` when asked for `nu --lsp`, so an editor that starts `nu` through mise gets it; that `nus` is the release mise installs, so it needs one that has `nus nu`.
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

Install the tools with `mise install --monorepo`.
Infrastructure tasks use the released Mise module pinned by the repository configuration.

Mise discovers project configs one to three directories below the repository root.
The workspace-graph provider supplements native Cargo dependencies with Go import edges and dependencies declared in each consuming project's config:

```toml
# catalog/lib/jj/mise.toml
[_.nusage.project]
depends_add = ["custom:catalog"]
```

Custom project IDs use `custom:<relative config root>`, with `custom:root` for the repository root.
Cargo and Go retain their native IDs.
Tasks use `^build`, `^check`, and `^check:platform` for upstream prerequisites and `:task` for local prerequisites.

Use an outer `mise exec` to refresh the graph before the inner `run` resolves task dependencies:

```sh
mise exec -- mise run '//catalog/...:check'
mise exec -- mise run //nusage/crates/nusage-spec:check
```

Each crate's check runs its tests, Clippy, documentation checks, and upstream checks.
`//nusage:check` checks all crates and verifies the shared fixtures; `//nusage:build` builds the distributed binaries.

To inspect the graph, run `mise deps install workspace-graph`, then `mise tasks graph --json` or `mise tasks deps`.
Go edges reflect the current build context; refresh the provider explicitly after changing build-context environment variables.

Mr Boxington manages build targets under the ignored `.cache/mbx-targets` directory.
The repository's discovery exclusions keep build artifacts out of the project graph.

Infrastructure tests are co-located `*_test.nu` suites run by Nutest:

```sh
mise exec -- mise run //:test
mise exec -- mise run //catalog:test
```
