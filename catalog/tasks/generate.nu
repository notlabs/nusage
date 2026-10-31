#!/usr/bin/env nus
#USAGE about "Generate each entry's module from its spec, schema suite and overlays, with the nus on PATH"
#USAGE arg "[tool]" help="One entry; every entry when absent"
use catalog.nu *

for entry in (entries $usage.args.tool) {
    let made = generate $entry
    print $"($entry.name): ($made.module | path relative-to (root))"
}
