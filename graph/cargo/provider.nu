#!/usr/bin/env nu
use ../common.nu *
const here = path self | path dirname

const inputs = [
    "../../Cargo.toml"
    "../../Cargo.lock"
    "../../.cargo/**"
    "../../rust-toolchain.toml"
]
export def tasks-from [metadata: record, templates: record] {
    let packages = $metadata.packages | where {|p| $p.id in $metadata.workspace_members }
    let nodes = $metadata.resolve.nodes | group-by id
    $packages | each {|package|
        let directory = $package.manifest_path | path dirname
        let root = relative $metadata.workspace_root $directory
        mut reached = []
        mut frontier = [$package.id]
        while ($frontier | is-not-empty) {
            let next = $frontier | each {|id| $nodes | get $id | get dependencies.0 } | flatten | uniq | where {|id| $id not-in $reached }
            $reached = $reached ++ $next | uniq
            $frontier = $next
        }
        let deps = $packages | where {|p| $p.id in $reached } | get manifest_path | each {|manifest|
            let dir = $manifest | path dirname | path basename
            $"../($dir)/**/*"
        } | sort
        let sources = ["**/*"] ++ $deps ++ $inputs
        $templates | items {|name, task|
            {kind: task, root: $root, name: $name, task: (if $name in [test clippy doc] { $task | insert sources $sources } else { $task })}
        }
    } | flatten
}
export def tool-edges [data: record, metadata: record, root: string] {
    let binaries = $metadata.packages | where {|p| $p.id in $metadata.workspace_members } | each {|p|
        $p.targets | where {|t| 'bin' in $t.kind } | each {|t| {bin: $t.name, id: $"cargo:($p.name)"} }
    } | flatten
    let targets = $binaries | where bin == nus
    $targets | each {|tool|
    $data.tasks | each {|task|
        let base = task-root $task.name
        let file = if $task.file? != null { $root | path join $base $task.file | path expand --no-symlink }
        let shebang = $file != null and ($file | path exists) and ((open --raw $file | lines | first) == '#!/usr/bin/env nus')
        if $shebang or 'github:notlabs/nusage' in ($task.tools | columns) {
            let from = owner $data.projects $base
            if $from.id != $tool.id { {kind: edge, from: $from.id, to: $tool.id, type: tool, source: (if $shebang { $"(relative $root $file):1" } else { task-location $root $task })} }
        }
    } | compact
    } | flatten | uniq
}
def main [root: path = ".", --discovery: path] {
    let root = $root | path expand --no-symlink
    cd $root
    let metadata = checked cargo metadata --format-version 1 --locked | from json --strict
    let data = load-discovery $discovery
    (
        (tasks-from
            $metadata
            (open ($here | path join tasks.toml))
        )
    ) ++ (tool-edges $data $metadata $root) ++ (
        $metadata.packages
        | where {|p| $p.id in $metadata.workspace_members }
        | get manifest_path
        | each { input $in }
    ) ++ [
        (input 'Cargo.lock')
        (input 'Cargo.toml')
        (input ($here | path join provider.nu))
        (input ($here | path join tasks.toml))
        (input ($here | path join ../common.nu | path expand --no-symlink))
    ] ++ (discovery-inputs $data)
    | emit
    | print
}
