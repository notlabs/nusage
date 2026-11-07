# nusage

Typed Nushell commands from usage-annotated scripts, and typed wrappers from the usage specs of binaries and services.
The command is `nus`, and so is the shebang, `#!/usr/bin/env nus`. Early development.

- `nusage/`: `nus` and its crates; `nus --help` for the CLI, and each crate's documentation, `cargo doc --workspace --no-deps`, for what it is.
- `catalog/`: a generated module package per tool under `catalog/lib/`, each released as `packslip:github.com/notlabs/nusage/catalog/<tool>`.
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

Install the tools with `mise install --monorepo`, and run tasks through `mise exec -- mise run`:

```sh
mise exec -- mise run '//catalog/...:check'
mise exec -- mise run //nusage/crates/nusage-spec:check
```

The project graph and the tests' inputs are generated configuration.
The root's `auto` providers refresh them before `mise exec` and `mise run`, but `mise run` has resolved its tasks by then, so only the next mise process reads what they wrote; `mise exec` makes the inner `mise run` that process.
A plain `mise run` that finds the graph changed fails at `//:graph-current` rather than run with the old one, and running it again works.
On a fresh clone a plain `mise run` stops earlier: a task that names a generated input group does not load until the providers have run.

### The project graph

Mise discovers config roots one to three directories below the repository root; Cargo and Go projects keep their native IDs and edges.
A config root that declares `[_.nusage.project]` or `[_.nusage.catalog]` is a project, and so is the repository root, with an ID that names its kind:

| ID | Project |
| --- | --- |
| `catalog:<entry>` | A catalog entry: `[_.nusage.catalog]` |
| `gen:<name>` | A generator an entry's spec comes from: `kind = "gen"` |
| `fixtures:<name>`, `schemas:<name>` | Data other projects read, depending on nothing: `kind` and `name` |
| `nu:<name>` | Any other project; `nu:root` is the repository root |

Another config root is no project: `nusage/` only selects its crates' tasks by path.
Mise drops `^task` dependencies in such a root, so the graph refuses them there.

The providers are in `.mise/graph`: `go-workspace` writes the ignored `go.work`, `go-imports` and `nu-imports` analyze the code into `.cache/graph`, and `project-graph` writes the configuration.
Each edge it adds keeps its kind and the file and line it comes from, as JSON in the project's `metadata.edges`:

- `declared`: `[_.nusage.project].depends_add`, for what nothing else shows, and `fixtures` when the target is a data project.
- `spec-generator`: what an entry's spec names: a `mise run` task, `clap`, or `openapi`.
- `nu-use`, `nu-source`, `nu-path`: Nushell that loads another project's file, or names it in a `path self` constant.
- `task-call`: a literal `mise run //root:task`, or a `{ task = }` or `{ tasks = [] }` run entry.
- `task-dir`: a task that runs in another project's directory.
- `go-import`: an import between Go modules.

A computed `use` or `mise run` target is an error until the owning project lists its file in `[_.nusage.project].dynamic` and declares what it reaches in `depends_add`.
A generator does not depend on an entry, a data project depends on nothing, and a cycle names the edges that close it.

`mise tasks graph --json` and `mise tasks deps` show the graph; `mise deps install --force project-graph` writes it again.
Go edges reflect the current build context; refresh `go-imports` after changing build-context environment variables.

The `nus` provider builds `nus`, `nu_plugin_nus` and `openapi-usage` into `.bin` when the Rust sources change: tasks run them from PATH instead of depending on a build, and a cached task that runs `nus` keys its result on `.bin/nus`.
A tool is no edge, so `--affected` selects the crates' checks for a change to the crates, not those of the projects that run `nus`; CI checks everything on main.

Each crate's check runs its tests, Clippy, documentation checks, and upstream checks; the `nusage` crate's also holds `nus` to the fixtures.
`//nusage:check` runs every crate's, and `//nusage:build` builds the distributed binaries.

Mr Boxington manages build targets under the ignored `.cache/mbx-targets` directory.
The repository's discovery exclusions, `target` among them, keep build artifacts out of the project graph.

Infrastructure tests are co-located `*_test.nu` suites run by Nutest; a config root's suites, and what they load, are its generated `nu-test` input group:

```sh
mise exec -- mise run //:test
mise exec -- mise run //catalog:test
```
