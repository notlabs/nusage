use std/assert
use std/testing *
use mise *

const project = path self | path dirname | path dirname | path dirname
const tasks = path self | path dirname | path join ../tasks/cargo.tasks.toml

def --wrapped checked [...args: string] {
    let result = run-external ...$args | complete
    assert equal $result.exit_code 0 ($result.stderr + $result.stdout)
    $result.stdout | str trim
}

@test
def "shared Cargo tasks follow native edges and scope cached inputs to their consumers" [] {
    let rust = open ($project | path join nusage mise.toml) | get task_config
    let cli = open ($project | path join nusage crates nusage mise.toml)
    let scratch = mktemp -d | path expand
    let result = try {
        mkdir ($scratch | path join .bin) ($scratch | path join tooling tasks)
        cp $tasks ($scratch | path join tooling tasks cargo.tasks.toml)
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
                # The shared tasks hold their graph to the one on disk through the root's guard.
                tasks: {graph-current: {run: "true"}}
            } | to toml | save mise.toml
            {workspace: {members: ["nusage/crates/*"], resolver: "2"}} | to toml | save Cargo.toml
            mkdir nusage
            {task_config: $rust} | to toml | save nusage/mise.toml
            "version = 4\n" | save Cargo.lock
            mkdir nusage/fixtures nusage/schemas
            "# fixture\n" | save nusage/fixtures/example.nu
            "{}\n" | save nusage/schemas/inspection.schema.json
            for name in [a b c] {
                let dir = $scratch | path join nusage crates $name
                mkdir ($dir | path join src)
                {package: {name: $name, version: "0.1.0"}} | to toml | save ($dir | path join Cargo.toml)
                "" | save ($dir | path join src lib.rs)
                mut config = {task_config: {includes: ["../../../tooling/tasks/cargo.tasks.toml"]}}
                if $name == a {
                    $config = $config | merge {tasks: {
                        test: {sources: $cli.tasks.test.sources, outputs: $cli.tasks.test.outputs}
                        clippy: {sources: $cli.tasks.clippy.sources, outputs: $cli.tasks.clippy.outputs}
                    }}
                }
                $config | to toml | save ($dir | path join mise.toml)
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
            rm events

            # A warm run reuses all three checks.
            checked mise run //nusage/crates/a:check | ignore
            assert not ("events" | path exists)

            # Fixture changes rerun only the CLI's tests.
            "# changed fixture\n" | save --append nusage/fixtures/example.nu
            checked mise run //nusage/crates/a:check | ignore
            assert equal (open --raw events | lines) [a:test]
            rm events

            # The schema is compiled into the CLI's tests, also checked by Clippy.
            " \n" | save --append nusage/schemas/inspection.schema.json
            checked mise run //nusage/crates/a:check | ignore
            assert equal (open --raw events | lines | sort) [a:clippy a:test]
            rm events

            # Native upstream edges carry invalidation into the consumer's cache key.
            "// changed upstream\n" | save --append nusage/crates/b/src/lib.rs
            checked mise run //nusage/crates/a:check | ignore
            assert equal (open --raw events | lines | sort) [a:clippy a:doc a:test b:clippy b:doc b:test]
            rm events

            # Workspace lockfiles and Cargo configuration are shared Rust inputs.
            "# changed resolution\n" | save --append Cargo.lock
            checked mise run //nusage/crates/a:check | ignore
            assert equal (open --raw events | lines | sort) [a:clippy a:doc a:test b:clippy b:doc b:test]
            rm events
            mkdir .cargo
            "[build]\njobs = 1\n" | save .cargo/config.toml
            checked mise run //nusage/crates/a:check | ignore
            assert equal (open --raw events | lines | sort) [a:clippy a:doc a:test b:clippy b:doc b:test]
            rm events

            # Unrelated workflows do not invalidate cached checks.
            mkdir .github/workflows
            "name: release\n" | save .github/workflows/release.yml
            checked mise run //nusage/crates/a:check | ignore
            assert not ("events" | path exists)

            # Included task definitions are tracked automatically.
            "# changed definition\n" | save --append tooling/tasks/cargo.tasks.toml
            checked mise run //nusage/crates/a:check | ignore
            assert equal (open --raw events | lines | sort) [a:clippy a:doc a:test b:clippy b:doc b:test]
        }
        null
    } catch {|err| $err}
    rm -rf $scratch
    if $result != null { error make $result }
}
