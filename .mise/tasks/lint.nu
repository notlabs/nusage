#!/usr/bin/env nus
#MISE description="Hold the tree to what `jj fix` writes for it and to what its linters accept"
#MISE depends=["//nusage:build"]
#MISE output="interleave"
# A formatter's own check names a file and no more; a lint has to say what is wrong where. So
# each formatter `jj.toml` gives `jj fix` formats again the files its patterns name, as jj
# reads them, and holds each file to the difference.
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

group-start formatting
for tool in (open jj.toml | get fix.tools | transpose name fix) {
    for file in (^jj file list --no-pager ...$tool.fix.patterns | lines) {
        let command = $tool.fix.command | each { str replace --all '$path' $file }
        let format = {|| run-external $command.0 ...($command | skip 1) }
        if not (formatted $file $tool.name $format) {
            $failed = $failed | append $"($tool.name): ($file)"
        }
    }
}
group-end

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

# What formatting cannot fix in the Markdown, named where it is.
group-start rumdl
let markdown = ^rumdl check . --output-format json | complete

let findings = try {
    $markdown.stdout | from json
} catch {
    null
}
if $findings == null {
    print --no-newline $markdown.stderr
    $failed = $failed | append "rumdl"
} else {
    for finding in ($findings | where {|it| not ($it.fixable? | default false) }) {
        print $"($finding.file):($finding.line):($finding.column): ($finding.rule) ($finding.message)"
        annotate error $"rumdl ($finding.rule): ($finding.message)" --file $finding.file --line $finding.line
        $failed = $failed | append $"rumdl: ($finding.file):($finding.line)"
    }
}
group-end

if ($failed | is-not-empty) {
    error make --unspanned {msg: $"lint failed: ($failed | str join ', ')"}
}
