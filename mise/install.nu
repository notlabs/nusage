#!/usr/bin/env nusage
#USAGE about "Writes the one line that loads the module into Nushell's user autoload directory"
# Nushell sources every file of its user autoload directory when an interactive session
# starts; where that is depends on the platform and on how Nushell is configured, so the
# Nushell on PATH is asked.
const here = path self | path dirname

let module = $here | path join generated mise.nu
let dir = ^nu -n -c '$nu.user-autoload-dirs | first' | str trim
mkdir $dir
let file = $dir | path join mise.nu
let line = $"use ($module | to nuon) *\n"
if not ($file | path exists) or (open --raw $file) != $line {
    $line | save --force $file
    print $"mise: ($file) loads the module"
} else {
    print $"mise: ($file) is current"
}
let x = [1,2,  3]
