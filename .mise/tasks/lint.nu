#!/usr/bin/env nus
#MISE description="Check repository formatting and lint diagnostics"
#MISE output="interleave"
use ../../actions/mod.nu *

mut failed = []

# Formatting checks do not mutate the working copy or its history.
group-start formatting
let formatted = ^cargo fmt --all -- --check | complete
print --no-newline $formatted.stdout $formatted.stderr
if $formatted.exit_code != 0 { $failed = $failed | append "cargo fmt" }
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
