# clap

The usage spec of a binary that ships none, read from the clap command its crate builds, as jj-cli builds jj's.
The extractor is a binary crate in a workspace of its own under `../lib/<bin>/spec/`: its `Cargo.toml` names the binary and its crate under `[package.metadata.clap-spec]` and depends on `clap-spec = { path = "../../../clap" }` and on the crate at `=<version>`, with the features its release is built with; its `main.rs` passes the crate's command, with whatever the binary's own `main` adds to it, to `clap_spec::main`.
The entry is `spec = { clap = "spec" }`.

`spec.nu` moves the extractor to the version of the binary on PATH, builds and runs it, and writes the spec with the extractor's `Cargo.lock`.
Compiling the crate is slow, so the spec is committed and written again only for a new version.
A crate whose command is private to its `main` needs a fork that makes it a library function; `spec.nu` does not move a fork.
