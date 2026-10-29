#!/usr/bin/env nusage
#USAGE about "The workflows by jactionlint, and the handwritten Nushell and the TOML as the formatters want them, with what they would change shown"
# The formatters' own checks name a file and no more; a lint has to say what is wrong where,
# so each file is formatted again and the difference printed, and in GitHub Actions each
# hunk is an annotation on its lines, which the pull request shows inline.
def in-actions [] {
    ($env.GITHUB_ACTIONS? | default "") == "true"
}

# An annotation, as the workflow command spells it, with the message's line breaks encoded.
def annotate [
    file: string
    line: int
    end: int
    title: string
    message: string
] {
    let encoded = $message
    | str replace --all "%" "%25"
    | str replace --all "\r" "%0D"
    | str replace --all "\n" "%0A"
    print $"::error file=($file),line=($line),endLine=($end),title=($title)::($encoded)"
}

# The hunks of a unified diff: the lines each starts at and covers in the first file, and its
# text.
def hunks [diff: string] {
    mut hunks = []
    for line in ($diff | lines) {
        let header = $line | parse --regex '^@@ -(?<line>\d+)(?:,(?<count>\d+))? '
        if ($header | is-not-empty) {
            let start = $header.0.line | into int
            let count = if $header.0.count == "" {
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

# Whether a file is what its formatter writes for it; the difference printed when not.
def formatted [file: string, formatter: string, format: closure] {
    # A formatter reading standard input ends without the newline it writes to a file.
    let content = open --raw $file | str trim --right --char (char nl)
    let wanted = $content | do $format | str trim --right --char (char nl)
    if $wanted == $content {
        return true
    }
    let diff = $wanted + (char nl)
    | ^diff --unified --label $file --label $"($file) as ($formatter) wants" $file -
    | complete
    print --no-newline $diff.stdout
    if (in-actions) {
        for hunk in (hunks $diff.stdout) {
            (annotate
                $file
                $hunk.line
                $hunk.end
                $"($formatter): not formatted"
                $"`jj fix` writes it:\n($hunk.body)"
            )
        }
    }
    false
}

mut failed = []

print "$ jactionlint"
let workflows = if (in-actions) {
    ^jactionlint --format github | complete
} else {
    ^jactionlint | complete
}
print --no-newline $workflows.stdout
if $workflows.exit_code != 0 {
    $failed = $failed | append "jactionlint"
}

print "$ nufmt"
for file in (^git ls-files "*.nu" | lines | where $it !~ "/expected/") {
    if not (formatted $file nufmt { ^nufmt --stdin }) {
        $failed = $failed | append $"nufmt: ($file)"
    }
}

print "$ taplo"
for file in (^git ls-files "*.toml" | lines) {
    if not (formatted $file taplo { ^taplo fmt - }) {
        $failed = $failed | append $"taplo: ($file)"
    }
}

if ($failed | is-not-empty) {
    error make --unspanned {msg: $"lint failed: ($failed | str join ', ')"}
}
