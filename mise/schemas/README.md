# mise output schemas

`outputs.nuon` binds source-reviewed JSON Schemas to mise commands and modes.
The baseline remains mise **2026.10.21**, commit
[`61eb04dbc806cb646821e342b7abbbdaf1581e84`](https://github.com/jdx/mise/tree/61eb04dbc806cb646821e342b7abbbdaf1581e84).
Each binding records the serializer and builder locations at that revision.

There are 20 schema files, 26 output bindings, 32 executable cases, and 17
source-derived examples. This is a bounded expansion of the initial four schemas,
not a claim of complete mise coverage.

## Coverage

| Commands / modes | Schema shape | Generated wrapper |
| --- | --- | --- |
| `version` | Fixed record, required nullable latest version | Attached |
| `env` | String-valued environment map | Attached |
| `env --json-extended` | Map of values with optional source/tool metadata | Raw validation only |
| `bin-paths` | Executable name, path, and symlink records | Attached |
| `config`, `config ls` | Config path, tools, and override records | Attached |
| `config explain` | Key descriptions, paths, line numbers, and recognition state | Attached |
| `ls` | Tool map or filtered version list, including source variants | Raw validation only |
| `ls-remote` | Single-tool metadata or `--all` rows | Raw validation only |
| `outdated` | Tool map with nullable current/bump and optional release URL | Attached |
| `registry` | One registry record or a list, including tagged security features | Raw validation only |
| `tasks`, `tasks ls` | Task definitions, including dependency/run/output variants | Attached |
| `tasks validate` | Counts and validation issues, including error reports | Attached |
| `doctor project` | Checks with status and required nullable diagnostic fields | Attached |
| `installs ls` | Identity installation records | Attached |
| `skills ls` | Installed skill records | Attached |
| `tool` and its eight field filters | Full record, strings, lists, source, or options | Raw validation only |

Fixed serializer records reject unknown fields. Dynamic maps remain open with typed
values; task/backend option maps intentionally permit backend-defined keys.
Required nullable fields and omitted optional fields are represented separately.

The field filters for `tool` have separate bindings and cases so an arbitrary options
object cannot accidentally validate a malformed full tool record. They are all marked
`attach: false`: attaching only the unfiltered record would give filtered calls an
incorrect return type. Extended environment JSON also waits for output-mode selection.
The list/record and tagged unions marked `attach: false` wait for branch-aware optional
field filling. These are consumer limitations, not reasons to weaken the raw schemas.

## Checks and fixtures

Use the existing task:

```sh
mise run //mise:check-schemas
mise run //mise:check-schemas -- --bin /absolute/path/to/candidate/mise
```

The task first validates all 20 schema documents against their metaschema. It then checks
`examples.nuon` and runs the candidate binary against the manifest cases. Examples are
small source-derived documents, **not captured command output**. They check rejection of
wrong field types, omitted required fields, invalid tagged variants, and null where a
serializer omits the field instead.

Live cases use isolated temporary config, data, cache, and state directories. The project
contains a fake installed node binary, a local asdf plugin with fixed version listings,
tasks with structured metadata, a hidden file task, and controlled diagnostics.
The local plugin is linked inside the temporary data directory; no remote plugin or
tool installation is needed. No fixture task is executed by task listing or validation.
The diagnostic commands are only `exit 0` and `exit 1`.

The invalid-task and failing-diagnostic cases require exit status 1 **and** a matching
JSON report. Their failure status is part of the expected behavior. The identity-layout
listing uses a separate project config. The live installation and skill listings are
empty; populated records for those two outputs are checked with source-derived examples.
The single-tool remote listing is live; the `--all` shape is covered by examples to
avoid querying unrelated backends.

## Deferred

As requested for shape review, the more involved extraction and fixture work remains
separate:

- Settings and extended settings, whose fields follow the generated settings catalog.
- Task info's embedded Usage spec, workspace graphs and provider metadata.
- The main doctor report and its platform/system-specific sections.
- Lock and task-cache operation variants.
- Bootstrap, dotfiles, daemon and other provider-backed outputs; network-backed patrons.
- Full command-inventory comparison, automated schema refresh, and external references.
- Consumer mode/union fixes, live JSONL, broad Cargo/CI and cross-platform runs.

Adding another output means adding its schema, source binding, and representative cases
here. The shared development helpers remain in `../../schemas/`; no interpreter CLI
command or Rust dependency is introduced by this schema expansion.
