#!/usr/bin/env nusage
#USAGE about "Write the line that loads each entry's module into Nushell's user autoload directory"
#USAGE arg "[tool]" help="One entry; every entry when absent"
# Nushell sources every file of its user autoload directory when an interactive session
# starts; where that is depends on the platform and on how Nushell is configured, so the
# Nushell on PATH is asked. A script loads a module itself, with `lib` on `$NU_LIB_DIRS`.
use catalog.nu *

let dir = ^nu -n -c '$nu.user-autoload-dirs | first' | str trim
mkdir $dir
for entry in (entries $usage.args.tool) {
    let files = files $entry.name
    if not ($files.module | path exists) {
        error make --unspanned {
            msg: $"entry `($entry.name)`: no module at ($files.module | path relative-to (root)); `mise run generate ($entry.name)` writes it"
        }
    }
    let file = $dir | path join $"nusage-($entry.name).nu"
    let line = $"use ($files.dir | path expand | to nuon) *\n"
    if not ($file | path exists) or (open --raw $file) != $line {
        $line | save --force $file
        print $"($entry.name): ($file) loads the module"
    } else {
        print $"($entry.name): ($file) is current"
    }
}
