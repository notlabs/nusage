#!/usr/bin/env nu
use ../common.nu *
const here = path self | path dirname
export def line-at [offset: int]: string -> int {
    (
        $in
        | encode utf8
        | bytes at 0..<$offset
        | bytes index-of --all 0x[0a]
        | length
    ) + 1
}
const load_kinds = {
    "use": nu-use
    "export use": nu-use
    "overlay use": nu-use
    "source": nu-source
    "source-env": nu-source
}

const literal_shapes = [
    shape_string
    shape_filepath
    shape_globpattern
    shape_externalarg
    shape_directory
]

def unquote []: string -> string {
    let text = $in
    if ($text | str length) >= 2 and ($text | str substring 0..0) in ['"' "'" '`'] and ($text | str substring 0..0) == ($text | str substring (-1)..) {
        $text | str substring 1..<(($text | str length) - 1)
    } else {
        $text | str replace --regex `^r#*'(.*)'#*$` '$1'
    }
}

def is-literal []: record -> bool {
    $in.shape in $literal_shapes and not ($in.content | str starts-with '$') and not ($in.content | str contains '{{')
}

# The file a load names from the directory that holds it: a file, `<name>.nu`, or a
# directory's `mod.nu`; null for a module NU_LIB_DIRS or the standard library provides.
def resolve-load [dir: string, target: string]: nothing -> any {
    if ($target | str contains '{{') { return null }
    let candidate = $dir | path join $target | path expand --no-symlink
    match ($candidate | path type) {
        file => $candidate
        dir if ($candidate | path join mod.nu | path exists) => ($candidate | path join mod.nu)
        _ => (if ($"($candidate).nu" | path type) == file { $"($candidate).nu" })
    }
}

# The constants a file builds from its own location (`path self`, optionally joined to a
# literal): each one's name, path and line.
def path-consts [source: string, tokens: list<any>, dir: string]: nothing -> list<any> {
    $tokens | enumerate | where {|t| $t.item.shape == shape_internalcall and $t.item.content in [const "export const"] } | each {|t|
        let rest = $tokens | skip ($t.index + 1) | first 7
        let name = $rest | get -o 0
        if $name == null or $name.shape != shape_vardecl { return null }
        let steps = $rest | skip 1 | get content
        let target = if ($steps | first 1) == ["path self"] and ($rest | get -o 2 | default {shape: none} | is-literal) {
            $dir | path join ($rest | get 2.content | unquote)
        } else if ($steps | first 5) == ["path self" "|" "path dirname" "|" "path join"] and ($rest | get -o 6 | default {shape: none} | is-literal) {
            $dir | path join ($rest | get 6.content | unquote)
        }
        if $target != null {
            {name: $name.content, path: ($target | path expand --no-symlink), line: ($source | line-at $t.item.span.start)}
        }
    } | compact
}

def by-name []: list<any> -> record {
    reduce --fold {} {|c, acc| $acc | upsert $c.name $c.path }
}

# The references in a piece of Nushell: loads, `path self` constants that name a file, and
# `mise run` targets. `consts` are the path constants in scope, by name.
export def scan [
    source: string
    tokens: list<any>
    dir: string
    consts: record
    --loads
    --runs
]: nothing -> list<any> {
    let bytes = $source | encode utf8
    let line = {|token|
        $source | line-at $token.span.start
    }
    let heads = ($load_kinds | columns) ++ [mise ^mise "mise run"]
    # Only these tokens can start a reference; the rest are skipped without a closure each.
    let starts = $tokens | enumerate | where ($it.item.content in $heads) or ($it.item.shape == shape_garbage)
    mut refs = []
    for t in $starts {
        let token = $t.item
        let next = $tokens | get -o ($t.index + 1)
        if $loads and $token.shape == shape_internalcall and $token.content in $load_kinds and $next != null {
            let kind = $load_kinds | get $token.content
            let target = if ($next | is-literal) {
                $next.content | unquote
            } else if $next.shape == shape_variable and ($next.content | str substring 1..) in $consts {
                $consts | get ($next.content | str substring 1..)
            }
            $refs = $refs | append (
                if $target != null {
                    let file = resolve-load $dir $target
                    if $file != null { {kind: $kind, line: (do $line $token), target: $file} }
                } else {
                    {kind: $kind, line: (do $line $token), dynamic: $"($token.content) ($next.content)"}
                }
            )
        } else if $loads and $token.shape == shape_garbage {
            # A load whose target the parser could not evaluate stays one garbage token.
            let parsed = $token.content | parse --regex '^(?<keyword>export use|overlay use|use|source-env|source)\s+(?<target>\S+)' | get -o 0
            if $parsed != null {
                let kind = $load_kinds | get $parsed.keyword
                let name = $parsed.target | str replace --regex '^\$' ''
                $refs = $refs | append (
                    if ($parsed.target | str starts-with '$') and $name in $consts {
                        let file = resolve-load $dir ($consts | get $name)
                        if $file != null { {kind: $kind, line: (do $line $token), target: $file} }
                    } else if ($parsed.target | str starts-with '$') or ($parsed.target | str starts-with '(') {
                        {kind: $kind, line: (do $line $token), dynamic: $token.content}
                    } else {
                        let file = resolve-load $dir ($parsed.target | unquote)
                        if $file != null { {kind: $kind, line: (do $line $token), target: $file} }
                    }
                )
            }
        } else if $runs and $token.shape != shape_garbage {
            let start = if $token.content in [mise ^mise] and $next != null and $next.content == run {
                $t.index + 2
            } else if $token.shape != shape_string and $token.content == "mise run" {
                $t.index + 1
            }
            if $start != null {
                # The call's arguments end with its line.
                let rest = $bytes | bytes at $token.span.end.. | bytes index-of 0x[0a]
                let end = if $rest < 0 {
                    $bytes | bytes length
                } else {
                    $token.span.end + $rest
                }
                let argument = $tokens | skip $start | take while {|a| $a.span.start < $end and $a.shape not-in [shape_pipe shape_semicolon] } | where {|a| not ($a.content | str starts-with '-') } | get -o 0
                if $argument != null {
                    let call = do $line $token
                    $refs = $refs | append (
                        if ($argument | is-literal) {
                            let task = $argument.content | unquote
                            if ($task | str starts-with '//') { {kind: task-call, line: $call, task: $task} }
                        } else {
                            let text = $bytes | bytes at $argument.span.start..<$end | decode utf8 | str trim
                            {kind: task-call, line: $call, dynamic: $"mise run ($text)"}
                        }
                    )
                }
            }
        }
    }
    $refs | compact
}

