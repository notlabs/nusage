# nusage

Typed Nushell commands from usage-annotated scripts, and typed wrappers from the usage specs
of binaries and services. The command is `nus`, and so is the shebang, `#!/usr/bin/env nus`.
Early development.

- `nusage/`: `nus` and its crates. `nus --help` for the CLI, `cargo doc --workspace --no-deps`
  for the crates. Two stand on their own: `openapi-usage`, an OpenAPI document as a usage
  spec with the HTTP mapping beside it, and `nushell-schema`, the Nushell dialect of JSON
  Schema. `nu_plugin_nus` serves the commands generated modules call, in one process across
  calls; `mise run //nusage:plugins` registers it.
- `catalog/`: a generated module package per tool under `catalog/lib/`, each released as
  `packslip:github.com/notlabs/nusage/catalog/<tool>`. `catalog/README.md` says how a project
  uses them.
- `intent/`: where the project is going, as claims checked where they can be.
- `mergiraf/`: Mergiraf, the structural merge tool `jj resolve` runs here, built with patches
  that teach it Nushell.

## Scripts

`nus script.nu` runs a script in the `nu` on PATH, with `$usage` bound from its arguments. A
script that calls another, `./other.nu ...`, calls a typed Nushell command defined for it, so
the other script runs in the same Nushell and returns its value. Such a call follows
Nushell's rules rather than usage's:

| Declaration | `nus script.nu ...` | Call from another script |
| --- | --- | --- |
| Required flag | Omission is rejected | Omission gives `null` unless a default applies |
| `choices` | Other values are rejected | The choices are completions only |
| Flag `env` fallback | An omitted flag reads the variable | No fallback |

A script's spec is its `#USAGE` header, or the hidden `.<filename>.usage.kdl` beside it when
present. `include` paths resolve against that file, and `mount` adds the spec its command
prints. Type annotations such as `arg (int)"<n>"` are kept from the header and the sidecar,
not from included or mounted specs, where the value stays a string.

`nus inspect script.nu | from json` gives the calls the analyzer resolves and its findings
without running the script, as `nusage/schemas/inspection.schema.json` describes.

## Editors

`nus lsp` is Nushell's language server with nusage's view of a script: `$usage` and its type,
and each call of another script held to that script's header. In a project that includes
`nusage/conf.d/nus.toml`, `nu` is `nus nu`, which serves `nus lsp` when asked for `nu --lsp`,
so an editor that starts `nu` through mise gets it; that `nus` is the release mise installs,
so it needs one that has `nus nu`. Elsewhere, after `mise dot apply`, `MISE_ENV=nus-lsp` in
the editor's environment does the same, and `MISE_ENV=nus-lsp,nus-kakehashi` adds
[kakehashi](https://github.com/atusy/kakehashi), which highlights a script's header as KDL.
A project with its own `[wrappers.nu]` keeps nusage's server with `command = "nus"` and
`args = ["nu"]`.

## Development

`mise install --monorepo` installs the tools, `mise tasks --all` lists the tasks, which run
through the `nus` built in the checkout, and `mise run '//...:check'` runs every check.
`mise dot apply` links the user-level fragment that installs the released nusage, with the
`nu` and `usage` it runs. `mise run //:pr-status` reports the open pull requests and their
checks.
