# schemas

The runner of an output-schema suite and the overlay it declares, shared by the packages; each
package keeps its schemas, manifest and examples beside it, as `../lib/mise/schemas/` does.

A suite is a NUON manifest. `outputs` bind schemas to a binary's outputs: an `id`, the
`command` words, the output `name`, the `select` switch or, where no switch asks for the
output, the words that do (jj's `--no-graph --template ...`, declared as `nusage-args`), the
`framing` (`json` or `jsonl`), the `schema` file beside the manifest, and `attach: false` for
an output checked but not declared in the overlay. `cases` run the binary: an `id`, the
`output`, the whole `argv`, the `exit_codes` accepted, an `expect` schema the output must also
satisfy, and `records` for a JSON lines count.

`overlay.nu <manifest>` prints the overlay declaring each attached output with its schema
embedded, for `nus generate --overlay`. `lib.nu` runs a suite, holding the binary's raw stdout
to the schemas through `nus validate` before anything decodes it.
