#!/usr/bin/env nu
#MISE description="Export the Clap extraction task"
#MISE hide=true
const here = path self | path dirname

def main [out: path] {
    mkdir $out
    cp ($here | path join spec.nu) ($out | path join spec.nu)
}
