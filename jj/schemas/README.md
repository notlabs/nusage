# jj output schemas

`outputs.nuon` binds JSON Schemas to the JSON lines jj writes for the template `json(self)`,
written from the serializers of jj 0.46.0, the jj-cli, jj-lib and jj-core crates at that
version, each with its source locations: commits for `log`, evolution entries for `evolog`,
operations for `operation log`, refs for `bookmark list` and `tag list`, workspaces for
`workspace list`, values for `config list`. Each is asked for with `--template 'json(self) ++
"\n"'`, and `--no-graph` where a graph would frame the lines; the overlay declares those words
as the output's `nusage-args`, so the wrapper passes them and owns both flags, and `^jj` takes
any other template.

`examples.nuon` holds documents the schemas must accept or reject, such as a conflicted ref's
target or a TOML datetime in the configuration. `mise run //jj:check-schemas` builds a
repository in a home of its own and holds jj's output to the schemas and to each case's
expectation; `--bin` holds another jj to the same.

`log` and `operation log` keep jj's diff flags, `--patch`, `--stat`, `--summary` and the
like, which write a diff after each line that the wrapper cannot decode: `^jj` asks for that.
A configuration value is any TOML value, so its type is `any`. The commands whose template
type does not serialize, `diff`, `show` and the `file` commands, stay text.
