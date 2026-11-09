use std/assert
use std/testing *
use ../common.nu load-discovery
use provider.nu [tasks-from tool-edges]
const here = path self | path dirname
@test
def "Cargo tasks project transitive resolve edges and constant inputs" [] {
    let records = tasks-from (open ($here | path join fixtures metadata.json)) (open ($here | path join tasks.toml))
    let test = $records | where root == crates/a and name == test | get task.0
    assert equal $test.sources ["**/*" "../b/**/*" "../c/**/*" "../../Cargo.toml" "../../Cargo.lock" "../../.cargo/**" "../../rust-toolchain.toml"]
    assert equal ($records | where name == build) []
    assert equal ($records | where name == check | get task.depends.0) [":test" ":clippy" ":doc"]
}

@test
def "A nus shebang declares tool use without an explicit tools table" [] {
    let root = $here | path join fixtures
    let data = load-discovery ($here | path join fixtures discovery.json) | update tasks.0.source ($root | path join consumer mise.toml)
    assert equal (tool-edges $data (open ($root | path join metadata.json)) $root) [{kind: edge, from: 'nu:consumer', to: 'cargo:a', type: tool, source: 'consumer/run.nu:1'}]
}

@test
def "A workspace without a nus binary emits no workspace tool edges" [] {
    let metadata = open ($here | path join fixtures metadata.json) | update packages.0.targets.0.name unrelated
    assert equal (tool-edges {tasks: [], projects: []} $metadata ($here | path join fixtures)) []
}