export def analyze [data: record, root: string] {

    # Literal declared Nu inputs also cover scripts invoked by a task's shell launcher.
    # Globs remain task-cache inputs; this traversal never expands them.
    mut queue = $data.tasks | each {|task|
        let files = [$task.file?] ++ ($task.sources? | default [] | where {|path| $path | str ends-with '.nu' })
        $files | compact | each {|file| $root | path join (task-root $task.name) $file | path expand --no-symlink }
    } | flatten | uniq
    let inline = $data.tasks | each {|t|
        $t.run | where {|run| ($run | describe) == string and $run != "" } | each {|run|
            {file: ($t.source | path expand --no-symlink), dir: ($root | path join (task-root $t.name)), source: ($run | str replace --all --regex '\{\{\s*config_root\s*\}\}' ($root | path join (task-root $t.name)))}
        }
    } | flatten
    mut pending = $inline
    mut seen = []
    mut parsed = []
    mut refs = []
    loop {
        let files = $queue | where {|file| $file not-in $seen and ($file | path type) == file }
        $seen = $seen ++ $files
        let sources = $pending ++ (
            $files
            | each {|file| {file: $file, dir: ($file | path dirname), source: (open --raw $file)} }
        )
        $pending = []
        $parsed = $parsed ++ ($sources | par-each --threads 4 {|source|
            let tokens = ast --flatten $source.source
            $source | insert tokens $tokens | insert defined (path-consts $source.source $tokens $source.dir)
        } | sort-by file source)
        # The source graph holds parser results for this run. Imports resolve against
        # those records; no importer reparses the module it loads.
        let documents = $parsed
        let definitions = $documents | group-by file | items {|file, docs| {file: $file, defined: ($docs | get defined | flatten)} } | reduce --fold {} {|doc, index| $index | insert $doc.file $doc.defined }
        $refs = $documents | par-each --threads 4 {|source|
            let own = $source.defined | by-name
            mut scope = $own
            loop {
                let loads = scan $source.source $source.tokens $source.dir $scope --loads
                let targets = $loads | get -o target | default [] | compact
                let loaded = $targets | each {|target| $definitions | get -o $target | default [] } | flatten | by-name
                let resolved = $loaded | merge $own
                if $resolved == $scope { break }
                $scope = $resolved
            }
            let paths = $source.defined | where {|c| $c.path != $source.dir and ($c.path | path exists) } | each {|c| {kind: nu-path, line: $c.line, target: $c.path} }
            (scan $source.source $source.tokens $source.dir $scope --loads --runs) ++ $paths | each {|ref| $ref | insert file $source.file }
        } | flatten
        $queue = $refs | where {|ref| $ref.kind in [nu-use nu-source] } | get -o target | default [] | compact | uniq | where {|file| $file not-in $seen }
        if ($queue | is-empty) { break }
    }
    let dynamic = $data.configs | each {|c|
        $c.data._?.nusage?.project?.dynamic? | default [] | each {|file| $root | path join $c.root $file | path expand --no-symlink }
    } | flatten
    let edges = $refs | each {|ref|
        let file = relative $root $ref.file
        let from = owner $data.projects $file
        let source = $"($file):($ref.line)"
        if $ref.dynamic? != null {
            if $ref.file not-in $dynamic { error make --unspanned {msg: $"($source): computed target ($ref.dynamic); list ($file) in its root's marker dynamic"} }
        } else if $ref.target? != null and (within $ref.target $root) {
            let to = owner $data.projects (relative $root $ref.target)
            if $from.id != $to.id { {kind: edge, from: $from.id, to: $to.id, type: $ref.kind, source: $source} }
        } else if $ref.task? != null {
            task-targets $data.tasks $ref.task (task-root ($data.tasks | where source == $ref.file | get -o name.0 | default '//:check')) | each {|base|
                let to = owner $data.projects $base
                if $from.id != $to.id { {kind: edge, from: $from.id, to: $to.id, type: task-call, source: $source} }
            }
        }
    } | flatten | compact | uniq
    $edges ++ ($seen | each { input $in })
}
def main [root: path = ".", --discovery: path] {
    let root = $root | path expand --no-symlink
    let data = load-discovery $discovery
    (analyze $data $root) ++ (discovery-inputs $data) ++ [
        (input ($here | path join provider.nu))
        (input ($here | path join ../common.nu | path expand --no-symlink))
    ]
    | emit
    | print
}
