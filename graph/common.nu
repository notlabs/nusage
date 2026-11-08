# Discovery is mise's; markers opt config roots into the graph.
export def --wrapped checked [...argv: string] {
    let result = run-external ...$argv | complete
    if $result.exit_code != 0 { error make --unspanned {msg: $result.stderr} }
    $result.stdout
}
export def relative [root: string, path: string] {
    let value = $path | path expand --no-symlink | path relative-to $root
    if $value == "" { "." } else { $value }
}
export def within [path: string, directory: string] {
    $directory == "." or $path == $directory or ($path | str starts-with ($directory + "/"))
}
export def owner [projects: list<any>, path: string] {
    $projects | where {|p| within $path $p.root } | sort-by {|p| $p.root | str length } | last
}
export def task-root [name: string] {
    let dir = $name | parse --regex '^//(?<root>[^:]*):' | get root.0
    if $dir == "" { "." } else { $dir }
}
export def input [path: string] { {kind: input, path: $path} }
export def emit [] { $in | each { to json --raw } | str join (char nl) }
export def load-discovery [file: path] { open --raw $file | from json --strict }
export def discovery-inputs [data: record] {
    ($data.configs | get file) ++ ($data.tasks | get source | each { path expand --no-symlink }) | uniq | each { input $in }
}
# Resolve literal task references using mise's discovered task names.
export def task-targets [tasks: list<any>, target: string, base: string] {
    let spec = if ($target | str starts-with "./") or ($target | str starts-with "../") {
        let parts = $target | split row ':'
        let dir = (($base | path split) ++ ($parts.0 | path split)) | reduce --fold [] {|part, path|
            match $part {
                '.' => $path
                '..' => ($path | drop 1)
                _ => ($path | append $part)
            }
        } | path join
        $"//($dir):($parts | skip 1 | str join ':')"
    } else if ($target | str starts-with "//") { $target } else if ($target | str starts-with ":") {
        $"//(if $base == '.' { '' } else { $base })($target)"
    } else { $"//(if $base == '.' { '' } else { $base }):($target)" }
    let pattern = '^' + (
        $spec
        | str escape-regex
        | str replace --all '\.\.\.' '[^:]*'
        | str replace --all '\*' '[^:]*'
    ) + '$'
    $tasks | where name =~ $pattern | get name | each { task-root $in } | uniq
}

export def location [root: string, file: string, texts: list<string>] {
    let path = relative $root $file
    let index = open --raw $file | lines | enumerate | where {|line| ($line.item | str trim) in $texts } | get -o index.0 | default 0
    $"($path):($index + 1)"
}
export def task-location [root: string, task: record] {
    let name = $task.name | split row ':' | skip 1 | str join ':'
    (location
        $root
        $task.source
        [$"[tasks.($name)]" $'[tasks."($name)"]' $"[($name)]" $'["($name)"]']
    )
}

export def reference-location [root: string, file: string, text: string] {
    let path = relative $root $file
    let index = open --raw $file | lines | enumerate | where {|line|
        not ($line.item | str trim | str starts-with '#') and ($line.item | str contains $text)
    } | get -o index.0 | default 0
    $"($path):($index + 1)"
}
