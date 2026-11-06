use std/assert
use std/testing *
use mise *

const tasks = path self | path dirname | path join cargo.tasks.toml

def --wrapped checked [...args: string] {
    let result = run-external ...$args | complete
    assert equal $result.exit_code 0 ($result.stderr + $result.stdout)
    $result.stdout | str trim
}

@test
def "shared Cargo tasks follow native crate edges without checking peers" [] {
    let scratch = mktemp -d | path expand
    let result = try {
        mkdir ($scratch | path join .bin) ($scratch | path join .mise lib)
        cp $tasks ($scratch | path join .mise lib cargo.tasks.toml)
        let command = '#!/bin/sh
printf "%s:%s\\n" "${PWD##*/}" "$1" >> "$GRAPH_LOG"
'
        $command | save ($scratch | path join .bin cargo)
        checked chmod +x ($scratch | path join .bin cargo) | ignore
        with-env {
            MISE_CONFIG_DIR: ($scratch | path join .config)
            MISE_DATA_DIR: ($scratch | path join .data)
            MISE_CACHE_DIR: ($scratch | path join .cache)
            MISE_TRUSTED_CONFIG_PATHS: $scratch
            MISE_IGNORED_CONFIG_PATHS: ""
        } {
            cd $scratch
            {
                monorepo_root: true
                monorepo: {config_roots: ["[!.]*" "[!.]*/[!.]*" "[!.]*/[!.]*/[!.]*"]}
                settings: {experimental: true}
                env: {
                    NU_LIB_DIRS: ($env.NU_LIB_DIRS | str join (char esep))
                    _: {path: ($env.PATH | prepend ($scratch | path join .bin))}
                    GRAPH_LOG: ($scratch | path join events)
                }
            } | to toml | save mise.toml
            {workspace: {members: ["nusage/crates/*"], resolver: "2"}} | to toml | save Cargo.toml
            for name in [a b c] {
                let dir = $scratch | path join nusage crates $name
                mkdir ($dir | path join src)
                {package: {name: $name, version: "0.1.0"}} | to toml | save ($dir | path join Cargo.toml)
                "" | save ($dir | path join src lib.rs)
                {task_config: {includes: ["../../../.mise/lib/cargo.tasks.toml"]}} | to toml | save ($dir | path join mise.toml)
            }
            '\n[dependencies]\nb = {path = "../b"}\n' | str replace --all '\n' (char nl) | save --append nusage/crates/a/Cargo.toml
            checked mise run --force //nusage/crates/a:check | ignore
            let events = open --raw events | lines
            assert equal ($events | sort) [a:clippy a:doc a:test b:clippy b:doc b:test]
            for action in [test clippy doc] {
                assert (($events | enumerate | where item == $"b:($action)" | get index.0) < ($events | enumerate | where item == $"a:($action)" | get index.0))
            }
            rm events
            checked mise run --force //nusage/crates/a:check:platform | ignore
            assert equal (open --raw events | lines | sort) [a:clippy a:test b:clippy b:test]
            assert equal (mise tasks graph | get projects | where id == cargo:a | get dependencies.0) [cargo:b]
        }
        null
    } catch {|err| $err}
    rm -rf $scratch
    if $result != null { error make $result }
}
