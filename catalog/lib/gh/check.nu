#!/usr/bin/env nu
# Drives gh through the module: each typed call decodes to the data it declares. The catalog's
# `check` runs this with `lib` included, as a user's `use gh *` finds the module. The calls
# read this repository on GitHub, so they need a token, `GH_TOKEN` or `GITHUB_TOKEN`; without
# one the script says so and stops, a failure in CI, where the workflow's token is there.
use std/assert
use gh *

let token = $env.GH_TOKEN? | default $env.GITHUB_TOKEN? | default ""
if ($token | is-empty) {
    if ($env.CI? | default "") == "true" {
        error make --unspanned {msg: "the module is driven against GitHub: set GH_TOKEN"}
    }
    print "gh: no GH_TOKEN or GITHUB_TOKEN, so the module is not driven here"
    exit 0
}

let dir = mktemp --directory
with-env {GH_CONFIG_DIR: $dir, GH_TOKEN: $token, GH_PROMPT_DISABLED: "1", GH_NO_UPDATE_NOTIFIER: "1", NO_COLOR: "1"} {
    # A record, its times decoded.
    let repo = gh repo view notlabs/nusage
    assert equal $repo.nameWithOwner "notlabs/nusage"
    assert equal $repo.defaultBranchRef.name main
    assert equal ($repo.createdAt | describe) datetime

    # Tables, each row as the schema says: an author is a record, a label list a list.
    let prs = gh pr list --repo notlabs/nusage --state all --limit 2
    assert (($prs | describe) | str starts-with "table<")
    assert (($prs | length) > 0)
    assert equal ($prs.0.author | columns | sort) [id is_bot login name]
    assert equal ($prs.0.labels | describe --detailed | get type) list

    let merged = gh pr view 34 --repo notlabs/nusage
    assert equal $merged.number 34
    assert equal $merged.state MERGED
    assert equal ($merged.mergedAt | describe) datetime

    let releases = gh release list --repo notlabs/nusage --limit 5
    assert ("v0.1.1" in ($releases | get tagName))
    let release = gh release view v0.1.1 --repo notlabs/nusage
    assert equal $release.tagName "v0.1.1"
    assert (($release.assets | describe) | str starts-with "table<")

    let runs = gh run list --repo notlabs/nusage --limit 2
    assert (($runs | length) > 0)
    assert equal ($runs.0.databaseId | describe) int

    # A command without a typed output passes gh's text through, the original CLI's.
    let status = gh pr checks 34 --repo notlabs/nusage
    assert (($status | describe) | str starts-with "table<")
}
rm --recursive $dir
