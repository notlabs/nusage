# Docker Compose baseline

The command tree of Compose **v5.6.1**, exported through Usage's Cobra adapter, with typed
`version` and `ls` wrappers. The full exported spec is committed for inspection.
`docker-compose.baseline.overlay.kdl` limits the generated package to those two commands;
the other commands remain available through the original CLI.

```nu
use docker-compose *

docker-compose version | get version
docker-compose ls | select Name Status ConfigFiles  # requires a Docker daemon
```

The package calls the official standalone `docker-compose` binary on PATH. A Docker CLI
plugin installation alone does not supply that executable. The catalog check task
pins it to the same version as the extractor; exporting and generating do not install it.
The standalone binary is used so the generated spec has a single executable name; this does
not model Docker's own global/plugin flags.

## Regenerate

From the repository root:

```sh
mise run //catalog:spec docker-compose
mise run //catalog:generate docker-compose
mise run //catalog:check docker-compose
mise run //catalog/cobra:check
```

The first command builds the pinned upstream Go packages; subsequent runs use Go's build
cache. The catalog's ordinary freshness and signature checks apply. Its version probe compares
the spec with the installed binary; the full Go export belongs to `//catalog/cobra:check`.
The small `check.nu` runs only `version`, offline. It does not start containers or connect to a daemon. The
`ls` declaration is based on its serializer; its live Docker behavior has not been exercised
here. A conformance suite and wider command coverage are later work.

## Extraction boundary

[`RootCommand`](https://github.com/docker/compose/blob/v5.6.1/cmd/compose/compose.go) is
public. `spec/main.go` constructs it with a Docker CLI and adds the hook command that
[the upstream main](https://github.com/docker/compose/blob/v5.6.1/cmd/main.go) adds.
It never executes the command tree. Input/output streams are fixed to nonterminal streams,
and `COMPOSE_*`, `DOCKER_*` and `BUILDX_*` environment variables are cleared inside the
exporter process, because some constructors read them into flag defaults. The invoking
shell is unaffected. The spec version comes from the linked Compose dependency, not a
second hardcoded version.

Two small compatibility fixes are explicit in the extractor: trim short-help whitespace,
and quote reserved words/signed numeric defaults that Usage v7.1.3's
[KDL renderer](https://github.com/jdx/usage/blob/v7.1.3/integrations/cobra/kdl.go) emits bare.
For example, the unmodified exporter writes `default=true` and `default=-1`; Usage rejects
both as string defaults. [Upstream issue #1594](https://github.com/jdx/usage/issues/1594)
tracks the bug with minimal reproducers. Remove the quoting shim when the upstream renderer
is fixed.

The adapter is a useful starting point, not complete input fidelity. Its
[conversion](https://github.com/jdx/usage/blob/v7.1.3/integrations/cobra/convert.go) drops bare
required positionals such as `SERVICE COMMAND` in Compose's `exec` usage, and does not retain
pflag slice/repetition types. Compose also uses local root flags with `TraverseChildren`,
so project options are not exported as inherited flags for every child. These gaps are
visible in the full spec and are reasons to keep the published baseline narrow. They
belong in adapter improvements and input-compatibility work, rather than a new CLI parser
in this repository.

## Where output declarations can come from

Cobra flags identify possible selectors, but do not declare output framing or schemas.
There is no single safe “all commands with --format” overlay.

| Command | Evidence in Compose v5.6.1 | Output and overlay decision |
| --- | --- | --- |
| `version` | [version.go](https://github.com/docker/compose/blob/v5.6.1/cmd/compose/version.go) writes a literal JSON object | Implemented: `--format json`, one `{version: string}` record. Hide `--short`, which overrides that format. |
| `ls` | [list.go](https://github.com/docker/compose/blob/v5.6.1/cmd/compose/list.go) builds `[]stackView`; [formatter.go](https://github.com/docker/compose/blob/v5.6.1/cmd/formatter/formatter.go) serializes it as one array | Implemented: a table of `Name`, `Status`, `ConfigFiles` strings. Hide `--quiet`, which emits names instead. The empty result is an empty array. |
| `ps` | [ps.go](https://github.com/docker/compose/blob/v5.6.1/cmd/compose/ps.go) uses the Docker formatter and [ContainerContext](https://github.com/docker/compose/blob/v5.6.1/cmd/formatter/container.go)'s custom marshaler | Candidate JSONL output, one object per container. The schema must describe the formatter's accessors, not `api.ContainerSummary`. Account for `--quiet`, `--services`, truncation and custom templates. |
| `events` | [events.go](https://github.com/docker/compose/blob/v5.6.1/cmd/compose/events.go) marshals an explicit map and writes a newline per event | Candidate JSONL stream selected by boolean `--json`. Its fields come from that map; streaming behavior and event-dependent values need their own follow-up. |
| `config` | [config.go](https://github.com/docker/compose/blob/v5.6.1/cmd/compose/config.go) calls project JSON/YAML serializers or several alternate handlers | Candidate JSON record or YAML decoder. `--services`, `--images`, `--environment`, `--quiet`, `--output` and others replace or redirect stdout. The Compose input schema is not automatically a schema for normalized output. |

The two implemented output declarations use the existing value-taking `select "--format"`
and inline JSON Schemas. No schema extraction framework is introduced. The `ls` schema can
eventually be generated by inspecting the private `stackView` type in the pinned source;
a Go type/AST analysis can see it without exporting that type. In contrast, `ps` has a
custom marshaler, `events` builds a map, and `config` branches between serializers. A generic
reflection pass over Go structs would miss those distinctions.

The reusable route is to inventory output selectors from Cobra, attach source-backed
framing and shape information to chosen commands, and generate ordinary Usage overlays.
Keep an explicit override path for custom marshalers, maps, templates and alternate output
flags. JSON, JSONL and YAML should use the catalog's generic decoder support; these cases
do not need tool-specific runtime code. The gh investigation is in [../../cobra/README.md](../../cobra/README.md).
