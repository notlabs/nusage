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

The tools install with `mise install --monorepo`.
The CLI tasks run through the `nus` built in the checkout.
Plain Nu infrastructure uses the public Mise module from the checksum-locked catalog 0.1.0.
This bootstrap dependency lets graph preparation and catalog tooling use structured Mise commands before building the next release, without a source-project dependency cycle.
The assembled task catalog bundles that module for consumers outside this repository.

Mise discovers config roots one to three directories below the repository root.
`[deps.workspace-graph]` prepares an ignored `go.work` with `go work use -r .` and an ignored `.mise/conf.d/_workspace-graph.toml` supplement.
Cargo projects and edges stay native; the supplement adds Go import edges and projects for discovered config roots, including projects with no tasks.
A config root also depends on native projects beneath it or selected by a task's `dir`.

Dependencies that are not described by language metadata belong to the consuming project's existing config:

```toml
# catalog/lib/jj/mise.toml
[_.nusage.project]
depends_add = ["custom:catalog"]
```

Custom IDs are `custom:<relative config root>` (`custom:root` for the repository root); native Cargo and Go IDs are preserved.
Local `depends_add` declarations, including those in active config fragments, extend the graph without replacing native edges.
There is no producer-side consumer inventory.
Project-local config changes affect their owning project and its consumers; root shared configuration remains a global input.
Task prerequisites consume this graph: `^build`, `^check`, or `^check:platform` select the corresponding upstream tasks; `:task` selects a local prerequisite.

Prepare the graph before task dependencies or affected projects are resolved:

```sh
mise exec -- mise run '//catalog/...:check'
mise exec -- mise run --affected --affected-base main '//...:check'
```

The outer `exec` refreshes stale providers; the inner `run` reads the updated graph before resolving its prerequisites.
For inspection, use `mise deps install workspace-graph` followed by `mise tasks graph --json` or `mise tasks deps`.
The graph preparation runs in plain Nu and Go and does not build `nus`.
Included `*.tasks.toml` files participate in provider freshness.
The generated fragment's `_` prefix keeps it outside the provider's configuration inputs.
Go edges follow the current Go build context, including test imports; after changing build-context environment variables, refresh explicitly with `mise deps install workspace-graph`.

Each Cargo crate includes the shared test, Clippy, documentation and check tasks from `.mise/lib/cargo.tasks.toml`.
For example, `mise exec -- mise run //nusage/crates/nusage-spec:check` checks that crate and its native Cargo upstream projects.
`//nusage:build` assembles the distributed binaries; `//nusage:check` selects all crate checks and verifies the shared fixtures.
The `custom:nusage` aggregate and the native `cargo:nusage` crate are distinct projects.

In CI, `MBX_TARGET_ROOT` places managed targets under ignored `.cache/mbx-targets` inside the checkout.
Mise also ignores configuration under that target root, so artifact trees cannot become projects through the public `target` links.
Managed check lanes and the separate object store remain enabled.

Infrastructure tests are co-located `*_test.nu` suites discovered by the pinned Nutest module; `mise exec -- mise run //:test` and `mise exec -- mise run //catalog:test` run them without building `nus`.
The graph fixture verifies actual caret execution, cold preparation, platform checks, native edges, project add/move/remove, affected selection, and failures before consumer execution.
