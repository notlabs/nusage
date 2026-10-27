# Decision register before implementation

Only decisions with more than one viable answer. Ordered by how open they are: the confidence
figure is how sure I am that the recommended option is the right one, so the top of the list is
where a conversation changes the most. Settled things (`run` over `source`, nufmt-stable
layout, no Nushell crate at runtime, the `$usage` record shape, globals-first ordering,
`int`/`list` for count and repeated flags, `scope commands` over help snapshots, the
interpreter deferred) are left out.

## 1. Attribute vocabulary shape — 55%

What the non-signature usage properties look like as Nushell attributes.

- **Per property** (`@requires key [identity]`, `@required-if-eq token mode remote`,
  `@env key APP_KEY`): reads like the usage reference, one alias per property in the shared
  `attrs.nu`, greppable. Costs: around twenty-five aliases, and names collide with built-ins
  (`@complete`, `@deprecated`, `@example` exist), so usage's `complete` needs a prefix.
- **Per parameter** (`@param key { requires: [identity], env: APP_KEY }`): one alias, one
  attribute per parameter, and `scope commands` yields a record keyed by parameter name, which
  is what a checker wants. Costs: a second mini-grammar inside the record, harder to skim.
- **Per command** (`@usage { ... }` for everything): simplest to emit and consume, least
  readable, and it duplicates names the signature already states.

Recommendation: per property, because the attributes are meant to be read by people next to
the signature, and the checker can regroup. A coin flip against per parameter.

## 2. Where the generated signature lives — 55%

- **Shim module beside the scripts** (current fixtures): scripts stay header plus body,
  `use mycli` gives typed commands, scripts can be sourced by nothing else.
- **A generated `def main` region inside each script**: with 0.117's `run` binding arguments
  to `main` and `nu script.nu` dispatching `def "main sub"`, a script carrying its own
  signature gets typed parsing, help and rejection of unknown flags from Nushell itself, under
  both `run` and the shebang, with no module to `use` and no nusage at run time. Costs:
  generated code inside user files with regeneration discipline, two visible sources of
  truth, and the design's "no signature in the script" rule is gone.

Recommendation: shim module, as designed. The alternative is strong enough that it should be
a documented mode later rather than rejected.

## 3. Where non-signature rules are enforced and resolved — 55%

- **A `nusage resolve` binary** called from the body: usage-lib semantics and messages
  exactly, `validate` expressions, `choices run=`, env fallbacks, `default_if`, origins.
  Costs: a process per call (a few milliseconds, to measure), and the module stops working on
  any machine without nusage.
- **A Nushell-native checker** generated from the attributes or shipped as one library
  module: self-contained modules, no runtime dependency. Costs: reimplementing the presence
  rules, and no `validate` expressions (expr-lang has no Nushell implementation).
- **Hybrid**: native for presence and arity rules, env fallbacks and `default_if`; the binary
  only when a spec uses `validate`.

Recommendation: hybrid, native first. Whichever wins, the call should return the resolved
record (env applied, defaults applied, origins) rather than only pass or fail, so the shim
body stays one line.

## 4. Spec assembly for a directory tree — 60%

- **Per-file headers merged by directory** (`db/migrate.nu` holds its own `arg`/`flag`,
  `mod.nu` holds `name`, `bin`, globals): locality, each file self-describing. Costs: the
  fragments are not a valid usage spec until nusage merges them, so plain `usage` tooling
  (docs, completions, MCP) needs the merged KDL nusage emits.
- **One root spec in `mod.nu`** with the full `cmd` tree, leaf files body-only: a single
  usage-valid spec every usage tool reads unchanged. Costs: the leaf's interface lives far
  from its body.

Recommendation: per-file, with nusage writing the merged spec next to the module so the usage
ecosystem keeps working.

## 5. Where the generated module goes — 60%

- **Committed sibling** (`mycli.nu` next to `mycli/`): `use ./mycli.nu` works for anyone who
  clones, diffs are reviewable, no config hook. Costs: generated code in the repository.
- **Cache directory plus a `use` line in config**: nothing generated in the repo. Costs:
  nusage must run on every machine, staleness is invisible, relative script paths become
  absolute cache-to-repo links.

Recommendation: committed sibling. The pivot to code generation already accepted generated
files; hiding them buys little.

## 6. Channel for Nushell-only typing — 60%

usage-lib rejects unknown keys on `arg` and `flag` (`lib/src/spec/arg.rs:299`,
`flag.rs:435`), so this cannot live inside the usage KDL today.

- **`#NUSAGE` lines in the header** (`#NUSAGE type since=datetime limit=int`): one place,
  one file. Costs: a second directive grammar to document.
- **Sidecar file** (`.<script>.nusage.kdl`, mirroring usage's own `.<script>.usage.kdl`):
  keeps user scripts untouched. Costs: a second file per script.
- **Upstream extension slot in usage** (vendor namespace on nodes): no nusage grammar at all.
  Costs: depends on a maintainer accepting it; not available now.

Recommendation: `#NUSAGE` lines now, sidecar as the twin form, and open the upstream
conversation since usage has shown it tracks Nushell.

## 7. How `$usage` reaches the script under `run` — 65%

- **Free `$usage` declared by the caller**: cleanest for script authors. Relies on `run`
  parsing the script in the caller's scope, which is how it is built but not promised.
- **`$env.nusage`** via `with-env`: documented behaviour. Costs: `$env.nusage.args.name`
  everywhere, and env is a strange home for a typed record.

Recommendation: free variable, with the env form kept as a one-line fallback if `run` ever
parses in a clean scope.

## 8. Staleness and the development loop — 65%

`run` reads the script when the module is parsed, so edits need a re-`use`.

- **Plain `run`**: fastest; stale until re-`use`.
- **`run --full-reparse` always**: edits are live; a reparse per call, cost unmeasured.
- **A dev mode** that emits `--full-reparse` and a prod mode that does not.

Recommendation: measure, then dev mode. If the reparse cost is negligible, always-on wins on
simplicity.

## 9. Minimum Nushell version — 70%

- **0.116 as the floor**, 0.117 features gated: `run` without `main` binding, no `type`
  aliases or `@structured`. Everything in the fixtures works today.
- **0.117 only**: `export type` aliases, `@structured` for the extern generator, `run`
  validating against `main`, custom types in signatures.

Recommendation: 0.116 floor with gated emission, since the shim path needs nothing from 0.117
and the pin can move when 0.117 ships.
