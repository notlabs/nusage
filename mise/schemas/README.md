# mise output schemas

`outputs.nuon` binds JSON Schemas to mise's `--json` outputs, written from the serializers at
the mise the root pins, each with its source locations; `examples.nuon` holds documents the
schemas must accept or reject; `../schema-fixtures/` is the project `check-schemas.nu` runs
the real mise in, isolated from the user's mise. `mise run //mise:check-schemas` holds the
schemas to their metaschema, the examples to the schemas, and mise's output to both the
schema and each case's expectation; `--bin` holds another mise to the same. An output with
`attach: false` is checked but not declared in the generated overlay.
