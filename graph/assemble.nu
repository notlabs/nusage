#!/usr/bin/env nu
#USAGE arg "<root>"
use common.nu *
use discovery.nu discover
const materialize = path self | path dirname | path join materialize.json
export def project-config [records: list<any>] {
    let projects = $records | where kind == project | sort-by id
    let edges = $records | where kind == edge | sort-by from to type source | uniq
    let ids = ($projects | get id) ++ ($edges | get from) | uniq | sort
    $ids | each {|id|
        let own = $edges | where from == $id
        let project = $projects | where id == $id | get -o 0
        let table = {depends_add: ($own | get to | uniq | sort)}
        let table = if $project != null { $table | insert root $project.root } else { $table }
        let comments = $own | each {|e| $"# ($e.type): ($e.to) at ($e.source)" } | str join (char nl)
        $comments + (char nl) + ({monorepo: {projects: {$id: $table}}} | to toml)
    } | str join (char nl)
}
export def write-tasks [root: string, records: list<any>] {
    let groups = $records | where kind == task | group-by root
    let cache = open ($root | path join mise.toml) | get task_config.cache
    for group in ($groups | transpose root records) {
        let tasks = $group.records | reduce --fold {} {|record, acc| $acc | insert $record.name $record.task }
        let file = $root | path join $group.root .mise conf.d _cargo.toml
        mkdir ($file | path dirname)
        let content = {
            task_config: {cache: $cache}
            tasks: $tasks
        } | to toml
        if not ($file | path exists) or (open --raw $file) != $content {
            $content | save --force $file
        }
    }
}

export def write-graph [root: string, records: list<any>] {
    write-tasks $root $records
    let content = project-config $records
    let file = $root | path join .mise conf.d _projects.toml
    let existed = $file | path exists
    let changed = (not $existed) or ((open --raw $file) != $content)
    if $changed {
        mkdir ($file | path dirname)
        $content | save --force $file
    }
    {
        changed: $changed
        watch_files: (
            $records
            | where kind == input
            | get path
            | each {|p| $root | path join $p | path expand --no-symlink }
            | uniq
            | sort
        )
    }
}
def main [root: path] {
    let root = $root | path expand --no-symlink
    cd $root
    let known_tasks = checked mise tasks ls --all --hidden --json | from json --strict
    let providers = $known_tasks | where {|t| ($t.name | str starts-with '//graph/') and ($t.name | str ends-with ':provider') } | sort-by name
    let temporary = mktemp -d
    let result = try {
        let snapshot = $temporary | path join discovery.json
        # Config/project sources do not depend on generated Cargo fragments.
        # Discover them while every provider receives the empty materialization
        # contract; mise then supplies the complete normalized task definitions.
        let phases = [
            {name: discovery, run: { discover $root $known_tasks }}
            {name: materialize, run: {
                let tasks = run-providers $providers $root $materialize
                write-tasks $root $tasks
                null
            }}
        ] | par-each {|phase| {name: $phase.name, value: (do $phase.run)} } | transpose -r -d
        let tasks = checked mise tasks ls --all --hidden --json | from json --strict | where global == false
        $phases.discovery | update tasks $tasks | to json --raw | save $snapshot
        let records = run-providers $providers $root $snapshot
        write-graph $root ($records ++ [(input $materialize)])
    } catch {|err| {failure: $err} }
    rm -rf $temporary
    if $result.failure? != null { error make $result.failure }
    $result | insert nu $nu.current-exe | to json --raw | print
}

export def run-providers [providers: list<any>, root: string, discovery: path] {
    $providers | par-each {|provider|
        try {
            let records = with-env {NUSAGE_GRAPH_NU: $nu.current-exe} { checked mise run --jobs 1 --force --no-deps --raw $provider.name $root --discovery $discovery } | lines | where $it != '' | each {
                let row = from json --strict
                match $row.kind {
                    project => { {kind: $row.kind, id: $row.id, root: $row.root} }
                    edge => { {kind: $row.kind, from: $row.from, to: $row.to, type: $row.type, source: $row.source} }
                    task => { {kind: $row.kind, root: $row.root, name: $row.name, task: $row.task} }
                    input => { {kind: $row.kind, path: $row.path} }
                }
            }
            {provider: $provider.name, records: ($records | each {|row| {key: ($row | to json --raw), row: $row} } | sort-by key | get row)}
        } catch {|err| error make --unspanned {msg: $"($provider.name): ($err.msg)"} }
    } | sort-by provider | get records | flatten
}
