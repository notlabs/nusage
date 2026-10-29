#!/usr/bin/env nu
# Drives jj through the module: each call decodes to the data it declares. The catalog's
# `check` runs this with `lib` included, as a user's `use jj *` finds the module, and holds
# the spec to the jj on PATH itself.
use std/assert
use jj *

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

print $"jj: (^jj --version | str trim) through the module"
