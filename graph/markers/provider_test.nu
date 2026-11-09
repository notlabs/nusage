use std/assert
use std/testing *
use ../common.nu load-discovery
use provider.nu records
const here = path self | path dirname
const root = path self | path dirname | path join fixtures
def fixture [] {
    load-discovery ($here | path join fixtures data.json) | to json | str replace --all /workspace $root | from json
}
@test
def "Markers project declared task-call and task-dir edges" [] {
    let data = fixture
    let got = records $data $root
    assert equal ($got | where kind == project | length) 2
    assert equal ($got | where kind == edge | get type | sort) [declared task-call task-dir]
    assert ($got | where kind == edge | all {|edge| $edge.from == 'nu:app' and $edge.to == 'nu:lib' })
}
@test
def "An unknown declared project is an error" [] {
    let data = fixture | update configs.0.data._.nusage.project.depends_add ['nu:missing']
    assert error { records $data $root }
}
