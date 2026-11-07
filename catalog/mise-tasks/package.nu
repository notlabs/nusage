#!/usr/bin/env nus
#MISE description="Package the catalog's tasks for a release: the directory the OCI task catalog is pushed from"
#MISE depends=[":check"]
#USAGE flag "--out <dir>" default="dist" help="Where the package goes, relative to the catalog"
# The OCI directory holds the tasks under `catalog/`, so that a consumer's
# `task_config.includes` names each `catalog:<task>`; this task and the module they share are
# not tasks there. The modules themselves are released as packages of their own, by `pack`.
use mise *
use ../lib/catalog.nu *
use ../lib/support.nu *

const tasks = path self | path dirname

let version = mise config get vars.catalog_version | str trim
if $version == "" {
    error make --unspanned {
        msg: "`vars.catalog_version` names the catalog's version in the mise config"
    }
}
let out = root | path join $usage.flags.out
let oci = $out | path join oci
rm --recursive --force $oci
mkdir ($oci | path join catalog)
cp ($tasks | path join ../lib/catalog.nu) ($oci | path join catalog catalog.nu)
for file in [spec.nu generate.nu check.nu] {
    open --raw ($tasks | path join $file)
    | str replace --all '../lib/catalog.nu' 'catalog.nu'
    | str replace --all '../lib/support.nu' 'support.nu'
    | lines | where {|line| not ($line | str starts-with '#MISE')} | str join (char nl)
    | save --force ($oci | path join catalog $file)
    ^chmod +x ($oci | path join catalog $file)
}
# Bundle the public bootstrap module; the task catalog also works outside this checkout.
let bootstrap = mise where http:catalog-bootstrap --cd ($tasks | path dirname) | str trim
mkdir ($oci | path join catalog mise)
cp ($bootstrap | path join lib mise mod.nu) ($oci | path join catalog mise mod.nu)
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
cp --recursive ($schema_overlay | path dirname | path join lib) ($oci | path join catalog .support schemas lib)
$helpers | each {|helper|
    $'export const ($helper.name) = path self | path dirname | path join ($helper.relative)'
} | str join "\n" | save --force ($oci | path join catalog support.nu)
print $"($oci | path join catalog): push it with `oras push <registry>/nusage-tasks:($version) catalog` from ($oci)"
