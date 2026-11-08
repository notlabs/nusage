use std/assert
use std/testing *
use assemble.nu [write-graph project-config run-providers]
const here = path self | path dirname
@test
def "Assembler refuses only a changed projection and writes task fragments" [] {
    let scratch = mktemp -d
    let result = try {
        {task_config: {cache: {enabled: true}}} | to toml | save ($scratch | path join mise.toml)
        let records = [
            {kind: project, id: 'nu:a', root: a}
            {kind: edge, from: 'nu:a', to: 'cargo:b', type: declared, source: 'a/mise.toml:3'}
            {kind: task, root: crates/b, name: test, task: {run: 'cargo test --locked', sources: ['**/*'], outputs: []}}
            {kind: input, path: Cargo.toml}
        ]
        assert (write-graph $scratch $records).changed
        let graph_file = $scratch | path join .mise conf.d _projects.toml
        let task_file = $scratch | path join crates b .mise conf.d _cargo.toml
        let before = [$graph_file $task_file] | each { ls $in | get modified.0 }
        assert not (write-graph $scratch ($records | reverse)).changed
        assert equal ([$graph_file $task_file] | each { ls $in | get modified.0 }) $before
        let text = open --raw ($scratch | path join .mise conf.d _projects.toml)
        assert ($text | str contains '# declared: cargo:b at a/mise.toml:3')
        assert not ($text | str contains metadata)
        assert equal (open ($scratch | path join crates b .mise conf.d _cargo.toml) | get tasks.test.run) 'cargo test --locked'
        assert (write-graph $scratch ($records | where kind != edge)).changed
        null
    } catch {|err| $err }
    rm -rf $scratch
    if $result != null { error make $result }
}

@test
def "An absent project file refuses even an empty projection" [] {
    let scratch = mktemp -d
    let result = try {
        {task_config: {cache: {enabled: true}}} | to toml | save ($scratch | path join mise.toml)
        assert (write-graph $scratch []).changed
        assert not (write-graph $scratch []).changed
        null
    } catch {|err| $err }
    rm -rf $scratch
    if $result != null { error make $result }
}

@test
def "Parallel provider records merge by provider name then record" [] {
    let scratch = mktemp -d
    let result = try {
        let command = $scratch | path join mise
        cp ($here | path join fixtures provider-mise.sh) $command
        ^chmod +x $command
        with-env {PATH: ([$scratch] ++ $env.PATH)} {
            let providers = [{name: '//graph/z:provider'} {name: '//graph/a:provider'}]
            assert equal (run-providers $providers $scratch ignored.json | get path) ["//graph/a:provider/a" "//graph/a:provider/z" "//graph/z:provider/a" "//graph/z:provider/z"]
        }
        null
    } catch {|err| $err }
    rm -rf $scratch
    if $result != null { error make $result }
}
