# Fixtures

Each directory holds a source (`script.nu`, a `<bin>/` tree, or `<bin>.usage.kdl`, with a
`<bin>.overlay.kdl` merged onto it when present), the module the generator must produce for it
byte for byte (`expected/<bin>.nu`), the parsed signatures that module yields
(`expected/signatures.nuon`), and cases (`cases/*.nuon`). `verify.nu` runs the cases against
the Nushell that runs it, and a single script's cases also through the `nus` interpreter
when the binary is built. A binary module completes through the `usage` CLI, so its completion
checks need it on `PATH`.

A script case is `{argv, invoke?, usage, output?, printed?, complete?}`: `argv` is what the
interpreter receives, as `nus <script> ...argv` parses it; `invoke` the Nushell spelling when
it differs; `usage` the record the script must see; `output` what the command returns when that
is not the record; `printed` what it prints before returning it; `complete` a line and the
completions expected at its end. A binary case is `{cmd, complete?, invoke?, argv?, stdout?,
output?, error?}`: `invoke` is a call run with the fixture's `fake/<bin>` on `PATH`, a stand-in
that records the argv it received, compared with `argv`, and prints `stdout`; `output` is what
the call returns, or `error` text the failure must mention.

The `$usage` record is `{cmd, args, flags}`. `cmd` is the subcommand path, `[]` at the root.
`args` and `flags` are keyed by the usage name in `snake_case`, and every declared name is
present: an absent switch is `false`, an absent value or optional positional `null`, an absent
variadic or repeatable flag `[]`, an absent count `0`, a declared default applied. A switch
declared on by default stays on unless its `negate` flag is given. Inherited global flags come
first. A KDL type annotation on an arg or output is its Nushell type;
without one a value is `string`, or `path` for `<file>` and `<dir>`. A binary's output may
declare a JSON Schema instead, inline or `schema file=`, which is read as a Nushell type:
`binary-schema` shows what it reads, and what it converts after decoding.

A script that calls another by its path, `./x.nu`, or as `nus x.nu` or `nu x.nu`, calls the
shadow nusage defines for that call: the other script's typed command, named as the call
writes it, which runs it through the interpreter and returns its value, typed as its output
declares, while what it prints passes through. The path is the calling script's: `./x.nu`,
`nus x.nu` and `nu x.nu` all name the `x.nu` beside it, wherever it runs from, where the
external call they replace would look in the working directory; `^./x.nu` is still that
external. The interpreter and the module define the shadows before the script, and `nusage
prelude` writes them as the line that stands in for the script's first where Nushell checks it.
`script-calls` calls `callee.nu` the three ways. The harness runs each script case two more
ways: through the plugin's `nus call`, which runs the script in an engine inside the
plugin's process, and through the module `nus generate --plugin` writes for a session with
the plugin registered, whose shadows call `nus call` without defining it; the value and
what the script prints must be the interpreter's each way.

A task of mise's whose file is a script nusage runs is called the same way, as `mise run
<task>` or `mise r <task>`: the shadow runs the task through mise, which runs what the task
depends on around it, and returns the task's own value. mise is asked what the name means
from the calling script's directory, where the shadow runs it from too. A task mise finds up
to date does not run, and the call returns nothing; `^mise run` is still the external, and
so is a call with mise's own flags before the task.

A spec may describe a service rather than a binary, with the HTTP mapping `openapi-usage`
writes beside it, `<bin>.http.kdl`: then each command's wrapper sends the request the mapping
says, the path parameters from its positionals, the query and headers from its flags, and
the body from its input, typed by the properties the body's schema requires; the response is
decoded as a binary's output is. The service's base URL and credentials are the
environment's, `$env.<BIN>_URL` and `$env.<BIN>_TOKEN`, as the module's helpers say, and the
root says where the service is. `http-petstore` is the petstore through the converter; its
cases name the commands for their signatures, and `tests/http.rs` sends their requests to a
server of its own, since no fake stands in for a service.

A binary's wrapper decodes the one output it asks for. An output is decoded when its
`media_type` names a format Nushell reads (`text/csv`, `application/yaml`, ...), when its
framing is `json` or `jsonl`, or when its declaration carries a `nusage-decode` child whose argument
is the Nushell pipeline that turns the text into a value; the conversions the type declares
follow. `nusage-decode` is nusage's own node, taken out before usage reads the spec, so it lives in an
overlay as readily as in a spec file. `binary-media` shows the readers, `binary-decode` the
pipelines.
