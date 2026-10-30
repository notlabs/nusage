#!/usr/bin/env nusage
#USAGE about "Hold each entry's generated files to their inputs and its spec to the tool on PATH, hold the tool's output to its schemas and the module to usage's reading of the spec, then drive the tool through the module"
#USAGE arg "[tool]" help="One entry; every entry when absent"
# The generated files are committed: the module a package ships is reviewed as a diff when the
# spec, the suite or an overlay changes. So `check` generates again and compares byte for byte,
# and asks after the tool's version: a stale spec fails in CI, where the tool's version is
# pinned, and is a warning elsewhere, where any version may be on PATH.
use catalog.nu *
use ../../.mise/lib/actions.nu *

def in-ci []: nothing -> bool {
    ($env.CI? | default "") == "true"
}

# The unified difference between a committed file and what was generated for it, when any.
def differs [committed: string, made: string]: nothing -> bool {
    if not ($committed | path exists) {
        print $"  ($committed | path relative-to (root)) is not committed"
        return true
    }
    if (open --raw $committed) == (open --raw $made) {
        return false
    }
    let diff = ^diff --unified --label $"($committed | path relative-to (root)) committed" --label "generated now" $committed $made
    | complete
    print --no-newline $diff.stdout
    annotate-diff $committed "not what the spec, suite and overlays give; `mise run generate` rewrites it" $diff.stdout
    true
}

# Whether the committed spec is the tool's on PATH, by the entry's probe: `current`, `stale`
# with what to run, or `unknown` with why, when the tool is not there to ask.
def spec-state [entry: record, files: record]: nothing -> record {
    let name = $entry.name
    let refresh = $"`mise run spec ($name)` then `mise run generate ($name)` refresh it"
    match (spec-probe $entry) {
        export if (spec-kind $entry) == openapi => {
            # The document is the source: every file written from it is held to the package.
            let scratch = mktemp --directory --tmpdir --suffix .nusage-openapi
            try { export-openapi $entry $scratch } catch {|err|
                rm --recursive $scratch
                return {state: unknown, note: $err.msg}
            }
            let written = openapi-files $scratch
            let stale = ($written | where {|file|
                let committed = $files.dir | path join $file
                not ($committed | path exists) or (open --raw $committed) != (open --raw ($scratch | path join $file))
            }) ++ (openapi-files $files.dir | where {|file| $file not-in $written })
            rm --recursive $scratch
            if ($stale | is-empty) {
                {state: current}
            } else {
                {
                    state: stale
                    note: $"($stale | str join ', ') under ($files.dir | path relative-to (root)) are not what the document gives; ($refresh)"
                }
            }
        }
        export => {
            let fresh = try { export-spec $entry } catch {|err| return {state: unknown, note: $err.msg} }
            if $fresh == (open --raw $files.spec) {
                {state: current}
            } else {
                {
                    state: stale
                    note: $"($files.spec | path relative-to (root)) is not what the tool prints; ($refresh)"
                }
            }
        }
        version => {
            let identity = spec-identity $files
            if $identity.version == null {
                error make --unspanned {
                    msg: $"entry `($name)`: the spec declares no `version` to probe by; `probe = \"export\"` compares the whole spec"
                }
            }
            let bin = $identity.bin | default $name
            let found = ^$bin --version | complete
            if $found.exit_code != 0 {
                return {
                    state: unknown
                    note: $"($bin) is not on PATH to ask"
                }
            }
            let version = $found.stdout | parse --regex '(?<version>\d+\.\d+\.\d+)' | get 0?.version? | default ""
            if $identity.version == $version {
                {state: current}
            } else {
                {
                    state: stale
                    note: $"($files.spec | path relative-to (root)) describes ($bin) ($identity.version), and PATH has ($version); ($refresh)"
                }
            }
        }
    }
}

mut failed = []
for entry in (entries $usage.args.tool) {
    let files = files $entry.name
    let name = $entry.name

    let tmp = mktemp --directory --tmpdir --suffix .nusage-catalog
    let made = generate $entry --into $tmp
    let stale = (
        $made.generated
        | each {|file| differs ($files.dir | path join ($file | path basename)) $file }
    ) ++ [
        (differs $files.module $made.module)
    ]
    rm --recursive $tmp
    if ($stale | any {|it| $it }) {
        print $"($name): the generated files are not what the spec, suite and overlays give; `mise run generate ($name)` rewrites them"
        $failed = $failed | append $"($name): generated files"
    }

    let spec = spec-state $entry $files
    match $spec.state {
        unknown => { print $"($name): the spec's currency is unknown, so the committed one stands: ($spec.note)" }
        stale => {
            if (in-ci) {
                print $"($name): ($spec.note)"
                $failed = $failed | append $"($name): spec"
            } else {
                print $"($name): ($spec.note) \(a warning here, where the tool's version is not pinned\)"
            }
        }
        _ => { }
    }

    let committed = $made.generated | each {|file| $files.dir | path join ($file | path basename) }
    let overlays = $committed ++ $files.overlays
    let http = if ($files.http | path exists) { ["--http" $files.http] } else { [] }
    let held = ^nusage check $files.spec $files.module ...($overlays | each {|overlay| ["--overlay" $overlay] } | flatten) ...$http | complete
    if $held.exit_code != 0 {
        print --no-newline $held.stderr
        $failed = $failed | append $"($name): nusage check"
    }

    if (spec-kind $entry) == clap {
        let main = (extractor $entry).dir | path join src main.rs
        let formatted = ^rustfmt --check --edition 2024 $main | complete
        if $formatted.exit_code != 0 {
            print --no-newline $formatted.stdout
            $failed = $failed | append $"($name): the extractor as rustfmt wants it"
        }
    }

    if ($files.check_schemas | path exists) {
        let suite = ^$files.check_schemas | complete
        print --no-newline $suite.stdout
        if $suite.exit_code != 0 {
            print --no-newline $suite.stderr
            $failed = $failed | append $"($name): check-schemas.nu"
        }
    }

    if ($files.check | path exists) {
        let drove = ^nu --include-path (root | path join lib) $files.check | complete
        print --no-newline $drove.stdout
        if $drove.exit_code != 0 {
            print --no-newline $drove.stderr
            $failed = $failed | append $"($name): check.nu"
        }
    }
}

if ($failed | is-not-empty) {
    error make --unspanned {msg: $"catalog check failed: ($failed | str join ', ')"}
}
