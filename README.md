# nusage

Typed Nushell commands from usage-annotated scripts, and typed wrappers from usage specs of
binaries.
Early development.

- `nusage/`: the tool. `nusage --help` for the CLI, `fixtures/` for the hand-written modules
  the generator reproduces and the contract a script relies on, `cargo doc --workspace
  --no-deps` for the crates.
- `mise/`: the module for mise, generated from mise's own spec and the overlays there, with
  the schemas of its outputs under `schemas/`.
- `jj/`: the module for jj, generated from the spec `clap/` reads from jj-cli, committed
  since writing it compiles jj-cli, with the schemas of its JSON outputs under `schemas/`;
  `mise run //jj:spec` writes the spec for a new jj.
- `clap/`: the spec of a binary that ships none, read from the clap command its crate
  builds. Its README says how to add a binary.
- `schemas/`: the runner of an output-schema suite and the overlay it declares, shared by
  the modules. Its README says what a suite is.

Install the development tools with `mise install --monorepo`; `mise tasks --all` lists the
tasks, which run through the nusage built here. `mise run //mise:install` and `mise run
//jj:install` generate a module and have every new interactive Nushell session load it. `mise
dot apply` links the global fragment that installs the released nusage for the user, with
the `nu` it runs scripts in and the `usage` its completions run. The repository uses a single
`main` bookmark with a colocated Git/Jujutsu checkout.

## Runtime output validation

Generated binary modules require `nusage` on PATH. Before decoding or converting output,
they validate its raw JSON against the schema used to generate the module. JSONL uses
that schema for each record, compiles it once per invocation, and releases each valid
record immediately. An invalid record fails the call; an already consumed valid prefix
cannot be recalled. Format constraints such as `date-time` are asserted.

Without an explicit output schema, a wrapper discovers schemas from the data. A local
`$schema` path is relative to the input file (or PWD for stdin); a missing local schema or
one in an unrecognized dialect leaves the data unchanged. HTTP(S) schemas are fetched
only when their URLs match `NUSAGE_SCHEMA_ALLOW`. Unknown declarations remain ordinary
data, including the `$schema` property. Allowed schemas that cannot be loaded or that
reject the data produce errors, rather than silently disabling validation.

```nu
# Exact URLs or path globs; scheme, host, port and query must match literally.
$env.NUSAGE_SCHEMA_ALLOW = '["https://schemas.example.org/events/v1.json", "https://schemas.example.org/tools/**"]'

# Disable automatic checks, retaining ordinary JSON decoding and declared conversions.
$env.NUSAGE_VALIDATE = 'off' # default: auto

# Check a schema alone, or check documents explicitly (also when automatic checks are off).
nusage validate report.schema.json
nusage validate report.schema.json report.json

# Discover a schema and stream checked records to stdout (no file means stdin).
nusage validate --auto --jsonl --passthrough events.jsonl

# Machine-readable diagnostics on stderr; stdout remains the checked data.
$env.NUSAGE_DIAGNOSTICS = 'json' # default: human
nusage validate report.schema.json report.json
```

External `$ref` retrieval uses the same allowlist, including file URLs. In-document refs
and the built-in standard metaschemas need no permission. Redirects are refused. Schema
downloads have a 10-second timeout and a 4 MiB limit; JSONL records have a 16 MiB limit.
Up to 32 findings are reported for the failing record, with physical line, data record,
instance pointer and schema keyword location. Blank lines are ignored as in Nu's
`from json --objects`. `--passthrough` is byte-preserving for data records; consumed
headers and blank JSONL lines are omitted. It accepts one input stream.

JSONL preserves the earlier NUON convention: its first nonblank line may be an **inline
schema** whose `$schema` is the NUON dialect URI. That line is consumed and describes
subsequent records. A bare `{"$schema":"some-schema-url"}` is a data record, not a
header. Without a header, each record can name its own schema. An explicit output schema
takes precedence and disables header inference. The legacy dialect URI remains an opaque
identifier; recognizing it makes no request to the old forge:

```text
https://gerrit.tail3b571d.ts.net/plugins/gitiles/notlabs/+/refs/heads/nusage/nuon-schema/nusage/nuon-schema/meta.json
```

The checker, interpreter and spec commands share a diagnostic record and human/JSON
renderers. Generated wrappers adapt that record into a native Nu error with its code and
locations. Their private `--nu` transport carries serde `Result` envelopes because Nu's
JSON decoder otherwise treats a failed external validator as EOF; those envelopes are
removed before values reach the caller. Nu controls rendering of those native errors.

This first runtime slice restores validation and discovery. Dynamically discovered schemas
do not change static signatures or apply new `x-nu` conversions. Full reintegration of the
earlier NUON codec, persistent schema caching and migration of every upstream parser's
diagnostics are follow-up work. Existing generated conversions still run after validation.
