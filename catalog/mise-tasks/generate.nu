#!/usr/bin/env nus
#MISE description="Generate each entry's module"
#USAGE arg "[tool]" help="One entry; every entry when absent"
use ../lib/catalog.nu *

for entry in (entries $usage.args.tool) {
    let made = generate $entry
    print $"($entry.name): ($made.module | path relative-to (root))"
}
