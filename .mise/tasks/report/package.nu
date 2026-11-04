#!/usr/bin/env nu
#MISE description="Export the reporting task with its private implementation"
#MISE hide=true
const here = path self | path dirname

def main [out: path] {
    mkdir ($out | path join lib)
    cp ($here | path join emit.nu) ($out | path join emit.nu)
    cp ($here | path join lib actions.nu) ($out | path join lib actions.nu)
}
