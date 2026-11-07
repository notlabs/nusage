#!/usr/bin/env nus
#USAGE arg "<project>" help="A project whose mise config names notlabs/nusage tools"
#MISE description="Install this checkout's builds into mise as the nusage versions a project names"
#MISE depends=["//catalog:pack"]
# For each tool of this repository the project's config names, `mise link` installs this
# checkout's build under the version the project asks for: `github:notlabs/nusage` is the
# built `nus`, and `packslip:github.com/notlabs/nusage/catalog/<tool>` the package
# `//catalog:pack` wrote. The project's files stay as they will be once the releases exist;
# only this machine's mise holds the links, and `mise install` treats them as installed. A
# link goes when its version is uninstalled (`mise uninstall <tool>@<version>`); the release
# then installs in its place. The builds the links point at are under target/nusage-link,
# where nus is a link to the checkout's own, so a rebuild reaches the project without
# linking again.

use mise *

let root = $env.MISE_PROJECT_ROOT? | default $env.PWD
let project = $usage.args.project | path expand
let links = $root | path join target nusage-link

const PREFIX = "packslip:github.com/notlabs/nusage/catalog/"

let wanted = do {
    cd $project
    mise ls --current
} | transpose tool installs | each {|row|
    {tool: $row.tool, version: ($row.installs | get requested_version | compact | first)}
} | where {|row| $row.tool == "github:notlabs/nusage" or ($row.tool | str starts-with $PREFIX) }
if ($wanted | is-empty) {
    error make --unspanned {msg: $"($project) names no notlabs/nusage tool in its mise config"}
}

let packed = open ($root | path join catalog dist packages packages.json)

let linked = $wanted | each {|row|
    let dir = $links | path join ($row.tool | str replace --all --regex '[^A-Za-z0-9.-]+' '-') $row.version
    rm --recursive --force $dir
    mkdir $dir
    if $row.tool == "github:notlabs/nusage" {
        mkdir ($dir | path join bin)
        for bin in [nus nu_plugin_nus] {
            ^ln -s ($root | path join .bin $bin) ($dir | path join bin $bin)
        }
    } else {
        let name = $row.tool | str replace $PREFIX ""
        let package = $packed | where name == $name
        if ($package | is-empty) {
            error make --unspanned {
                msg: $"($row.tool): no catalog entry `($name)` with a version to pack"
            }
        }
        ^tar --extract --gzip --file ($root | path join catalog $package.0.archive) --directory $dir
    }
    mise link --force $"($row.tool)@($row.version)" $dir
    $"($row.tool)@($row.version)"
}
cd $project
mise install
$linked | str join "\n"
