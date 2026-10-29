# clap

The usage spec of a binary that ships none, read from the clap command its crate builds.

A binary built with clap often describes its interface nowhere but in that command. When the
crate is also a library that builds it, as jj-cli builds jj's, an extractor reads it there: a
binary crate outside the binary's tree, depending on the library at the version of the binary on
PATH, whose `main` hands the command to `clap_spec::main`. usage converts the command;
`clap-spec` names the binary and its version, and holds the printed spec to usage's reading of
it. `spec.nu` moves the extractor to the version, checks that it builds that version, runs it
and writes the spec under a header naming the crate and the version. Compiling the crate is
slow, so this runs once per version and the spec is committed.

A binary `<bin>` is added to the catalog with:

- `../lib/<bin>/spec/Cargo.toml`: a package in its own workspace (`[workspace]`) that names
  the binary and its crate under `[package.metadata.clap-spec]`, and depends on `clap-spec =
  { path = "../../../clap" }` and on the crate at `=<version>`, with the features its release
  is built with.
- `../lib/<bin>/spec/src/main.rs`: `clap_spec::main(<the crate's function that builds the
  command>())`, plus whatever the binary's own `main` adds to the command that is part of its
  interface.
- Its entry in `../mise.toml`: `[_.nusage.catalog.<bin>]` with `spec = { clap = "spec" }`, the
  extractor's directory under the package, as `jj` has it.

`mise run //catalog:spec <bin>` then writes `<bin>.usage.kdl` and the extractor's
`Cargo.lock`, which are committed together. What the binary knows outside clap, such as the
output a switch selects, goes in an overlay, as for mise.

A crate that keeps its command private to its `main` is forked: the fork's one change makes the
command a library function, and the extractor depends on the fork's tag for the version, `{ git
= "…", tag = "…" }`. `spec.nu` moves only a registry dependency, so a fork is moved by hand, and
it refuses an extractor that builds a version other than the binary's.
