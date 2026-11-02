#!/usr/bin/env nus
#USAGE about "Package the catalog's tasks for a release: the directory an OCI task catalog is pushed from"
#USAGE flag "--out <dir>" default="dist" help="Where the package goes, relative to the catalog"
# The OCI directory holds the tasks under `catalog/`, so that a consumer's
# `task_config.includes` names them `catalog:spec`, `catalog:generate` and `catalog:check`;
# this task and the module they share are not tasks there. The modules themselves are
# released as packages of their own, by `pack`.
use catalog.nu *
use support.nu *

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
mkdir ($oci | path join catalog)
for file in [catalog.nu spec.nu generate.nu check.nu] {
    cp ($tasks | path join $file) ($oci | path join catalog $file)
}
# Hidden from mise's task discovery, but shipped with the scripts that import them.
let helpers = [
    {name: actions, source: $actions, relative: .support/actions.nu}
    {name: clap, source: $clap, relative: .support/clap/spec.nu}
    {
        name: schema_overlay
        source: $schema_overlay
        relative: .support/schemas/overlay.nu
    }
]
for helper in $helpers {
    let target = $oci | path join catalog $helper.relative
    mkdir ($target | path dirname)
    cp $helper.source $target
}
cp ($schema_overlay | path dirname | path join lib.nu) ($oci | path join catalog .support schemas lib.nu)
$helpers | each {|helper|
    $'export const ($helper.name) = path self | path dirname | path join ($helper.relative)'
} | str join "\n" | save --force ($oci | path join catalog support.nu)
print $"($oci | path relative-to (root))/catalog: push it with `oras push <registry>/nusage-tasks:($version) catalog` from ($oci | path relative-to (root))"
