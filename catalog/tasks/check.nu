#!/usr/bin/env nusage
#USAGE about "Hold each entry's generated files to its spec and overlays, its spec to the tool on PATH, its module to usage's reading of the spec, then drive the tool through the module"
#USAGE arg "[tool]" help="One entry; every entry when absent"
# The generated files are committed: the module a package ships is reviewed as a diff when the
# spec or an overlay changes. So `check` generates again and compares byte for byte, and asks
# the tool for its spec again: a stale spec fails in CI, where the tool's version is pinned,
# and is a warning elsewhere, where any version may be on PATH.
use catalog.nu *

def in-ci []: nothing -> bool {
    ($env.CI? | default "") == "true"
}

# The unified difference between a committed file and what was generated for it, when any.
def differs [committed: path, made: path]: nothing -> bool {
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
    true
}

mut failed = []
for entry in (entries $usage.args.tool) {
    let files = files $entry.name
    let name = $entry.name

    let tmp = mktemp --directory --tmpdir --suffix .nusage-catalog
    let made = generate $entry --into $tmp
    let stale = ($made.select | each {|select| differs $files.select $select }) ++ [
        (differs $files.module $made.module)
    ]
    rm --recursive $tmp
    if ($stale | any {|it| $it }) {
        print $"($name): the generated files are not what the spec and overlays give; `mise run generate ($name)` rewrites them"
        $failed = $failed | append $"($name): generated files"
    }

    let fresh = try { export-spec $entry } catch {|err|
        print $"($name): the tool did not print its spec, so the committed one stands: ($err.msg)"
        null
    }
    if $fresh != null and $fresh != (open --raw $files.spec) {
        let note = $"($name): ($files.spec | path relative-to (root)) is not what the tool on PATH prints; `mise run spec ($name)` then `mise run generate ($name)` refresh it"
        if (in-ci) {
            print $note
            $failed = $failed | append $"($name): spec"
        } else {
            print $"($note) \(a warning here, where the tool's version is not pinned\)"
        }
    }

    let overlays = ($made.select | each {|it| $files.select }) ++ $files.overlays
    let held = ^nusage check $files.spec $files.module ...($overlays | each {|overlay| ["--overlay" $overlay] } | flatten) | complete
    if $held.exit_code != 0 {
        print --no-newline $held.stderr
        $failed = $failed | append $"($name): nusage check"
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
