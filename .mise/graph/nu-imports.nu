# The workspace's Nushell references, as typed records in `.cache/graph/nu.json` for the
# project graph: the modules and scripts each file loads or names by a path beside itself,
# and the tasks it runs. Only literal targets resolve; a computed one is recorded as dynamic
# for the project graph to reject or accept.
use common.nu *

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
def scan [
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

# The directories the root's `monorepo.config_roots` policy names, and the root itself.
def config-roots [root: string]: nothing -> list<string> {
    let policy = open ($root | path join mise.toml) | get -o monorepo.config_roots | default []
    cd $root
    ["."] ++ (
        $policy
        | each {|pattern| glob $pattern --no-file --exclude ["**/.*/**"] }
        | flatten
        | each { workspace-path $root }
    )
    | uniq
}

# The index of a task's table header among a file's enumerated lines, or 0.
def header-index [name: string]: list<any> -> int {
    let quoted = $name | str replace --all '"' '\"'
    let headers = [
        $"[tasks.($name)]"
        $"[tasks.\"($quoted)\"]"
        $"[($name)]"
        $"[\"($quoted)\"]"
    ]
    $in | where {|l| ($l.item | str trim) in $headers } | get -o 0.index | default 0
}

# Each task definition in a config file or task include: its name and table.
def task-tables [file: string]: nothing -> list<any> {
    let data = open --raw $file | from toml
    let tasks = if ($file | str ends-with .tasks.toml) {
        $data
    } else {
        $data | get -o tasks | default {}
    }
    let shell = $data | get -o task_config.shell
    $tasks | items {|name, task| {name: $name, task: $task} } | where {|t| ($t.task | describe) =~ '^record' } | each {|t|
        {name: $t.name, task: $t.task, shell: ($t.task | get -o shell | default $shell)}
    }
}

def analyze [root: string] {
    let workspace = {|p|
        $p | workspace-path $root
    }
    let nu_files = workspace-files $root '*.nu'
    let sources = $nu_files | par-each {|file|
        let source = open --raw ($root | path join $file)
        {file: $file, source: $source, tokens: (ast --flatten $source)}
    }
    let consts = $sources | each {|s|
        {file: $s.file, consts: (path-consts $s.source $s.tokens ($root | path join $s.file | path dirname))}
    }
    let refs = $sources | each {|s|
        let file = $root | path join $s.file
        let dir = $file | path dirname
        # A load brings the loaded file's path constants into scope.
        let defined = $consts | where file == $s.file | get 0.consts
        let own = $defined | by-name
        let loaded = scan $s.source $s.tokens $dir $own --loads | get -o target | compact | each {|t| do $workspace $t }
        let scope = $consts | where file in $loaded | get consts | flatten | by-name | merge $own
        let paths = $defined | where {|c| ($c.path | path type) == file } | each {|c| {kind: nu-path, line: $c.line, target: $c.path} }
        # Test suites drive the scratch workspaces they build; their `mise run` names those.
        let runs = not ($s.file | str ends-with _test.nu)
        (scan $s.source $s.tokens $dir $scope --loads --runs=$runs) ++ $paths | each {|r| {file: $s.file} | merge $r }
    } | flatten

    # Task definitions: run entries that name tasks, and inline scripts.
    let roots = config-roots $root
    let configs = workspace-files $root ':(glob)**/mise.toml' ':(glob)**/mise.*.toml' ':(glob)**/.mise/conf.d/*.toml'
    | where {|f|
        let parts = $f | path split
        let owner = if ($parts | length) >= 3 and ($parts | last 3 | first 2) == [.mise conf.d] {
            $parts | drop 3 | path join
        } else { $f | path dirname }
        let owner = if $owner == "" { "." } else { $owner }
        $owner in $roots and not ($f | path basename | str starts-with _)
    }
    let includes = workspace-files $root '*.tasks.toml'
    let definitions = $configs ++ $includes | each {|file|
        let path = $root | path join $file
        let raw = open --raw $path
        let config_root = if ($file | str ends-with .tasks.toml) {
            null
        } else if ($file | path split | last 3 | first 2) == [.mise conf.d] {
            $path | path dirname | path dirname | path dirname
        } else { $path | path dirname }
        let raw_lines = $raw | lines | enumerate
        task-tables $path | each {|t|
            # The line a reference's text first appears on, from the task's own header.
            let header = $raw_lines | header-index $t.name
            let line_of = {|text|
                let found = if $text == "" { null } else {
                    $raw_lines | skip $header | where {|l| $l.item | str contains $text } | get -o 0.index
                }
                if $found == null { null } else { $found + 1 }
            }
            let entries = $t.task | get -o run | default [] | if ($in | describe) == string { [$in] } else { $in }
            $entries | each {|entry|
                if ($entry | describe) =~ '^record' {
                    [($entry | get -o task)] ++ ($entry | get -o tasks | default []) | compact | each {|target|
                        {file: $file, line: (do $line_of $target), kind: task-call, task: $target, include: ($config_root == null)}
                    }
                } else {
                    let script = if $config_root != null {
                        $entry | str replace --all --regex '\{\{\s*config_root\s*\}\}' $config_root
                    } else { $entry }
                    let dir = $config_root | default ($path | path dirname)
                    let nushell = $t.shell != null and ($t.shell | str starts-with nu)
                    scan $script (ast --flatten $script) $dir {} --loads=$nushell --runs | each {|r|
                        # Substitution keeps the script's lines; the file holds the original.
                        let text = $entry | lines | get -o (($r.line | default 1) - 1) | default "" | str trim
                        {file: $file, include: ($config_root == null)} | merge $r | merge {line: (do $line_of $text)}
                    }
                }
            } | flatten
        } | flatten
    } | flatten

    # `^task` dependencies as written: mise drops them where a task's root is no project, so
    # its resolved tasks no longer show them.
    let carets = $configs ++ $includes | each {|file|
        let path = $root | path join $file
        let raw_lines = open --raw $path | lines | enumerate
        task-tables $path | each {|t|
            $t.task | get -o depends | default [] | if ($in | describe) == string { [$in] } else { $in }
            # A dependency is a name, a `{task = }` table, or a name followed by its arguments.
            | each {|d|
                match ($d | describe) {
                    string => $d
                    $type if ($type | str starts-with record) => ($d | get -o task)
                    _ => ($d | get -o 0)
                }
            }
            | compact
            | where ($it | str starts-with '^')
            | each {|caret|
                let header = $raw_lines | header-index $t.name
                let line = $raw_lines | skip $header | where {|l| $l.item | str contains $'"($caret)"' } | get -o 0.index
                {file: $file, line: (if $line == null { null } else { $line + 1 }), task: $t.name, depends: $caret}
            }
        } | flatten
    } | flatten
    let headers = $sources | each {|s|
        $s.source | lines | enumerate | where {|l| $l.item =~ '^#\s*(\[MISE\]|MISE)\s+depends\s*=' } | each {|l|
            $l.item | parse --regex '"(?<depends>\^[^"]+)"' | each {|c|
                {file: $s.file, line: ($l.index + 1), task: null, depends: $c.depends}
            }
        } | flatten
    } | flatten

    let refs = $refs ++ $definitions | each {|r|
        if ($r.target? | default null) != null { $r | update target (do $workspace $r.target) } else { $r }
    } | where {|r| ($r.target? | default null) == null or not ($r.target | str starts-with ..) }
    let output = $root | path join .cache graph nu.json
    let content = {
        files: $nu_files
        refs: ($refs | sort-by file line kind)
        carets: ($carets ++ $headers | sort-by file line)
    } | to json --indent 2
    write-if-changed $output $content | ignore
}

def main [root: path = "."] {
    try {
        analyze ($root | path expand)
    } catch {|err|
        $err | report-failure nu-imports
    }
}
