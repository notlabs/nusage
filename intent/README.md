# intent

Where the project is going, written as what it can be held to before anything is built for it:
claims, traits and schemas, not a design. Nothing here is settled; a claim is added, changed,
reworded or deleted as freely as code.

- `traits.nuon`: the properties the claims name, what each means, how it carries across a
  call, and what can establish it: the analysis, a declaration in a header, or the runtime.
- `claims/*.nuon`: a file per topic, a sentence per claim, `open` until something holds nusage
  to it and `checked` when `check.nu` does. What a claim leaves undecided is under `open`, and
  the ways it could be met, none chosen, under `alternatives`.
- `*.schema.json`: the shape of those files.
- `check.nu`, which CI runs: the files against the schemas and each other, and the checked
  claims against today's `nus prelude` and `nus inspect`.
- `claims.nu [topic] [--status open|checked]`: the claims as a table.

A claim moves to `checked` when something can hold the code to it: a check here while that is
cheap, a test beside the code once the code exists.
