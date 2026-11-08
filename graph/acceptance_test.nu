use std/assert
use std/testing *
use common.nu checked
use discovery.nu discover

const repository = path self | path dirname | path dirname
const refusal = 'project graph changed; run the command again'

# Each case owns a JJ workspace and an independent Git baseline, since mise's
# affected selector reads Git changes. No main-workspace snapshot or ref is changed.
def isolated [label: string, change: closure, verify: closure, --refuses] {
    let temporary = mktemp -d | path expand
    let name = 'nusage-acceptance-' + (random uuid)
    let workspace = $temporary | path join workspace
    let outcome = try {
        do {
            cd $repository
            # Full sparsity skips JJ's initial sparse-pattern mutation. The ignored
            # source workspace stays untouched; checkout happens only below.
            checked jj --ignore-working-copy workspace add --no-colocate --sparse-patterns full --name $name --revision @ $workspace | ignore
        }
        let row = with-env {
            MISE_TRUSTED_CONFIG_PATHS: $workspace
            MISE_IGNORED_CONFIG_PATHS: ''
            MISE_AFFECTED_BASE: HEAD
            MISE_AFFECTED_HEAD: HEAD
            MISE_AFFECTED_COMMITTED: 'false'
            MISE_AFFECTED_UNTRACKED: 'false'
            MISE_AUTO_INSTALL: 'false'
            GIT_CONFIG_NOSYSTEM: '1'
            GIT_CONFIG_GLOBAL: '/dev/null'
        } {
            cd $workspace
            hide-env --ignore-errors NUSAGE_GRAPH_ACTIVE MISE_TASK_NAME MISE_TASK_DIR MISE_CONFIG_ROOT MISE_PROJECT_ROOT GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG GIT_CONFIG_COUNT
            checked jj workspace update-stale | ignore
            assert not ('.git' | path exists) 'The JJ workspace must not inherit Git metadata'
            checked git init --quiet | ignore
            assert equal ((checked git rev-parse --show-toplevel) | str trim | path expand) $workspace
            assert equal ((checked git rev-parse --absolute-git-dir) | str trim | path expand) ($workspace | path join .git)
            checked git add --all | ignore
            checked git -c user.name=Acceptance -c user.email=acceptance@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null commit --quiet --message baseline | ignore
            let first = ^mise tasks ls --all | complete
            assert ($first.exit_code != 0 and ($first.stderr | str contains $refusal)) $first.stderr
            checked mise tasks ls --all | ignore
            let graph = checked mise tasks graph --json | from json | get projects
            # This test-local executable delegates reads to the built binary. A build
            # would replace only the local launcher, never the source installation.
            mkdir target/install/bin
            let binary = $repository | path join target install bin nus
            let quoted = "'" + ($binary | str replace --all "'" "'\"'\"'") + "'"
            '#!/bin/sh' + (char nl) + 'exec ' + $quoted + ' "$@"' + (char nl) | save target/install/bin/nus
            checked chmod +x target/install/bin/nus | ignore
            do $change $workspace
            if $refuses {
                let first = ^mise run --affected --affected-json --affected-uncommitted '//...:check' | complete
                assert ($first.exit_code != 0 and ($first.stderr | str contains $refusal)) $first.stderr
            }
            let affected = checked mise run --affected --affected-json --affected-uncommitted '//...:check' | from json
            let details = do $verify $affected $graph | default {}
            let row = {row: $label, passed: true, selected: ($affected.projects | get id | sort), tasks: ($affected.tasks | get name | sort)}
            $row | merge $details
        }
        {row: $row, error: null}
    } catch {|error| {row: null, error: $error} }
    let forgotten = do {
        cd (if ($workspace | path join .jj | path exists) { $workspace } else { $repository })
        ^jj --ignore-working-copy workspace forget $name | complete
    }
    rm -rf $temporary
    assert equal $forgotten.exit_code 0 $forgotten.stderr
    if $outcome.error != null { error make $outcome.error }
    print ($outcome.row | to json --raw)
}

