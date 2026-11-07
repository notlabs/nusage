# What the graph providers share: checked commands, workspace paths and atomic writes.

# The command's output; its exit code and output are the error when it fails.
export def --wrapped checked [...args: string]: any -> string {
    let input = $in
    let result = $input | run-external ...$args | complete
    if $result.exit_code != 0 {
        error make --unspanned {
            msg: ($result.stderr + $result.stdout)
        }
    }
    $result.stdout
}

# Whether a workspace-relative path is the directory or inside it; `.` holds every path.
export def within [path: string, directory: string]: nothing -> bool {
    $directory == "." or $path == $directory or ($path | str starts-with ($directory + "/"))
}

# A path relative to the workspace root, with `/` separators and `.` for the root itself; a
# path outside the root starts with `..`.
export def workspace-path [root: string]: string -> string {
    let path = $in | path expand --no-symlink
    let relative = try { $path | path relative-to ($root | path expand --no-symlink) } catch { $"../($path)" }
    let relative = $relative | str replace --all '\' '/'
    if $relative == "" { "." } else { $relative }
}

# The 1-based line of a byte offset in the text.
export def line-at [offset: int]: string -> int {
    let before = $in | encode utf8 | bytes at 0..<$offset
    ($before | bytes index-of --all 0x[0a] | length) + 1
}

# The workspace's files matching the git pathspecs, as workspace-relative paths: the tracked
# and untracked files git does not ignore, or, outside a work tree, a walk that keeps the
# hidden `.mise` directories and skips other hidden directories and `target`.
export def workspace-files [root: string, ...patterns: string]: nothing -> list<string> {
    let listed = do { cd $root; ^git ls-files --cached --others --exclude-standard -z -- ...$patterns } | complete
    if $listed.exit_code == 0 {
        return (
            $listed.stdout
            | split row (char nul)
            | where $it != "" and ($root | path join $it | path exists)
            | uniq
            | sort
        )
    }
    let skipped = ["**/target/**" "**/.*/**"]
    $patterns
    | each {|pattern|
        let pattern = $pattern | str replace --regex '^:\(glob\)' ''
        let pattern = if ($pattern | str contains "/") { $pattern } else { $"**/($pattern)" }
        glob ($root | path join $pattern) --no-dir --exclude $skipped
        | append (glob ($root | path join .mise $pattern) --no-dir --exclude ["**/target/**"])
        | append (glob ($root | path join "**/.mise" $pattern) --no-dir --exclude ["**/target/**"])
    }
    | flatten
    | each { workspace-path $root }
    | uniq
    | sort
}

# Write the text unless the file already holds it, through a temporary file beside it.
export def write-if-changed [file: string, content: string]: nothing -> bool {
    if ($file | path exists) and (open --raw $file) == $content {
        return false
    }
    mkdir ($file | path dirname)
    let temporary = $"($file).tmp"
    $content | save --force $temporary
    mv --force $temporary $file
    true
}

# The messages of the errors an error wraps, innermost first: a failure inside a closure
# comes wrapped in one about the closure's input.
def causes [error: record]: nothing -> list<string> {
    let inner = $error.inner? | default []
    if ($inner | is-empty) { [$error.msg] } else { $inner | each {|e| causes $e } | flatten }
}

# Providers report only their final stderr line; the failure goes on that line, after the
# provider's name.
export def report-failure [name: string]: record -> nothing {
    let error = $in
    let messages = if ($error.details? | default null) != null { causes $error.details } else { [$error.msg] }
    let detail = $messages | each { lines } | flatten | where $it != "" | str join " | "
    print --stderr $"($name): ($detail)"
    exit 1
}
