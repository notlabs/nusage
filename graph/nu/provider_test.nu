use std/assert
use std/testing *
use ../common.nu load-discovery
use provider.nu analyze
const root = path self | path dirname | path join fixtures

def data [file: string] {
    load-discovery ($root | path join discovery.json) | update tasks.0.source ($root | path join app mise.toml) | update tasks.0.file $file
}
@test
def "Nu traverses task loads and emits typed cross-root references" [] {
    let got = analyze (data main.nu) $root
    assert equal ($got | where kind == edge | get type | sort) [nu-path nu-source nu-use]
    assert equal ($got | where kind == input | length) 3
}
@test
def "Computed loads require the declaring root dynamic marker" [] {
    assert error { analyze (data dynamic.nu) $root }
    let allowed = data dynamic.nu | update configs [{root: app, data: {_: {nusage: {project: {dynamic: [dynamic.nu]}}}}}]
    assert equal (analyze $allowed $root | where kind == edge | length) 0
}

@test
def "Imported path constants resolve transitive loads" [] {
    let got = analyze (data indirect.nu) $root
    assert equal ($got | where kind == input | length) 4
    assert equal ($got | where kind == edge | get type) [nu-use nu-use]
}
