# nusage

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
The installed `target/install/bin/nus` is the project tool; `//:build` refreshes it.

Install the tools with `mise install --monorepo`, and run tasks through `mise exec -- mise run`:

```sh
mise exec -- mise run '//catalog/...:check'
mise exec -- mise run //crates/nusage-spec:check
```

The graph providers under `graph/` are placeholders until the environment plugin is installed.
Only native Cargo and Go projects are currently registered; catalog tasks still resolve by path.
The `nus` tool resolves to `target/install/bin/nus`; each binary crate's build task owns freshness.

Each crate's check runs its tests, Clippy, documentation checks, and upstream checks; the `nusage` crate's also holds `nus` to the fixtures.
`//:check` runs every crate's, and `//:build` builds the distributed binaries.

Mr Boxington manages build targets under the ignored `.cache/mbx-targets` directory.
The repository's discovery exclusions, `target` among them, keep build artifacts out of the project graph.

Infrastructure tests are co-located `*_test.nu` suites run by Nutest; a config root's suites, and what they load, are its generated `nu-test` input group:

```sh
mise exec -- mise run //:test
mise exec -- mise run //catalog:test
```
