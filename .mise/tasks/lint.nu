#!/usr/bin/env nus
#MISE description="Hold the tree to what `jj fix` writes for it and to what its linters accept"
#MISE output="interleave"
use ../lib/actions.nu *

# A Git diff as each file's path and its own part of the diff.
def files-of []: string -> table<path: string, diff: string> {
    $in
    | split row --regex '(?m)^diff --git '
    | where $it != ""
    | each {|part|
        {
            path: ($part | parse --regex '(?m)^\+\+\+ b/(?<path>.+)$' | get path.0)
            diff: ($"diff --git ($part)" | str trim --right --char (char nl))
        }
    }
}

mut failed = []

# `jj fix` formats every file of the working copy with the formatters `jj.toml` gives it, and
# the working copy keeps what it writes: what that changes was not formatted, and a formatter
# that fails names the file it could not read.
group-start formatting
let before = ^jj log --no-pager --no-graph --revisions @ --template commit_id
let fixed = ^jj fix --no-pager --quiet --include-unchanged-files --source @ | complete
print --no-newline $fixed.stderr
let refused = $fixed.stderr
| parse --regex 'Fix tool `(?<tool>[^`]+)` exited with non-zero exit code for `(?<file>[^`]+)`'
for file in $refused {
    annotate error $"($file.tool) could not format it" --file $file.file
    $failed = $failed | append $"($file.tool): ($file.file)"
}
if $fixed.exit_code != 0 {
    $failed = $failed | append "jj fix"
}
for file in (^jj diff --no-pager --git --from $before --to @ | files-of) {
    print $file.diff
    annotate-diff $file.path "not formatted: `jj fix` writes this" $file.diff
    $failed = $failed | append $"formatting: ($file.path)"
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

# What formatting cannot settle in the YAML.
group-start ryl
let yaml = if (in-actions) {
    ^ryl check --output-format github . | complete
} else {
    ^ryl check . | complete
}
print --no-newline $yaml.stdout $yaml.stderr
if $yaml.exit_code != 0 {
    $failed = $failed | append "ryl"
}
group-end

# Each TOML file against the schema `.taplo.toml` gives it.
group-start taplo
let toml = with-env {RUST_LOG: warn} { ^taplo check | complete }
print --no-newline $toml.stderr
for file in (
    $toml.stderr
    | parse --regex 'invalid file error=(?<why>.+?) path="(?<path>[^"]+)"'
) {
    annotate error $"taplo: ($file.why)" --file ($file.path | path relative-to (pwd))
}
if $toml.exit_code != 0 {
    $failed = $failed | append "taplo"
}
group-end

if ($failed | is-not-empty) {
    error make --unspanned {msg: $"lint failed: ($failed | str join ', ')"}
}
