#!/usr/bin/env nus
use common.nu *
use discovery.nu discover
const here = path self | path dirname

# The contract's schema is the JSON literal embedded in its KDL output declaration.
let schema = open --raw ($here | path join provider.schemas.kdl) | lines | each { str trim } | where {|line| $line | str starts-with 'schema ' } | first | str substring 7.. | from json --strict
let temporary = mktemp -d

let result = try {
    $schema | save ($temporary | path join schema.json)
    let root = $here | path dirname
    let data = with-env {NUSAGE_GRAPH_ACTIVE: '1'} { discover $root (checked mise tasks ls --all --hidden --json | from json --strict) }
    let snapshot = $temporary | path join discovery.json
    $data | to json | save $snapshot
    let providers = $data.tasks | where {|task| ($task.name | str starts-with '//graph/') and ($task.name | str ends-with ':provider') }
    for provider in $providers {
        let output = with-env {NUSAGE_GRAPH_ACTIVE: '1', NUSAGE_GRAPH_NU: $nu.current-exe} { checked mise run --force --no-deps --raw $provider.name $root --discovery $snapshot }
        let validated = $output | ^nus validate ($temporary | path join schema.json) --lines - | complete
        if $validated.exit_code != 0 { error make {msg: $"($provider.name): ($validated.stderr)"} }
        print $"($provider.name): contract passed"
    }
    null
} catch {|err| $err }
rm -rf $temporary
if $result != null { error make $result }
