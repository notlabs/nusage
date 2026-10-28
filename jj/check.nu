#!/usr/bin/env nusage
#USAGE about "Holds the module to jj's spec and the spec to the jj on PATH, then drives jj through the module"
use std/assert
use generated/jj.nu *

^nusage check jj.usage.kdl generated/jj.nu --overlay generated/jj.schemas.kdl

# The spec is written once per version, and a jj of another version has another interface.
let spec = open --raw jj.usage.kdl | parse --regex '(?m)^version "(?<version>[^"]+)"' | get 0.version
let path = jj version | parse --regex '(?<version>\d+\.\d+\.\d+)' | get 0.version
if $spec != $path {
    error make {
        msg: $"jj.usage.kdl describes jj ($spec), and PATH has jj ($path): `mise run //jj:spec` writes it for ($path)"
    }
}

# A repository of its own, in a home of its own and configured by global flags alone: jj keeps
# each repository's configuration under the user's configuration directory, reads the user's
# files, and a path that does not exist is passed over.
let dir = mktemp --directory
let repo = $dir | path join repo
let inherited = $env | columns | where {|name| $name | str starts-with "JJ_" }
hide-env --ignore-errors ...$inherited
with-env {HOME: $dir, XDG_CONFIG_HOME: ($dir | path join .config), JJ_CONFIG: ($dir | path join none.toml)} {
    let config = ['user.name="nusage"' 'user.email="nusage@example.com"']
    jj git init $repo
    jj describe --repository $repo --config $config --message ["through the module"]
    jj bookmark create --repository $repo --config $config --revision @ topic

    # Each output is data: commits with their authors' times, bookmarks with their targets,
    # operations back to the root one, which no workspace ran.
    let commits = jj log --repository $repo --revision ["@"]
    assert equal ($commits | length) 1
    assert equal ($commits.0.description | str trim) "through the module"
    assert equal $commits.0.author.name nusage
    assert equal ($commits.0.author.timestamp | describe) datetime
    let bookmarks = jj bookmark list --repository $repo
    assert equal ($bookmarks | select name target) [{name: topic, target: [$commits.0.commit_id]}]
    let operations = jj operation log --repository $repo
    assert equal ($operations | last | get workspace_name) null
    assert equal ($operations.0.time.start | describe) datetime
}
rm --recursive $dir

print $"jj: ($path) through the module"
