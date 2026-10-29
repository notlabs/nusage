#!/usr/bin/env nusage
#USAGE about "Generate each entry's module from its spec and overlays, with the nusage on PATH"
#USAGE arg "[tool]" help="One entry; every entry when absent"
use catalog.nu *

for entry in (entries $usage.args.tool) {
    let made = generate $entry
    print $"($entry.name): ($made.module | path relative-to (root))"
}
