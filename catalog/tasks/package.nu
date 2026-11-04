#!/usr/bin/env nus
#USAGE flag "--out <dir>" default="dist" help="Where the package goes, relative to the catalog"
# The OCI directory holds the tasks under `nusage/`, so that a consumer's
# `task_config.includes` names each `nusage:<task>`; this task and the module they share are
# not tasks there. The modules themselves are released as packages of their own, by `pack`.
use catalog.nu *

const tasks = path self | path dirname

let version = ^mise config get vars.catalog_version | str trim
if $version == "" {
    error make --unspanned {
        msg: "`vars.catalog_version` names the catalog's version in the mise config"
    }
}
let out = root | path join $usage.flags.out
let oci = $out | path join oci
rm --recursive --force $oci
mkdir ($oci | path join nusage)
for file in [catalog.nu spec.nu generate.nu check.nu] {
    cp ($tasks | path join $file) ($oci | path join nusage $file)
}
# Producers export their public tasks; only the producer knows its private file layout.
run-task //catalog/clap:package ($oci | path join nusage clap) | print --no-newline
run-task //catalog/schemas:package ($oci | path join nusage schemas) | print --no-newline
run-task //:report:package ($oci | path join nusage report) | print --no-newline
let display = try {
    $oci | path relative-to (root)
} catch {
    $oci
}
print $"($display)/nusage: push it with `oras push <registry>/nusage-tasks:($version) nusage` from ($display)"
