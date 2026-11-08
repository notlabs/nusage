#!/usr/bin/env nu
use ../common.nu *
export def records [data: record, root: string] {
    let declared = $data.configs | each {|c|
        let from = owner $data.projects $c.root
        $c.data._?.nusage?.project?.depends_add? | default [] | each {|to|
            if $to not-in ($data.projects | get id) { error make {msg: $"($c.file): unknown project ($to)"} }
            {kind: edge, from: $from.id, to: $to, type: declared, source: (reference-location $root ($root | path join $c.file) $to)}
        }
    } | flatten
    let task_edges = $data.tasks | each {|task|
        let base = task-root $task.name
        let from = owner $data.projects $base
        let targets = $task.depends ++ ($task.run | where {|run| ($run | describe) starts-with record } | each {|run| [$run.task?] ++ ($run.tasks? | default []) } | flatten | compact)
        let calls = $targets | each {|target|
            let name = if ($target | describe) == string { $target } else if ($target | describe) starts-with list { $target.0 } else { $target.task }
            task-targets $data.tasks $name $base | each {|target_root|
                let to = owner $data.projects $target_root
                if $to.id != $from.id { {kind: edge, from: $from.id, to: $to.id, type: task-call, source: (task-location $root $task)} }
            }
        } | flatten
        let dir = relative $root $task.dir
        let to = owner $data.projects $dir
        $calls ++ (if $to.id != $from.id { [{kind: edge, from: $from.id, to: $to.id, type: task-dir, source: (task-location $root $task)}] } else { [] })
    } | flatten
    ($data.registered | each {|p| {kind: project} | merge $p }) ++ $declared ++ $task_edges
}
def main [root: path = ".", --discovery: path] {
    let root = $root | path expand --no-symlink
    let data = load-discovery $discovery
    (records $data $root) ++ (discovery-inputs $data) ++ [
        (input 'graph/markers/provider.nu')
        (input 'graph/common.nu')
    ]
    | emit
    | print
}
