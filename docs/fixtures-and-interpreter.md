# Fixtures first, then the interpreter, then the generator

Fourth note. Three questions: is there a corpus to use as before/after targets, which
library to emit code with, and whether the shebang-interpreter idea can be a wrapper
rather than an engine embedding.

Checked against usage f357a6c and Nushell `main` 36c057c (0.117 line).

## 1. What exists as a corpus, and how to adapt it

usage ships no Nushell fixtures, but it ships four things that are directly reusable:

- **`corpus/*.json`, the argv conformance corpus.** Seventeen files of vectors, each a
  complete spec, an argv, and the parse result it must produce:
  `{"ok": {"cmd": [...], "flags": {...}, "args": {...}}}` or `{"error": "code"}`.
  The README states the contract exactly: values are strings, lists of strings,
  booleans or lists of booleans, "converting it is the caller's business". That is
  the usage-fidelity `$usage` record, already written down as hundreds of test
  cases. Sibling corpora cover completion (`corpus/complete`), help rendering
  (`corpus/render`) and config resolution (`corpus/config`).
- **`examples/`.** Thirty-odd `.usage.kdl` specs from `basic` to `kitchen-sink`, and a
  dozen header scripts (`example.sh`, `test-*.sh`, `.js`, `.py`) with `#USAGE` lines
  under a `usage bash` shebang. The scripts are the shape your `.nu` scripts take;
  only the shebang and the body change.
- **`lib/src/sdk/{typescript,python}/snapshots`.** Spec fixture in, generated client
  out, one snapshot per feature: `minimal_spec`, `deep_nesting`,
  `hyphenated_subcommands`, `choice_collision`, `flags_only_subcommand`,
  `count_flag`, `arg_defaults`, `full_feature_*`. The fixture list is the right
  checklist for which Nushell targets to hand-write; the snapshots show how usage
  itself phrases the before/after discipline.
- **`benches/shadows/*`.** Real specs for mise, hk, fnox, pitchfork, aube, tak,
  communique, plus clap-generated specs for fd, tokei and starship. Stress input for
  the `extern` generator later; not needed for the scripts case.

Suggested layout for nusage's own corpus, hand-written before any generator exists:

```
fixtures/
  minimal/
    script.nu            # #!/usr/bin/env nusage + #USAGE header, no def main
    expected/mod.nu      # the def shim you want the generator to produce, byte for byte
    expected/help.txt    # `nu -c 'use fixtures/minimal/expected; help minimal'` output
    cases/
      no-args.nuon       # { argv: [], usage: { cmd: [], args: {...}, flags: {...} } }
      all-flags.nuon
  subcommands/           # db migrate / db seed, mod.nu with multi-word names
  variadic-choices/      # rest arg, choices → @[a b c], a count flag
  defaults-env/          # default=, env=, a value that comes from the environment
  typed/                 # #NUSAGE type lines, datetime and int coercion
  output-table/          # #NUSAGE output, export type alias, : nothing -> list<Row>
```

Each case is one argv and the `$usage` record it must yield, written as NUON so the
same file drives both entrypoints below. The argv corpus can be converted into
`cases/` mechanically for the interpreter path, with one normalisation: the corpus
omits unset values, while `$usage` should carry every declared arg and flag as
`null`, `false` or `[]` so scripts never need `?` accessors and both entrypoints
produce identical records.

The generator's acceptance test is then byte equality against `expected/mod.nu`,
plus a parse through the pinned `nu` binary. Design in the hand-written files, let
the generator catch up.

## 2. Library choice

Two layers, two tools.

**Declarations: a typed model with one `Display` printer, no library.** Signatures,
attributes, `export type`, doc comments. The model carries the invariants (rest
parameter last, body only on `def`, `@structured` only on `extern`, validated
identifiers that handle `type` as a reserved word and the `--dry-run` → `$dry_run`
rename); the printer owns quoting and layout. A fixed layout rule (one parameter per
line past two, trailing commas) is enough for stable snapshots. The `pretty` crate
is not needed for this subset.

**Bodies: genco with a custom language.** The `$usage` shim body is a short
parametric template, which is what quasi-quoting is for. genco's `Lang` trait has no
required methods: `Config`, `Format` and `Item` can all be unit, and the one override
worth writing is `write_quoted` with Nushell's string escaping. `quote!` handles
indentation from the source layout. genco builds on stable Rust now (it uses span
information available since Rust 1.88; mise pins 1.99). If the body never grows past
three lines, plain `format!` inside the model's printer is honest too; reach for genco
once validation calls or coercions make the body a real template.

