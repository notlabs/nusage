#!/usr/bin/env nu
#MISE description="Export the schema tasks with their private implementation"
#MISE hide=true
const here = path self | path dirname

def main [out: path] {
    mkdir ($out | path join .support)
    for name in [overlay.nu examples.nu validate.nu] {
        cp ($here | path join $name) ($out | path join $name)
    }
    cp ($here | path join .support lib.nu) ($out | path join .support lib.nu)
}
