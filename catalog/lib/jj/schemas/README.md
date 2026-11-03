# jj output schemas

`outputs.nuon` binds JSON Schemas to the JSON lines jj writes for the template `json(self)`,
written from jj 0.46.0's serializers, each with its source location: commits for `log`,
evolution entries for `evolog`, operations for `operation log`, refs for `bookmark list` and
`tag list`, workspaces for `workspace list`, values for `config list`. The wrapper passes
`--template 'json(self) ++ "\n"'`, and `--no-graph` where a graph would frame the lines, so it
owns both flags; `^jj` takes any other template. `examples.nuon` holds documents the schemas
must accept or reject.

`jj.typed.overlay.kdl` hides what appends text to the JSON lines or replaces them: the diff
modes and their formatting flags on `log`, `evolog` and `operation log`, and `log --count`. A
configuration value is any TOML value, so its type is `any`. `diff`, `show` and the `file`
commands stay text, since their template types do not serialize.
