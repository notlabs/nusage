# GitHub CLI

gh's command tree at v2.103.3, exported through usage's Cobra adapter, with the `pr`, `issue`,
`repo`, `run` and `release` groups in the module and their list and view commands typed;
`gh.baseline.overlay.kdl` keeps the module to those groups, and the rest stays with `^gh`. It
calls the `gh` on PATH, with the user's own authentication.

```nu
use gh *

gh pr list --repo notlabs/nusage --state all | select number title state author.login
gh run list --repo notlabs/nusage --limit 5 | where conclusion != success
```

gh selects JSON with `--json` and a list of fields, so each typed command passes the fields its
schema describes, as `schemas/outputs.nuon` lists them; `gh.typed.overlay.kdl` hides `--jq`,
`--template` and `--web`, which replace that output, and `run view`'s log flags.

| Command | Output | Fields |
| --- | --- | --- |
| `pr list`, `pr view` | a pull request, or a table of them | number, title, state, isDraft, url, author, head and base ref names, the times, labels, reviewDecision, body, headRefOid, isCrossRepository, mergeable, mergeStateStatus, statusCheckRollup |
| `pr checks` | a table of checks | name, state, startedAt, completedAt, link, bucket, event, workflow, description |
| `issue list`, `issue view` | an issue, or a table of them | number, title, state, stateReason, url, author, the times, labels, assignees, body |
| `repo view`, `repo list` | a repository, or a table of them | name, nameWithOwner, owner, description, url, the `is*` flags, defaultBranchRef, the counts, the times |
| `run list`, `run view` | a run, or a table of them | databaseId, number, attempt, the names, headBranch, headSha, event, status, conclusion, the times, url; `run view` also includes jobs and their steps |
| `release list` | a table of releases | name, tagName, the `is*` flags, createdAt, publishedAt |
| `release view` | a release with its assets | tagName, name, body, the `is*` flags, the times, targetCommitish, url, author, assets |

An author is `{is_bot, login}`, with `id` and `name` for a user; a time decodes to a datetime,
and one that may be absent is null; check-rollup timestamps stay strings, as its two kinds of
record differ. A field the selection does not name is refused, so a schema says exactly what a
wrapper returns. `json-fields.json` says which other commands take `--json`.

The checks read this repository on GitHub, so they need `GH_TOKEN` or `GITHUB_TOKEN`.
