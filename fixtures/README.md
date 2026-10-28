# Fixtures

Each directory holds a source (`script.nu`, a `<bin>/` tree, or `<bin>.usage.kdl`, with a
`<bin>.overlay.kdl` merged onto it when present), the module the generator must produce for it
byte for byte (`expected/<bin>.nu`), the parsed signatures that module yields
(`expected/signatures.nuon`), and cases (`cases/*.nuon`). `verify.nu` runs the cases against
the Nushell that runs it, and a single script's cases also through the `nusage` interpreter
when the binary is built.

A script case is `{argv, invoke?, usage, output?, complete?}`: `argv` is what the interpreter
receives, as `nusage <script> ...argv` parses it; `invoke` the Nushell spelling when it differs;
`usage` the record the script must see;
`output` what the command returns when that is not the record; `complete` a line and the
completions expected at its end. A binary case is `{cmd, complete?, invoke?, argv?, stdout?,
output?}`: `invoke` is a call run with the fixture's `fake/<bin>` on `PATH`, a stand-in that
records the argv it received, compared with `argv`, and prints `stdout`; `output` is what the
call returns.

The `$usage` record is `{cmd, args, flags}`. `cmd` is the subcommand path, `[]` at the root.
`args` and `flags` are keyed by the usage name in `snake_case`, and every declared name is
present: an absent switch is `false`, an absent value or optional positional `null`, an absent
variadic or repeatable flag `[]`, an absent count `0`, a declared default applied. A switch
declared on by default stays on unless its `negate` flag is given. Inherited global flags come
first. A KDL type annotation on an arg or output is its Nushell type;
without one a value is `string`, or `path` for `<file>` and `<dir>`.
