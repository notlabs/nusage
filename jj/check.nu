#!/usr/bin/env nusage
#USAGE about "Holds the module to jj's spec and the spec to the jj on PATH, then drives jj through the module"
use std/assert
use generated/jj.nu *

^nusage check jj.usage.kdl generated/jj.nu

# The spec is written once per version, and a jj of another version has another interface.
let spec = open --raw jj.usage.kdl | parse --regex '(?m)^version "(?<version>[^"]+)"' | get 0.version
let path = jj version | parse --regex '(?<version>\d+\.\d+\.\d+)' | get 0.version
if $spec != $path {
    error make {
        msg: $"jj.usage.kdl describes jj ($spec), and PATH has jj ($path): `mise run //jj:spec` writes it for ($path)"
    }
}

# A repository of its own, configured by global flags alone: a path that does not exist is
# passed over, so no configuration of the user's is read.
let dir = mktemp --directory
let repo = $dir | path join repo
with-env {JJ_CONFIG: ($dir | path join none.toml)} {
    let config = ['user.name="nusage"' 'user.email="nusage@example.com"']
    jj git init $repo
    jj describe --repository $repo --config $config --message ["through the module"]
    let description = jj log --repository $repo --no-graph --revision ["@"] --template description
    assert equal ($description | str trim) "through the module"
}
rm --recursive $dir

print $"jj: ($path) through the module"
