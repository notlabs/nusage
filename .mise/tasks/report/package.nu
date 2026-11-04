#!/usr/bin/env nu
#MISE description="Export the reporting task with its private implementation"
#MISE alias="report:package"
#MISE hide=true
const here = path self | path dirname

def main [out: path] {
    mkdir ($out | path join .support)
    cp ($here | path join emit.nu) ($out | path join emit.nu)
    cp ($here | path join .support actions.nu) ($out | path join .support actions.nu)
}
