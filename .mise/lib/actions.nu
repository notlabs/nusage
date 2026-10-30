# GitHub Actions, for the tasks CI runs: whether this is one, and its workflow commands. The
# runner reads a command off a line of the log only when it starts the line, so a task that
# prints them runs with `output = "interleave"`, as mise prefixes the lines otherwise. An
# annotation names a file and its lines, and the pull request shows it inline on them and the
# run's summary lists it; a group folds the lines under its title until its end, so the log
# opens on what matters. Outside Actions an annotation prints nothing, a group a plain heading,
# and the task's own output stands.

# Whether the task runs in GitHub Actions.
export def in-actions []: nothing -> bool {
    ($env.GITHUB_ACTIONS? | default "") == "true"
}

# A command's message: its `%` and line breaks encoded, as the runner decodes them.
def encode-message []: string -> string {
    $in
    | str replace --all "%" "%25"
    | str replace --all "\r" "%0D"
    | str replace --all "\n" "%0A"
}

# A command's property: as a message, and the `:` and `,` that would end it.
def encode-property []: string -> string {
    $in | encode-message | str replace --all ":" "%3A" | str replace --all "," "%2C"
}

# A path as the workflow reads it, relative to the repository: an absolute one is made relative
# to the checkout, or to the repository the task runs in, which mise's project root is not
# in a monorepo, where it is the task's config root.
def workflow-path [file: string]: nothing -> string {
    if ($file | path expand) != $file {
        return $file
    }
    let root = $env.GITHUB_WORKSPACE? | default { ^git rev-parse --show-toplevel | str trim }
    try {
        $file | path relative-to $root
    } catch {
        $file
    }
}

# An annotation, `error`, `warning` or `notice`, on a file's lines when they are given.
export def annotate [
    level: string # error, warning or notice
    message: string
    --file: string # the file, relative to the repository, or absolute
    --line: int # its first line
    --end-line: int # its last
    --title: string
] {
    if not (in-actions) {
        return
    }
    let properties = [
        (if $file != null { $"file=(workflow-path $file | encode-property)" })
        (if $line != null { $"line=($line)" })
        (if $end_line != null { $"endLine=($end_line)" })
        (if $title != null { $"title=($title | encode-property)" })
    ] | compact | str join ","
    let command = if ($properties | is-empty) { $"::($level)" } else { $"::($level) ($properties)" }
    print $"($command)::($message | encode-message)"
}

# The hunks of a unified diff: the lines each starts at and covers in the first file, and its
# text.
export def hunks [diff: string]: nothing -> table<line: int, end: int, body: string> {
    mut hunks = []
    for line in ($diff | lines) {
        let header = $line | parse --regex '^@@ -(?<line>\d+)(?:,(?<count>\d+))? '
        if ($header | is-not-empty) {
            let start = $header.0.line | into int
            let count = if ($header.0.count | is-empty) {
                1
            } else {
                $header.0.count | into int
            }
            $hunks = $hunks | append {line: $start, end: ($start + ([$count 1] | math max) - 1), body: ""}
        } else if ($hunks | is-not-empty) {
            $hunks = $hunks | update ($hunks | length | $in - 1) {|hunk| $hunk | update body ($hunk.body + $line + "\n") }
        }
    }
    $hunks
}

# A unified diff from a file to what it should be, as an error on the file's lines per hunk,
# the hunk as the message.
export def annotate-diff [file: string, title: string, diff: string] {
    for hunk in (hunks $diff) {
        annotate error $hunk.body --file $file --line $hunk.line --end-line $hunk.end --title $title
    }
}

# A section of the log under its title, folded in Actions from here to `group-end`; a plain
# heading elsewhere. A pair rather than a closure, so the section can go on changing the
# task's variables.
export def group-start [title: string] {
    if (in-actions) {
        print $"::group::($title | encode-message)"
    } else {
        print $"$ ($title)"
    }
}

# The end of the section `group-start` opened.
export def group-end [] {
    if (in-actions) {
        print "::endgroup::"
    }
}
