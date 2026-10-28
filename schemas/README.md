# schemas

The runner of an output-schema suite and the overlay it declares, shared by the modules; each
module keeps its schemas, manifest and fixtures beside it, as `mise/schemas/` does.

A suite is a NUON manifest. `outputs` bind schemas to a binary's outputs: an `id`, the
`command` words, the output `name`, the `select` switch, the `framing` (`json` or `jsonl`),
the `schema` file beside the manifest, and `attach: false` for an output checked but not
declared in the overlay. `cases` run the binary: an `id`, the `output`, the whole `argv`, the
`exit_codes` accepted, an `expect` schema the output must also satisfy, and `records` for a
JSON lines count.

`overlay.nu <manifest>` prints the usage overlay declaring each attached output with its
schema embedded, for `nusage generate --overlay`. `lib.nu` runs a suite: `load-suite`,
`run-suite`, which holds the binary's raw stdout to the schemas through `nusage validate`
before anything decodes it, and `finish`. `verify.nu` holds the runner to the failures it
must report; `mise run //schemas:check` runs it.
