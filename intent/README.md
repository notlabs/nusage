# intent

The direction, written as what it can be held to before anything is built for it: claims,
traits and schemas, not a design. Nothing here is settled or chosen. A claim is added,
changed or deleted as freely as code, and a disputed one is reworded where it stands.

- `traits.nuon`: the properties the claims name, what each means, how it carries across a
  call, and what can establish it: the analysis, a declaration in a header, which is where
  review looks as it looks at Rust's `unsafe`, or the runtime.
- `claims/*.nuon`: a file per topic, a sentence per claim. `open` until something holds
  nusage to it, `checked` when `check.nu` does. What a claim leaves undecided is under
  `open`; the ways it could be met, none chosen, under `alternatives`.
- `*.schema.json`: the shape of those files, and the graph's words the examples use.
- `check.nu`, `mise run //intent:check`, which CI runs: holds the files to the schemas and
  their names to each other, and the checked claims to today's `nusage prelude`.
- `claims.nu`, `mise run //intent:claims [topic] [--status open|checked]`: the claims as a
  table.

The runner is disposable, as is anything later built to meet a claim. A claim moves to
`checked` when something can hold the code to it: a check here while that is cheap, a test
beside the code once the code exists.
