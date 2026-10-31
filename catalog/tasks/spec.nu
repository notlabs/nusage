#!/usr/bin/env nus
#USAGE about "Obtain each entry's spec into its package: as its tool prints it, or from the clap command its crate builds, left untouched when unchanged"
#USAGE arg "[tool]" help="One entry; every entry when absent"
#USAGE flag "--force" help="Write a clap entry's spec though it describes the binary's version, after a change to the extractor or to usage"
# What depends on a spec stays fresh across runs when the file is written only on a change.
use catalog.nu *
use support.nu clap

for entry in (entries $usage.args.tool) {
    let files = files $entry.name
    mkdir $files.dir
    match (spec-kind $entry) {
        run => {
            let spec = export-spec $entry
            if not ($files.spec | path exists) or (open --raw $files.spec) != $spec {
                $spec | save --force $files.spec
                print $"($entry.name): ($files.spec | path relative-to (root)) written"
            } else {
                print $"($entry.name): spec is current"
            }
        }
        clap => {
            let dir = (extractor $entry).dir
            let force = if $usage.flags.force { ["--force"] } else { [] }
            ^nus $clap $dir --out $files.spec ...$force
        }
        openapi => {
            # The committed set is made the written set: a file the document no longer gives
            # is removed with the rest refreshed.
            let scratch = mktemp --directory --tmpdir --suffix .nusage-openapi
            export-openapi $entry $scratch
            let written = openapi-files $scratch
            let changed = $written | where {|file|
                let committed = $files.dir | path join $file
                not ($committed | path exists) or (open --raw $committed) != (open --raw ($scratch | path join $file))
            }
            for file in $changed {
                mkdir ($files.dir | path join $file | path dirname)
                cp ($scratch | path join $file) ($files.dir | path join $file)
                print $"($entry.name): (($files.dir | path join $file) | path relative-to (root)) written"
            }
            let stale = openapi-files $files.dir | where {|file| $file not-in $written }
            for file in $stale {
                rm ($files.dir | path join $file)
                print $"($entry.name): (($files.dir | path join $file) | path relative-to (root)) removed; the document no longer gives it"
            }
            rm --recursive $scratch
            if ($changed | is-empty) and ($stale | is-empty) {
                print $"($entry.name): spec is current"
            }
        }
    }
}
