# Cobra

The usage spec of a Go binary built with Cobra, read from its command tree through
[usage's Cobra adapter](https://github.com/jdx/usage/tree/v7.1.3/integrations/cobra) by an
extractor under `../lib/<bin>/spec/`. Go is needed to write the spec, not to use the module.

- Docker Compose: the extractor is a Go module of its own, whose `go.mod` pins Compose and the
  adapter.
- gh: its root command takes packages under `internal/`, which only code inside cli/cli may
  import, so `gh.nu` clones cli/cli at the tag `../lib/gh/spec/pin.toml` names, under the
  user's cache directory, adds the extractor as `cmd/nusage-spec/main.go` and runs it there.
  With `--json-fields` it writes the fields each command's `--json` accepts to
  `../lib/gh/json-fields.json`.

What the adapter gets wrong, each extractor corrects; its comments say what, and until when.
