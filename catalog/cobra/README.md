# Cobra

A pinned Go module builds the upstream command tree and hands it to
[Usage's Cobra adapter](https://github.com/jdx/usage/tree/v7.1.3/integrations/cobra).
The catalog then reads the exported spec, merges its overlays, and generates the Nushell
module. This is the same boundary as the Clap extractors: command metadata comes from the
tool's library; output declarations are separate.

The first example is [Docker Compose](../lib/docker-compose/README.md). Its extractor is a
small independent Go module under `lib/docker-compose/spec/`; `go.mod` and `go.sum` pin
Compose v5.6.1 and the adapter at Usage v7.1.3's commit. The adapter is a nested Go module
without a matching module tag, hence its pseudo-version. Go is a development dependency.
Loading or calling the generated module does not build or run the extractor.

`mise.toml` supplies the Go toolchain and the export task. The catalog entry uses its existing
`spec.run` hook; there is no new catalog entry kind or nusage command. Another Cobra tool
would get its own constructor and Go module, an export task, and the same catalog entry.
Separate Go modules let tools keep their own dependency versions.

## GitHub CLI

The second example is [gh](../lib/gh/README.md), at
[v2.103.3](https://github.com/cli/cli/tree/v2.103.3), whose construction boundary differs
from Compose's. [`root.NewCmdRoot`](https://github.com/cli/cli/blob/v2.103.3/pkg/cmd/root/root.go)
takes a factory whose configuration and telemetry interfaces come from `internal/` packages,
which only code inside the upstream module may import; the upstream
[docs generator](https://github.com/cli/cli/blob/v2.103.3/cmd/gen-docs/main.go) builds there,
with an empty in-memory configuration, no extensions and no-op telemetry. So does the
extractor, `lib/gh/spec/main.go`: `gh.nu` clones cli/cli at the tag `lib/gh/spec/pin.toml`
names, under the user's cache directory, copies the file in as `cmd/nusage-spec/main.go`,
adds the adapter to the checkout's module at the pinned version, and runs it. The user's
aliases, extensions, hosts and tokens stay out, `GH_*` and `GITHUB_*` cleared in the exporter
process; nothing impersonates the upstream module path, and the checkout is never pushed.
The catalog entry is the same `spec.run` hook as Compose's, with the version probe.

Output metadata is unusually useful:
[`AddJSONFlags`](https://github.com/cli/cli/blob/v2.103.3/pkg/cmdutil/json_flags.go) records
the available fields in the Cobra annotation `help:json-fields`, and `gh.nu --json-fields`
exports them per command into `lib/gh/json-fields.json`. `--json` takes fields, not the name
of a format, so it is not a `switch` as mise's `--json` is: each typed command's output
names its field list as `nusage-args`, in `lib/gh/schemas/outputs.nuon`, and its schema
follows the exporter for those fields, with `--jq` and `--template`, which transform the
selection, hidden. `gh api` stays outside the typed baseline.

The adapter reads nothing from a Use line's alternation, `[<number> | <url> | <branch>]`,
reads a group's `<command>` placeholder as a positional, and writes a command's own
persistent flag twice, so that usage keeps the one without `global`; the extractor
normalizes the three, as its comments say, until the adapter does.
