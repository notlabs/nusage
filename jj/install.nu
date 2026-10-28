#!/usr/bin/env nusage
#USAGE about "Writes the one line that loads the module into Nushell's user autoload directory"
# Nushell sources every file of its user autoload directory when an interactive session
# starts; where that is depends on the platform and on how Nushell is configured, so the
# Nushell on PATH is asked.
const here = path self | path dirname

let module = $here | path join generated jj.nu
let dir = ^nu -n -c '$nu.user-autoload-dirs | first' | str trim
mkdir $dir
let file = $dir | path join jj.nu
let line = $"use ($module | to nuon) *\n"
if not ($file | path exists) or (open --raw $file) != $line {
    $line | save --force $file
    print $"jj: ($file) loads the module"
} else {
    print $"jj: ($file) is current"
}
