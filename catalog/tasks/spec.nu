#!/usr/bin/env nusage
#USAGE about "Export each entry's spec from the tool on PATH into its package, left untouched when unchanged"
#USAGE arg "[tool]" help="One entry; every entry when absent"
# What depends on a spec stays fresh across runs when the file is written only on a change.
use catalog.nu *

for entry in (entries $usage.args.tool) {
    let files = files $entry.name
    let spec = export-spec $entry
    mkdir $files.dir
    if not ($files.spec | path exists) or (open --raw $files.spec) != $spec {
        $spec | save --force $files.spec
        print $"($entry.name): ($files.spec | path relative-to (root)) written"
    } else {
        print $"($entry.name): spec is current"
    }
}
