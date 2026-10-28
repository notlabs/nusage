# Output schema development

This directory contains shared Nushell development scripts, invoked by mise tasks.
Each integration owns its schema files, output bindings, source provenance, and fixture setup.
The interpreter's CLI and Rust dependencies are unchanged.

## First slice

The mise suite is in `mise/schemas/outputs.nuon`. Its four schemas were read from the
output builders and serializers at mise 2026.10.21, commit
`61eb04dbc806cb646821e342b7abbbdaf1581e84`. The manifest records those source locations.

- `version`: a fixed record, including required nullable `latest`.
- `env`: a map with string values.
- `config ls`: a list of config records.
- `ls`: a map without a tool argument and an array with one.

The five executable cases use a temporary project, isolated mise directories, one fake
installed node version, and one missing version. They do not install node. A seeded
release-index cache keeps the version check offline. The fixture is removed after each run.

## Existing task workflow

```sh
mise run //schemas:check
mise run //mise:check-schemas
mise run //mise:check-schemas -- --bin /absolute/path/to/candidate/mise
```

`//schemas:check` exercises valid output and failures for missing fields, extra fields,
trailing JSON documents, unexpected exit status, disappearing optional data, and invalid
JSONL records.

`//mise:check-schemas` runs the real mise executable against the unchanged baseline.
It is included in `//mise:check`; the shared checks join the existing
`mise run '//...:check'` CI command through their monorepo config root.

## Another tool

Add an output manifest beside that tool's schemas and a Nushell fixture script calling
`load-suite`, `run-suite`, and `finish` from `lib.nu`. Wire it through that
integration's mise tasks. There are no tool names or fixture paths in the shared runner.

An output has a stable `id`, command words, output `name`, boolean `select` flag,
`framing`, and manifest-relative `schema` path.

A case names an output, gives the complete `argv`, and declares acceptable `exit_codes`.
Its optional `expect` is an additional JSON Schema, used for fixture-specific assertions
such as a nonempty array or presence of an otherwise optional property. A finite JSONL
case can also state its expected `records` count. Each record must satisfy both schemas.

The runner captures stdout and stderr separately, checks status independently, and passes
the original stdout to check-jsonschema before any Nushell decoding. Checks never rewrite
schemas. Candidate binaries are tested against this same baseline; no version range is
implicitly claimed.

`pipx:check-jsonschema@0.39.0` is a pinned development tool in the root mise config.
The current uv installation cannot generate mise's Python dependency lock, so the added
lock entry pins the package version only. Updating uv and locking its transitive graph is
deferred.

## Deferred for shape review

- Remaining mise commands and variants, including extended JSON, tasks, and diagnostics.
- Full inventory comparison and automated source/schema refresh.
- Live JSONL streams, per-process timeouts, and cancellation. The current runner captures
  a finite invocation to completion; do not use it for watch commands.
- Shared external schema references and version-range/package distribution machinery.
- The full Cargo/fixture/CI suite and execution on macOS or Windows.

Keep new extraction and conformance work in this development workflow. Any interpreter
change should address an independently demonstrated consumer defect.
