#!/usr/bin/env nus
#USAGE about "Hold mise's affected selection to the checks each kind of change needs"
#MISE description="Hold mise's affected selection to the checks each kind of change needs"
#MISE depends=["//nusage:build"]
use std/assert

def --wrapped git [...args: string] {
    let input = $in
    let result = $input | ^git ...$args | complete
    if $result.exit_code != 0 {
        error make --unspanned {msg: $result.stderr}
    }
    $result.stdout | str trim
}

let root = git rev-parse --show-toplevel
cd $root
let graph = ^mise tasks graph --json | from json | get projects
let roots = open mise.toml | get monorepo.config_roots | sort
assert equal (
    $graph
    | where id =~ '^custom:'
    | get root
    | sort
) $roots
let crates = $graph | where id =~ '^cargo:'
assert ($crates | is-not-empty)
assert ($crates | all {|project| $project.root | str starts-with nusage/crates/ })
let tasks = ^mise tasks ls --all --json | from json | get name
let platform_roots = $roots
assert equal (
    $tasks | where $it =~ ':check:platform$' | sort
) ($platform_roots | each {|root| $"//($root):check:platform" } | sort)

let cases = [
    {path: nusage/crates/nusage/src/lib.rs, roots: $roots}
    {path: nusage/crates/nu_plugin_future/src/lib.rs, roots: $roots}
    {
        path: nusage/fixtures/script/script.nu
        roots: [nusage intent]
    }
    {
        path: intent/claims/identity.nuon
        roots: [intent]
    }
    {
        path: mergiraf/patches/selection-probe.patch
        roots: [mergiraf]
    }
    {path: .mise/lib/actions.nu, roots: $roots}
    {path: Cargo.lock, roots: $roots}
    {path: intent/mise.toml, roots: $roots}
]

# Synthetic children of HEAD change one path each. A private index leaves the
# checkout, real index and refs untouched. Only unreachable Git objects are written;
# mise reads the resulting selection and never executes any selected task.
let base = git rev-parse HEAD
let scratch = mktemp -d
try {
    with-env {
        GIT_INDEX_FILE: ($scratch | path join index)
        GIT_AUTHOR_NAME: "nusage affected check"
        GIT_AUTHOR_EMAIL: "check@nusage.invalid"
        GIT_COMMITTER_NAME: "nusage affected check"
        GIT_COMMITTER_EMAIL: "check@nusage.invalid"
    } {
        let blob = "affected selection probe" | git hash-object -w --stdin
        for case in $cases {
            git read-tree $base | ignore
            git update-index --add --cacheinfo $"100644,($blob),($case.path)" | ignore
            let tree = git write-tree
            let head = "affected selection probe" | git -c commit.gpgsign=false commit-tree $tree -p $base
            for task in [check check:platform] {
                let result = ^mise run --affected --affected-committed --affected-base $base --affected-head $head --affected-json $"//...:($task)" | complete
                if $result.exit_code != 0 {
                    error make --unspanned {msg: $result.stderr}
                }
                let selected = $result.stdout | from json | get tasks | get -o name | default [] | sort
                let expected = $case.roots | where {|root| $task == check or $root in $platform_roots } | each {|root| $"//($root):($task)" } | sort
                if $selected != $expected {
                    error make --unspanned {
                        msg: $"($case.path), ($task): expected ($expected | to nuon), selected ($selected | to nuon)"
                    }
                }
            }
        }
    }
} catch {|err|
    rm -rf $scratch
    error make $err
}
rm -rf $scratch
print $"affected selection: ($cases | length) cases; ($crates | length) Cargo projects; ($roots | length) check roots"