def append-file [file: string, text: string] {
    checked git ls-files --error-unmatch -- $file | ignore
    $text | save --append $file
}
def selected [result: record] { $result.projects | get id | sort }
def contains [result: record, required: list<string>] {
    assert ($required | all {|id| $id in (selected $result) }) ($result | to nuon)
}
def excludes [result: record, forbidden: list<string>] {
    assert ($forbidden | all {|id| $id not-in (selected $result) }) ($result | to nuon)
}
def downstream [projects: list, start: string] {
    mut reached = [$start]
    loop {
        let next = $projects | where {|p| $p.id not-in $reached and ($p.dependencies | any {|id| $id in $reached }) } | get id
        if ($next | is-empty) { break }
        $reached = $reached ++ $next
    }
    $reached | sort
}

@test
def "spec edits select downstream crates and tool consumers" [] {
    isolated spec {|_| append-file crates/nusage-spec/src/lib.rs "\n// acceptance\n" } {|result, graph|
        let cargo = $graph | where id =~ '^cargo:'
        let expected = downstream $cargo 'cargo:nusage-spec'
        assert equal (selected $result | where $it =~ '^cargo:') $expected
        let records = with-env {NUSAGE_GRAPH_ACTIVE: '1', NUSAGE_GRAPH_NU: $nu.current-exe} {
            let snapshot = $env.PWD | path join target provider-discovery.json
            let tasks = checked mise tasks ls --all --hidden --json | from json --strict
            discover $env.PWD $tasks | to json --raw | save $snapshot
            checked mise run --force --no-deps --raw //graph/cargo:provider $env.PWD --discovery $snapshot | lines | each { from json --strict }
        }
        contains $result ($records | where kind == edge and type == tool | get from | uniq)
        excludes $result ['cargo:openapi-usage' 'nu:mergiraf']
    }
}

@test
def "openapi edits select only its crate and package among those kinds" [] {
    isolated openapi {|_| append-file crates/openapi-usage/src/main.rs "\n// acceptance\n" } {|result, graph|
        contains $result ['cargo:openapi-usage' 'catalog:typesafe']
        excludes $result ($graph | where {|p| (($p.id | str starts-with 'cargo:') and $p.id != 'cargo:openapi-usage') or (($p.id | str starts-with 'catalog:') and $p.id != 'catalog:typesafe') } | get id)
    }
}

@test
def "fixture edits schedule only the nusage test and verification" [] {
    isolated fixtures {|_| append-file crates/nusage/fixtures/README.md "\nAcceptance fixture.\n" } {|result, graph|
        excludes $result ($graph | where id =~ '^cargo:' | get id)
        let tasks = checked mise tasks ls --all --json | from json
        let scheduled = $result.tasks | get name
        let fixture = $tasks | where {|task| $task.name in $scheduled } | get depends | flatten | sort
        assert equal $fixture ['//crates/nusage:test' '//crates/nusage:verify-fixtures']
        {scheduled: $fixture}
    }
}

@test
def "gh exporter manifest and source select its Go project and package" [] {
    for file in [go.mod main.go] {
        isolated $"gh-($file)" {|_| append-file ($'catalog/packages/gh/spec/($file)') "\n// acceptance\n" } {|result, graph|
            let go = $graph | where root == 'catalog/packages/gh/spec' | get id.0
            contains $result [$go 'catalog:gh']
            excludes $result (['catalog:jj' 'catalog:mise'] ++ ($graph | where id =~ '^cargo:' | get id))
        }
    }
}

@test
def "jj package edits select only that package" [] {
    isolated jj {|_| append-file catalog/packages/jj/jj.usage.kdl "\n// acceptance\n" } {|result, _|
        assert equal (selected $result) ['catalog:jj']
    }
}

@test
def "marker dependency changes refuse once then use the new graph" [] {
    isolated marker --refuses {|_|
        open --raw actions/mise.toml | str replace '[_.nusage.project]' ('[_.nusage.project]' + (char nl) + 'depends_add = ["cargo:openapi-usage"]') | save --force actions/mise.toml
    } {|result, _|
        contains $result ['nu:actions']
        let graph = checked mise tasks graph --json | from json | get projects
        assert ('cargo:openapi-usage' in ($graph | where id == 'nu:actions' | get dependencies.0))
    }
}

@test
def "root mise changes select every project" [] {
    isolated root {|_| append-file mise.toml "\n# acceptance\n" } {|result, graph|
        assert equal (selected $result) ($graph | get id | sort)
    }
}
