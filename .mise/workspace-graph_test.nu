use std/assert
use mise *
use std/testing *

const generator = path self | path dirname | path join workspace-graph.nu

def --wrapped checked [...args: string] {
    let result = run-external ...$args | complete
    assert equal $result.exit_code 0 ($result.stderr + $result.stdout)
    $result.stdout | str trim
}

def graph [] {
    mise tasks graph | get projects
}

def before [events: list<string>, first: string, second: string] {
    let positions = $events | enumerate
    assert equal ($positions | where item == $first | length) 1
    assert equal ($positions | where item == $second | length) 1
    assert (($positions | where item == $first | get index.0) < ($positions | where item == $second | get index.0))
}

@test
def "discovered project edges drive caret tasks and affected selection" [] {
    let provider = open ($generator | path dirname | path dirname | path join mise.toml) | get deps.workspace-graph
    let scratch = mktemp -d | path expand
    let result = try {
        with-env {
            NU_LIB_DIRS: ($env.NU_LIB_DIRS | str join (char esep))
            MISE_CONFIG_DIR: ($scratch | path join config)
            MISE_DATA_DIR: ($scratch | path join data)
            MISE_CACHE_DIR: ($scratch | path join cache)
            MISE_TRUSTED_CONFIG_PATHS: $scratch
            MISE_IGNORED_CONFIG_PATHS: ""
            GOWORK: ""
            GOPROXY: "off"
            GIT_CONFIG_GLOBAL: ($scratch | path join gitconfig)
            GIT_CONFIG_NOSYSTEM: "1"
        } {
            cd $scratch
            mkdir bin crates/a/src crates/b/src services/a services/b consumer bridge
            for command in [nus cargo] {
                '#!/bin/sh
echo unexpected > "$GRAPH_LOG.unexpected"
exit 99
' | save ($scratch | path join bin $command)
                checked chmod +x ($scratch | path join bin $command) | ignore
            }
            {
                monorepo_root: true
                monorepo: {config_roots: ["[!.]*" "[!.]*/[!.]*" "[!.]*/[!.]*/[!.]*"]}
                settings: {experimental: true}
                task_config: {cache: {enabled: false}}
                env: {NU_LIB_DIRS: ($env.NU_LIB_DIRS | str join (char esep)), _: {path: ($env.PATH | prepend ($scratch | path join bin))}, GRAPH_LOG: ($scratch | path join events)}
                _: {nusage: {project: {depends_add: ["custom:bridge"]}}}
                deps: {workspace-graph: ($provider | update run $'nu "($generator)" && echo prepared >> provider-runs')}
                tasks: {
                    root-check: {depends: ["^build" "^check"], run: 'echo root-check >> "$GRAPH_LOG"'}
                    root-platform: {depends: ["^build" "^check:platform"], run: 'echo root-platform >> "$GRAPH_LOG"'}
                }
            } | to toml | save mise.toml
            '[workspace]
members = ["crates/*"]
resolver = "2"
' | save Cargo.toml
            for crate in [a b] {
                $'[package]
name = "($crate)"
version = "0.1.0"
' | save ($scratch | path join crates $crate Cargo.toml)
                "" | save ($scratch | path join crates $crate src lib.rs)
            }
            '\n[dependencies]\nb = {path = "../b"}\n' | str replace --all '\n' (char nl) | save --append crates/a/Cargo.toml
            for module in [a b] {
                $'module example.test/($module)

go 1.27.0
' | save ($scratch | path join services $module go.mod)
                {
                    tasks: {
                        build: {depends: ["^build"], run: $'echo ($module)-build >> "$GRAPH_LOG"'}
                        check: {depends: ["^check" ":build"], run: $'echo ($module)-check >> "$GRAPH_LOG"'}
                        "check:platform": {depends: ["^check:platform" ":build"], run: $'echo ($module)-platform >> "$GRAPH_LOG"'}
                    }
                } | to toml | save ($scratch | path join services $module mise.toml)
            }
            "package b\nfunc Value() int { return 1 }\n" | save services/b/b.go
            'package a
import "example.test/b"
func Value() int { return b.Value() }
' | save services/a/a.go
            {
                _: {nusage: {project: {depends_add: ["go:example.test/a"]}}}
                tasks: {
                    check: {depends: ["^build" "^check"], run: 'echo consumer-check >> "$GRAPH_LOG"'}
                    "check:platform": {depends: ["^build" "^check:platform"], run: 'echo consumer-platform >> "$GRAPH_LOG"'}
                }
            } | to toml | save consumer/mise.toml
            # A project with no tasks must still participate in transitive traversal.
            {_: {nusage: {project: {depends_add: ["custom:consumer"]}}}} | to toml | save bridge/mise.toml

            let projects = checked mise exec -- mise tasks graph --json | from json | get projects
            assert equal ($projects | where id == cargo:a | get dependencies.0) [cargo:b]
            assert equal ($projects | where id == go:example.test/a | get dependencies.0) [go:example.test/b]
            assert equal ($projects | where id == custom:consumer | get dependencies.0) [go:example.test/a]
            assert equal ($projects | where id == custom:bridge | get dependencies.0) [custom:consumer]
            assert not ("events" | path exists)
            assert not ("events.unexpected" | path exists)

            # Cold execution: graph preparation precedes dependency resolution.
            let output = ".mise/conf.d/_workspace-graph.toml"
            rm $output go.work
            checked mise exec -- mise run //:root-check | ignore
            let events = open --raw events | lines
            assert equal ($events | sort) [a-build a-check b-build b-check consumer-check root-check]
            before $events b-build a-build
            before $events b-build b-check
            before $events b-check a-check
            before $events a-build a-check
            before $events a-check consumer-check
            before $events consumer-check root-check
            assert not ("events.unexpected" | path exists)

            rm events
            checked mise exec -- mise run //:root-platform | ignore
            let platform = open --raw events | lines
            assert equal ($platform | sort) [a-build a-platform b-build b-platform consumer-platform root-platform]
            before $platform b-platform a-platform
            before $platform a-platform consumer-platform

            let runs = open --raw provider-runs | lines | length
            checked mise exec -- "true" | ignore
            assert equal (open --raw provider-runs | lines | length) $runs
            # Included task definitions are provider inputs, including hidden shared files.
            mkdir .mise/lib
            "[probe]\nrun = 'true'\n" | save .mise/lib/probe.tasks.toml
            checked mise exec -- "true" | ignore
            assert equal (open --raw provider-runs | lines | length) ($runs + 1)
            # Metadata in active config fragments extends native project dependencies.
            mkdir consumer/.mise/conf.d
            {_: {nusage: {project: {depends_add: ["cargo:a"]}}}} | to toml | save consumer/.mise/conf.d/project.toml
            checked mise exec -- "true" | ignore
            assert equal (graph | where id == custom:consumer | get dependencies.0) [cargo:a go:example.test/a]
            assert equal (graph | where id == cargo:a | get dependencies.0) [cargo:b]

            # A new consumer needs no edits to existing files or a consumer inventory.
            mkdir newcomer
            open consumer/mise.toml | update tasks.check.run 'echo newcomer-check >> "$GRAPH_LOG"' | to toml | save newcomer/mise.toml
            rm events
            checked mise exec -- mise run //newcomer:check | ignore
            let events = open --raw events | lines
            before $events a-check newcomer-check
            assert not ("consumer-check" in $events)

            # Select affected checks in this fixture, independently of the real repo layout.
            'go.work
go.work.sum
.mise/conf.d/_*.toml
provider-runs
events*
cache/
data/
config/
' | save .gitignore
            checked git init --quiet | ignore
            checked git config user.name "workspace graph test" | ignore
            checked git config user.email test@nusage.invalid | ignore
            checked git add . | ignore
            checked git -c commit.gpgsign=false commit --quiet --message base | ignore
            let base = checked git rev-parse HEAD
            "\n// changed\n" | save --append services/b/b.go
            checked git add services/b/b.go | ignore
            checked git -c commit.gpgsign=false commit --quiet --message change | ignore
            let selected = checked mise exec -- mise run --affected --affected-base $base --affected-head HEAD --affected-committed --affected-json //...:check
                | from json | get tasks | get name | sort
            assert equal $selected [//consumer:check //newcomer:check //services/a:check //services/b:check]
            let local_base = checked git rev-parse HEAD
            "\n# local configuration change\n" | save --append consumer/mise.toml
            checked git add consumer/mise.toml | ignore
            checked git -c commit.gpgsign=false commit --quiet --message local | ignore
            let local = checked mise exec -- mise run --affected --affected-base $local_base --affected-head HEAD --affected-committed --affected-json //...:check
                | from json | get tasks | get name | sort
            assert equal $local [//consumer:check]
            # CI configuration belongs to the root; it must not select unrelated checks.
            let workflow_base = checked git rev-parse HEAD
            mkdir .github/workflows
            "name: release\non: workflow_dispatch\njobs: {}\n" | save .github/workflows/release.yml
            checked git add .github/workflows/release.yml | ignore
            checked git -c commit.gpgsign=false commit --quiet --message workflow | ignore
            let workflow = checked mise exec -- mise run --affected --affected-base $workflow_base --affected-head HEAD --affected-committed --affected-json //...:check
                | from json | get tasks | get name | sort
            assert equal $workflow []
            mv newcomer moved
            checked mise exec -- "true" | ignore
            assert not (graph | any {|p| $p.id == custom:newcomer})
            assert (graph | any {|p| $p.id == custom:moved})
            rm -r moved
            checked mise exec -- "true" | ignore
            assert not (graph | any {|p| $p.id == custom:moved})

            # Go test imports add edges; removing imports and modules removes them.
            "package a\nfunc Value() int { return 0 }\n" | save --force services/a/a.go
            'package a
import (_ "example.test/b"; "testing")
func TestLocal(t *testing.T) {}
' | save services/a/a_test.go
            checked mise exec -- "true" | ignore
            assert equal (graph | where id == go:example.test/a | get dependencies.0) [go:example.test/b]
            rm services/a/a_test.go
            checked mise exec -- "true" | ignore
            assert equal (graph | where id == go:example.test/a | get dependencies.0) []
            rm -r services/b
            checked mise exec -- "true" | ignore
            assert not (graph | any {|p| $p.id == go:example.test/b})

            let previous = open --raw $output
            {_: {nusage: {project: {depends_add: ["custom:missing"]}}}} | to toml | save consumer/.mise/conf.d/bad.toml
            let bad = ^mise exec -- true | complete
            assert ($bad.exit_code != 0)
            assert ($bad.stderr | str contains "custom:missing") $bad.stderr
            assert equal (open --raw $output) $previous
            rm consumer/.mise/conf.d/bad.toml
            {_: {nusage: {project: {depends_add: ["custom:bridge"]}}}} | to toml | save consumer/.mise/conf.d/cycle.toml
            rm events
            let cycle = ^mise exec -- mise run //:root-check | complete
            assert ($cycle.exit_code != 0)
            assert ($cycle.stderr | str contains "cycle") $cycle.stderr
            assert not ("events" | path exists)
            rm consumer/.mise/conf.d/cycle.toml
            checked mise exec -- "true" | ignore
            assert equal (open --raw $output) $previous
            'package a
import _ "example.test/missing"
' | save --force services/a/a.go
            let failed = ^mise deps install workspace-graph | complete
            assert ($failed.exit_code != 0)
            assert ($failed.stderr | str contains "example.test/missing") $failed.stderr
            assert equal (open --raw $output) $previous
            "package a\n" | save --force services/a/a.go
            "invalid [toml" | save --force $output
            checked nu $generator | ignore
            assert (graph | any {|p| $p.id == custom:consumer})
        }
        null
    } catch {|err| $err}
    rm -rf $scratch
    if $result != null { error make $result }
}

@test
def "managed target configurations stay outside the discovered project graph" [] {
    let project = $generator | path dirname | path dirname
    let config = open ($project | path join mise.toml)
    let provider = $config.deps.workspace-graph
    let scratch = mktemp -d | path expand
    let targets = $scratch | path join .cache mbx-targets
    let result = try {
        mkdir ($targets | path join view) ($scratch | path join app)
        {tasks: {unwanted: {run: "true"}}} | to toml | save ($targets | path join view mise.toml)
        "not a Go module" | save ($targets | path join view go.mod)
        checked ln -s ($targets | path join view) ($scratch | path join target) | ignore
        cp ($project | path join .miserc.toml) ($scratch | path join .miserc.toml)
        with-env {
            NU_LIB_DIRS: ($env.NU_LIB_DIRS | str join (char esep))
            MISE_CONFIG_DIR: ($scratch | path join .config)
            MISE_DATA_DIR: ($scratch | path join .data)
            MISE_CACHE_DIR: ($scratch | path join .cache)
            MISE_TRUSTED_CONFIG_PATHS: $scratch
            GOWORK: ""
        } {
            hide-env --ignore-errors MISE_IGNORED_CONFIG_PATHS
            cd $scratch
            {
                monorepo_root: true
                monorepo: {config_roots: ["[!.]*" "[!.]*/[!.]*" "[!.]*/[!.]*/[!.]*"]}
                settings: {experimental: true}
                env: {
                    NU_LIB_DIRS: $env.NU_LIB_DIRS
                    MBX_TARGET_ROOT: $config.env.MBX_TARGET_ROOT
                    MISE_IGNORED_CONFIG_PATHS: $config.env.MISE_IGNORED_CONFIG_PATHS
                    _: {path: $env.PATH}
                }
                deps: {workspace-graph: ($provider | update run $'nu "($generator)"')}
            } | to toml | save mise.toml
            {tasks: {check: {run: "true"}}} | to toml | save app/mise.toml
            assert equal (mise env | get MBX_TARGET_ROOT) $targets
            let discovered = ^mise exec -- mise tasks ls --all --json | complete
            assert equal $discovered.exit_code 0 $discovered.stderr
            assert not ($discovered.stderr | str contains "glob matched path outside") $discovered.stderr
            assert equal ($discovered.stdout | from json | get name) [//app:check]
            assert equal (graph | get id | sort) [custom:app custom:root]
        }
        null
    } catch {|err| $err}
    rm -rf $scratch
    if $result != null { error make $result }
}
