#!/usr/bin/env nus
#MISE description="Check PR status summaries without contacting GitHub"
#MISE depends=["^build"]
#MISE sources=[".mise/lib/pr-status.nu", ".mise/tasks/check-pr-status.nu", ".mise/tasks/pr-status.nu", "catalog/lib/gh/mod.nu", "catalog/lib/gh/schemas/examples.nuon"]
#MISE outputs=[]
use std/assert
use ../lib/pr-status.nu report

let base = {
    number: 1
    title: base
    headRefName: feature
    baseRefName: main
    headRefOid: aaaa
    isCrossRepository: false
    isDraft: false
    reviewDecision: APPROVED
    mergeable: MERGEABLE
    mergeStateStatus: CLEAN
    statusCheckRollup: null
    url: "https://example.test/pr/1"
}

let checks = [
    {
        __typename: CheckRun
        name: linux
        status: COMPLETED
        conclusion: SUCCESS
        detailsUrl: "https://example.test/check/1"
    }
    {
        __typename: CheckRun
        name: macos
        status: IN_PROGRESS
        conclusion: ""
        detailsUrl: "https://example.test/check/2"
    }
    {
        __typename: CheckRun
        name: lint
        status: COMPLETED
        conclusion: FAILURE
        detailsUrl: "https://example.test/check/3"
    }
    {
        __typename: CheckRun
        name: old
        status: COMPLETED
        conclusion: CANCELLED
        detailsUrl: ""
    }
    {
        __typename: CheckRun
        name: optional
        status: COMPLETED
        conclusion: NEUTRAL
        detailsUrl: ""
    }
    {
        __typename: CheckRun
        name: future
        status: COMPLETED
        conclusion: NEW_STATE
        detailsUrl: ""
    }
    {
        __typename: StatusContext
        context: external
        state: ERROR
        targetUrl: "https://example.test/status"
    }
    {
        __typename: StatusContext
        context: waiting
        state: EXPECTED
        targetUrl: ""
    }
]

let child = $base | merge {number: 2, headRefName: next, baseRefName: feature, statusCheckRollup: $checks, mergeStateStatus: BLOCKED}
# A fork with the same branch name is not the parent of a base-repository branch.
let fork = $base | merge {number: 3, isCrossRepository: true}
let rows = report [$child $fork $base]
assert equal ($rows | get number) [1 2 3]
assert equal $rows.1.depends_on [1]
assert equal $rows.1.passed 1
assert equal $rows.1.failed 2
assert equal $rows.1.pending 2
assert equal $rows.1.cancelled 1
assert equal $rows.1.skipped 1
assert equal $rows.1.unknown 1
assert equal $rows.1.merge_state BLOCKED
assert equal $rows.1.checks.6.name external
assert equal $rows.1.checks.6.url "https://example.test/status"
assert equal $rows.0.checks []
assert equal $rows.0.passed 0
assert equal (report []) []

# Exercise the public script and its generated wrapper, including typed numeric flags.
const root = path self | path dirname | path dirname | path dirname

let scratch = mktemp -d

let outcome = try {
    let fixture = open ($root | path join catalog lib gh schemas examples.nuon) | where id == bot-author | first | get document
    [$fixture] | to json | save ($scratch | path join response.json)
    '#!/usr/bin/env nu
def --wrapped main [...args: string] {
    $args | to json | save --force $env.PR_STATUS_ARGS
    open --raw $env.PR_STATUS_RESPONSE
}
' | save ($scratch | path join gh)
    ^chmod +x ($scratch | path join gh)
    with-env {
        PATH: ($env.PATH | prepend $scratch)
        PR_STATUS_ARGS: ($scratch | path join args.json)
        PR_STATUS_RESPONSE: ($scratch | path join response.json)
    } {
        let result = ^nus ($root | path join .mise tasks pr-status.nu) --repo example/repo --limit 7 --json | complete
        assert equal $result.exit_code 0 $result.stderr
        assert equal ($result.stdout | from json | get 0.number) 7
        let args = open ($scratch | path join args.json)
        let limit = $args | enumerate | where item == "--limit" | first | get index
        assert equal ($args | get ($limit + 1)) "7"
        assert equal ($args | where $it == "--limit" | length) 1
    }
    null
} catch {|err| $err }
rm -rf $scratch
if $outcome != null { error make $outcome }
print "PR status: stacks, forks, failed/pending checks and absent checks"
