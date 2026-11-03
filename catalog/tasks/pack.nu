#!/usr/bin/env nus
#USAGE arg "[tool]" help="One entry; every entry with a version when absent"
#USAGE flag "--out <dir>" default="dist/packages" help="Where the archives go, relative to the catalog"
# An entry's archive, `nusage-<tool>-<version>.tar.gz`, and `packages.json` beside the
# archives for the release job. The name gives no platform, so packslip records the archive as
# running anywhere.
use catalog.nu *

let out = root | path join $usage.flags.out
mkdir $out
let entries = entries $usage.args.tool | where {|entry| ($entry.version? | default "") != "" }
if ($entries | is-empty) {
    error make --unspanned {msg: "no entry has a `version`, which releases it as a package of its own"}
}
let packed = $entries | each {|entry|
    let files = files $entry.name
    if not ($files.module | path exists) {
        error make --unspanned {
            msg: $"entry `($entry.name)`: no module at ($files.module | path relative-to (root)); `mise run generate ($entry.name)` writes it"
        }
    }
    let spec = open --raw $files.spec | lines
    let bin = $spec | parse --regex '^bin\s+"?(?<bin>[^"\s]+)"?\s*$' | get bin.0? | default $entry.name
    # The mise tool and version of the binary the spec was read from, which nus holds the
    # project's own version of that tool to.
    let tool = if ($entry.tool? | default "") == "" {
        null
    } else {
        let version = $spec | parse --regex '^version\s+"(?<version>[^"]+)"' | get version.0?
        if $version == null {
            error make --unspanned {
                msg: $"entry `($entry.name)`: its spec names no `version`, which the package pins `($entry.tool)` to"
            }
        }
        {name: $entry.tool, bin: $bin, version: $version}
    }
    let staged = $out | path join $".($entry.name)"
    rm --recursive --force $staged
    # Empty, so that mise puts nothing of the package on PATH.
    mkdir ($staged | path join bin)
    cp --recursive $files.dir ($staged | path join $entry.name)
    # What a package keeps for its maintenance stays here, as the catalog tarball leaves it.
    for kept in [spec schema-fixtures] {
        rm --recursive --force ($staged | path join $entry.name $kept)
    }
    {name: $entry.name, version: $entry.version, module: $entry.name}
    | merge (if $tool == null { {} } else { {tool: $tool} })
    | to nuon --indent 4
    | save --force ($staged | path join package.nuon)
    let archive = $out | path join $"nusage-($entry.name)-($entry.version).tar.gz"
    ^tar --create --gzip --file $archive --directory $staged package.nuon bin $entry.name
    rm --recursive --force $staged
    {
        name: $entry.name
        version: $entry.version
        tag: $"catalog/($entry.name)/v($entry.version)"
        archive: $archive
    }
}

let packed = $packed | update archive {|row| $row.archive | path relative-to (root) }
$packed | to json --raw | save --force ($out | path join packages.json)
$packed | each {|row| $"($row.tag): ($row.archive)" } | str join "\n"