**Literals: an emitter you own, verified against `from nuon`.** The `nuon` crate
would be the natural choice but it pulls `nu-protocol` and `nu-engine`, which is the
coupling you are removing. The literal subset the generator and the interpreter emit
is small: string, int, float, bool, null, list, record, and the coerced types from
`#NUSAGE` (datetime, duration, filesize, path). A hand-written emitter for that
subset is under a hundred lines, and a round-trip test through the pinned binary
(`$nuon | from nuon | to nuon`) pins its correctness without any crate dependency.
Copy the two quoting predicates from `nu-utils/src/quoting.rs` rather than depend on
the crate; they are short and the rules are what the parser itself applies.

Net dependency picture: `usage-lib` (+ `usage-argv`), `genco`, an `insta` dev
dependency. No Nushell crate anywhere; the pinned `nu` binary is the only Nushell in
the build, used by tests.

**Kakehashi** (tree-sitter-based bridging of embedded languages to language servers)
does not change any of this. The one thing to keep in mind for it: the header
directives stay line-based (`#USAGE ...`, `#NUSAGE ...`) with a stable prefix, so a
tree-sitter injection query can later hand those comment lines to a KDL grammar.

## 3. The interpreter as a wrapper, not an embedding

The idea is sound, and it is exactly `usage bash` with a typed payload. What `usage
bash` does today (`cli/src/cli/shell.rs`): parse the script's header into a `Spec`,
handle `-h`/`--help` and the `--` separator rules, run `usage::parse::parse(&spec,
&args)`, then spawn the shell on the script with `usage_<name>` environment variables
from `ParseOutput::as_env`. The wrapper for Nushell replaces the last step:

```
nusage /abs/script.nu <args...>          # from #!/usr/bin/env nusage
  → Spec::parse_file(script)
  → usage::parse::parse(&spec, &argv)     # help, errors, completions as usage does them
  → $usage record: ParseOutput, every declared name present, #NUSAGE coercions applied
  → NUON text
  → exec nu [--stdin] -c 'let usage = ($env.NUSAGE_ARGS | from nuon); source /abs/script.nu'
      with NUSAGE_ARGS set, stdin/stdout/stderr inherited
```

Details that decide whether it feels transparent:

- **Pass the record through an environment variable, not the `-c` string**, so no
  quoting of user data ever touches a command line. `from nuon` on the Nushell side is
  the only decoder.
- **`exec` on Unix, spawn-and-wait on Windows.** With `exec` the wrapper vanishes and
  `nu` is the process: exit codes, signals and job control behave as if the script had
  been run directly. `usage bash` spawns and waits, which also works.
- **`--stdin` only when stdin is not a terminal.** It makes piped input available as
  `$in` at the script's top level; on a terminal it would capture input that an
  interactive `input` call wants.
- **File context.** `source` splices the file, so `$env.CURRENT_FILE` and
  `$env.FILE_PWD` may describe the `-c` context rather than the script. Set
  `NUSAGE_SCRIPT` to the absolute path as a known fallback and verify what `source`
  reports in the spike.
- **Also emit the `usage_*` variables.** Free, and it keeps every script that only
  needs a string compatible with the plain `usage` runner.

What the wrapper cannot do is share the caller's scope: a shebang script is a new
process whether `nusage`, `usage bash` or `nu` starts it. That is not a limitation
to work around; it is what the generated `def` shim module is for. The two are the
same contract with two entrypoints:

| Entrypoint             | Who types the arguments        | Fidelity of `$usage`                 | Runs in              |
| ---------------------- | ------------------------------ | ------------------------------------ | -------------------- |
| `nusage script.nu …`   | usage's parser on argv         | usage-level, upgraded by `#NUSAGE`   | a fresh `nu` process |
| `use mycli; mycli …`   | Nushell's parser on the `def`  | Nushell-level                        | the caller's engine  |

A script written against `$usage` cannot tell which one invoked it. The argv corpus
tests the first directly; the hand-written `mod.nu` targets test the second.

Nothing here links a Nushell crate. The wrapper needs `usage-lib`, a NUON emitter and
`std::process`. That is the clean rework of the earlier, engine-coupled attempt, at
the cost every shebang already pays: one `nu` start per script run.

**Upstream angle.** `usage` already models shells as named subcommands with a
`USAGECLI_SHELL_<NAME>` program override. A `usage nu` that sets `$usage` from
`ParseOutput` (strings, bools, lists, every declared name present) is a natural
contribution and would make the base behaviour available without nusage installed.
The `#NUSAGE` coercions and the `def` shim generator stay in nusage, since usage has
no vocabulary for Nushell types.

## Order of work

1. Hand-write the six fixtures above: scripts, expected `mod.nu`, cases, help text.
   This settles the `$usage` shape, naming rules and layout before any code.
2. Build the interpreter wrapper. It is the smaller program, it needs no generator,
   and the argv corpus gives it a test suite on day one.
3. Build the generator against the fixtures: model + printer, genco for the body, own
   NUON emitter. Byte equality with `expected/mod.nu`, then `nu-check` through the
   pinned binary.
4. Only then widen: `#NUSAGE output` with `export type`, the `extern` generator for
   binaries, a `usage nu` proposal upstream.
