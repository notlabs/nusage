# mise output schemas

`outputs.nuon` binds JSON Schemas to mise's `--json` outputs, written from the serializers of
mise 2026.10.21 (`61eb04d`, the manifest's `baseline`), each with its source location.
`examples.nuon` holds documents the schemas must accept or reject, and `../schema-fixtures/`
is the project the real mise runs in for the suite, apart from the user's own mise.

An output with `attach: false` is checked but not declared in the generated overlay, since
the module would give it the wrong type:

- `ls`, `ls-remote` and `registry` write one of two shapes, a map or a list, one tool's rows or
  `--all`'s, and the module fills an optional field in whichever shape arrives.
- Each of `tool`'s field filters changes the type of what it writes, and a wrapper has one.
- `env --json-extended` is asked for beside the wrapper's `--json`, which mise prefers.

The module raises when mise exits non-zero, so the report `tasks validate` or `doctor project`
writes with exit status 1 reaches no caller; the suite holds it to its schema all the same.
