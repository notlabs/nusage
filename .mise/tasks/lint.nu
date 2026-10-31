#!/usr/bin/env nus
#USAGE about "The workflows by jactionlint, and the handwritten Nushell and the TOML as the formatters want them, with what they would change shown"
#MISE description="The workflows by jactionlint, and the handwritten Nushell and the TOML as the formatters want them, with what they would change shown"
#MISE depends=["//nusage:build"]
#MISE output="interleave"
# Unlabelled lines: GitHub reads an annotation only at the start of a line.
# The formatters' own checks name a file and no more; a lint has to say what is wrong where,
# so each file is formatted again and the difference printed, and in GitHub Actions each
# hunk is an annotation on its lines, which the pull request shows inline, through the
# module every task shares.
use ../lib/actions.nu *

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
    annotate-diff $file $"($formatter): not formatted, `jj fix` writes it" $diff.stdout
    false
}

mut failed = []

group-start jactionlint
let workflows = if (in-actions) {
    ^jactionlint --format github | complete
} else {
    ^jactionlint | complete
}
print --no-newline $workflows.stdout
if $workflows.exit_code != 0 {
    $failed = $failed | append "jactionlint"
}
group-end

group-start nufmt
for file in (
    ^git ls-files "*.nu"
    | lines
    | where $it !~ "/expected/" and $it !~ '^catalog/lib/[^/]+/mod\.nu$'
) {
    if not (formatted $file nufmt { ^nufmt --stdin }) {
        $failed = $failed | append $"nufmt: ($file)"
    }
}
group-end

group-start taplo
for file in (^git ls-files "*.toml" | lines) {
    if not (formatted $file taplo { ^taplo fmt - }) {
        $failed = $failed | append $"taplo: ($file)"
    }
}
group-end

if ($failed | is-not-empty) {
    error make --unspanned {msg: $"lint failed: ($failed | str join ', ')"}
}
