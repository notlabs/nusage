# GitHub CLI

The command tree of gh **v2.103.3**, exported through Usage's Cobra adapter from a checkout
of [cli/cli](https://github.com/cli/cli) at that tag, with the `pr`, `issue`, `repo`, `run`
and `release` groups in the module and their list and view commands typed. The full spec is
committed as `gh.usage.kdl`; `gh.baseline.overlay.kdl` keeps the module to those groups, and
the other commands remain in the original CLI, `^gh`.

```nu
use gh *

gh pr list --repo notlabs/nusage --state all | select number title state author.login
gh repo view notlabs/nusage | get defaultBranchRef.name
gh run list --repo notlabs/nusage --limit 5 | where conclusion != success
gh release view v0.1.1 --repo notlabs/nusage | get assets | select name size
```

The package calls the `gh` on PATH with the user's own authentication; the catalog's `check`
pins it to the version the spec describes.

## The typed outputs

gh selects JSON with `--json` and a list of fields, from those each command records in its
`help:json-fields` annotation; `json-fields.json` lists them per command, exported with the
spec. So an output is not a format a switch names, as mise's `--json` is, but a selection:
`schemas/outputs.nuon` gives each typed command the field list its schema describes, which
the wrapper passes as `--json <fields>`, and `gh.typed.overlay.kdl` hides `--jq` and
`--template`, which rewrite the selection, `--web`, which opens a browser instead, and `run
view`'s log flags.

| Command | Output | Fields |
| --- | --- | --- |
| `pr list`, `pr view` | a pull request, or a table of them | number, title, state, isDraft, url, author, head and base ref names, the times, labels, reviewDecision, body |
| `pr checks` | a table of checks | name, state, startedAt, completedAt, link, bucket, event, workflow, description |
| `issue list`, `issue view` | an issue, or a table of them | number, title, state, stateReason, url, author, the times, labels, assignees, body |
| `repo view`, `repo list` | a repository, or a table of them | name, nameWithOwner, owner, description, url, the `is*` flags, defaultBranchRef, the counts, the times |
| `run list`, `run view` | a run, or a table of them | databaseId, number, attempt, the names, headBranch, headSha, event, status, conclusion, the times, url |
| `release list` | a table of releases | name, tagName, the `is*` flags, createdAt, publishedAt |
| `release view` | a release with its assets | tagName, name, body, the `is*` flags, the times, targetCommitish, url, author, assets |

Each schema follows the exporter in cli/cli, which `outputs.nuon` names per output: an
author is `{is_bot, login}` with `id` and `name` for a user, a time is RFC 3339 and decodes
to a datetime, a time that may be absent is null. A field the selection does not name is
refused, so a schema says exactly what a wrapper returns. `search`, `api` and the other
groups wait for their outputs to be declared the same way; `json-fields.json` says which
take `--json`.

## Check

`check-schemas.nu` holds gh's raw JSON to the schemas, `check.nu` drives the module. Both
read this repository on GitHub and so need a token, `GH_TOKEN` or `GITHUB_TOKEN`; without one
they check the examples and stop, which CI, where the workflow's token is set, counts as a
failure. The user's configuration stays out of both: a scratch `GH_CONFIG_DIR`, the token
from the environment, no prompt.

## Regenerate

From the repository root:

```sh
mise run //catalog:spec gh
mise run //catalog/cobra:gh-json-fields
mise run //catalog:generate gh
mise run //catalog:check gh
```

`spec` clones cli/cli at the tag `spec/pin.toml` names under the user's cache directory,
holds the checkout to the pinned commit, and builds the extractor there, as
[`../../cobra/README.md`](../../cobra/README.md) describes; the first run downloads Go's
modules and, when the one on PATH is older, the toolchain the module asks for. A new gh
version is a new tag and commit in `pin.toml` and a new version in the catalog's `check`
task, then the four commands; `outputs.nuon`'s baseline names the revision the schemas were
read at.

Unlike Compose's, the spec is not reproducible from this repository alone: the extractor
builds in a checkout outside it, with the adapter added at run time, and
`//catalog/cobra:check` reproduces Compose's export, not gh's. So `check` holds the spec to
the tool on PATH by version only, and a change in what the extractor would export, from the
adapter or from the extractor itself, shows up only when someone runs `spec` again, which
the `check` of a bumped `pin.toml` then reviews as a diff of the committed spec. That is the
trade-off the construction boundary forces; a public construction helper upstream would
remove it.

## What the extractor normalizes

Three things in `spec/main.go`, each a limit of the adapter at Usage 7.1.3, to remove when
the adapter changes:

- A command's own persistent flag is written twice, once `global=#true`, and usage keeps the
  last, so `pr list` would lose `--repo`; the second is dropped.
- An alternation in a Use line, `[<number> | <url> | <branch>]`, yields no positional; it
  becomes one, `number-or-url-or-branch`, optional or required as the brackets say. And a
  group's `<command>` placeholder, which the adapter would read as a positional, is dropped.
- Reserved words and signed numbers as defaults are quoted, as for Compose.

`release verify` and `release verify-asset` take `[<tag>] <asset>`, an optional positional
before a required one, which a Nushell signature cannot say; they are hidden.
