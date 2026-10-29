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

Inspected at [v2.103.3](https://github.com/cli/cli/tree/v2.103.3). It is promising for a second
example, but its construction boundary differs from Compose's.

[`root.NewCmdRoot`](https://github.com/cli/cli/blob/v2.103.3/pkg/cmd/root/root.go) takes a
factory whose configuration and telemetry interfaces come from `internal/` packages.
The upstream [docs generator](https://github.com/cli/cli/blob/v2.103.3/cmd/gen-docs/main.go)
uses an empty in-memory configuration, no extensions, and no-op telemetry. That is the
right starting point, but it builds inside the upstream module. An independent module
cannot import those internal packages as the docs generator does. A follow-up can either
add a public upstream construction helper or build a small export entrypoint in an isolated
copy of the pinned upstream source. Do not use the user's aliases, extensions, authentication
configuration, or a module path impersonating the upstream package to bypass this boundary.

Output metadata is unusually useful:
[`AddJSONFlags`](https://github.com/cli/cli/blob/v2.103.3/pkg/cmdutil/json_flags.go) records
the available fields in the Cobra annotation `help:json-fields`. A walker can export a
per-command field inventory and identify `--json <fields>` selectors without scraping help.
It cannot infer the output types or whether the command emits an object or an array from
that annotation. Those require following each command's exporter and serialized values.

An output generator for gh should therefore:

1. Read the JSON-field annotation from the constructed, isolated command tree.
2. Select an explicit field set for each baseline command. `--json` takes fields, not the
   name of a format; it cannot be treated as Compose's `--format json`.
3. Follow the serializer for those fields to derive a schema, accounting for nulls,
   omitted fields, custom marshalers and command-specific outer shapes.
4. Remove `--jq` and `--template` from a wrapper that promises that shape: both transform
   the selected output. Keep dynamic endpoints such as `gh api` outside that typed baseline.

The current Usage selector model supplies an output name as a value-taking selector's
argument. A field-list selector needs an explicit representation of the selected fields
(or a deliberately named output carrying that list); it should not be silently equated
with a boolean `--json` switch. This and the internal construction boundary are why this
PR implements Compose first.
