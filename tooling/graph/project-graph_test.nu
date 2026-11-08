use std/assert
use ../../catalog/packages/mise *
use std/testing *

const here = path self | path dirname
const providers = [go-workspace go-imports nu-imports project-graph]
const assembler = path self | path dirname | path join project-graph.nu
const guard = path self | path dirname | path join current.nu
const workspace = path self | path dirname | path join go-workspace.nu
const go_imports = path self | path dirname | path join go-imports.nu
const nu_imports = path self | path dirname | path join nu-imports.nu

def --wrapped checked [...args: string] {
    let result = run-external ...$args | complete
    assert equal $result.exit_code 0 ($result.stderr + $result.stdout)
    $result.stdout | str trim
}

def --wrapped failing [...args: string] {
    let result = run-external ...$args | complete
    assert ($result.exit_code != 0) $result.stdout
    $result.stderr
}

def graph [] {
    mise tasks graph | get projects
}

def dependencies [id: string] {
    graph | where id == $id | get dependencies.0
}

def edges [id: string] {
    graph | where id == $id | get metadata.0.edges | from json
}

def before [events: list<string>, first: string, second: string] {
    let positions = $events | enumerate
    assert equal ($positions | where item == $first | length) 1
    assert equal ($positions | where item == $second | length) 1
    assert (($positions | where item == $first | get index.0) < ($positions | where item == $second | get index.0))
}

# The graph providers as the repository declares them, each run logged.
def provider-config [] {
    let config = open ($here | path dirname | path dirname | path join mise.toml)
    let scripts = {go-workspace: $workspace, go-imports: $go_imports, nu-imports: $nu_imports, project-graph: $assembler}
    $providers | reduce --fold {} {|name, acc|
        $acc | insert $name ($config.deps | get $name | update run $'nus "($scripts | get $name)" && echo ($name) >> provider-runs')
    }
}

# The providers that ran since the last call, in order.
def runs-since [count: int] {
    open --raw provider-runs | lines | skip $count
}

def isolated [scratch: string] {
    {
        NUS_MODULES: $env.NUS_MODULES, NUS_TOOLS: $env.NUS_TOOLS
        MISE_CONFIG_DIR: ($scratch | path join config)
        MISE_DATA_DIR: ($scratch | path join data)
        MISE_CACHE_DIR: ($scratch | path join cache)
        MISE_TRUSTED_CONFIG_PATHS: $scratch
        MISE_IGNORED_CONFIG_PATHS: ""
        GOWORK: ""
        GOPROXY: "off"
        GIT_CONFIG_GLOBAL: ($scratch | path join gitconfig)
        GIT_CONFIG_NOSYSTEM: "1"
    }
}

@test
def "discovered projects carry kinds and typed edges that drive caret tasks and affected selection" [] {
    let scratch = mktemp -d | path expand
    let result = try {
        with-env (isolated $scratch) {
            cd $scratch
            mkdir bin crates/a/src crates/b/src services/a services/b consumer bridge samples generator entries/alpha
            for command in [cargo] {
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
                env: {NUS_MODULES: $env.NUS_MODULES, NUS_TOOLS: $env.NUS_TOOLS, _: {path: ($env.PATH | prepend ($nu.current-exe | path dirname) | prepend ($scratch | path join bin))}, GRAPH_LOG: ($scratch | path join events)}
                _: {nusage: {project: {depends_add: ["nu:bridge"]}}}
                deps: (provider-config)
                tasks: {
                    graph-current: {env: {NUS_LOADED_GRAPH: "{{ vars.project_graph | default(value='') }}"}, run: $'nus "($guard)"'}
                    root-check: {depends: ["//:graph-current" "^build" "^check"], run: 'echo root-check >> "$GRAPH_LOG"'}
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
                _: {nusage: {project: {depends_add: ["go:example.test/a" "fixtures:demo"]}}}
                tasks: {
                    check: {depends: ["^build" "^check"], run: 'echo consumer-check >> "$GRAPH_LOG"'}
                    "check:platform": {depends: ["^build" "^check:platform"], run: 'echo consumer-platform >> "$GRAPH_LOG"'}
                }
            } | to toml | save consumer/mise.toml
            # A project with no tasks must still participate in transitive traversal.
            {_: {nusage: {project: {depends_add: ["nu:consumer"]}}}} | to toml | save bridge/mise.toml
            {_: {nusage: {project: {kind: fixtures, name: demo}}}} | to toml | save samples/mise.toml
            # A generator whose task runs in a Go module, and an entry its spec comes from.
            {
                _: {nusage: {project: {kind: gen}}}
                tasks: {export: {dir: "../services/b", run: "true"}}
            } | to toml | save generator/mise.toml
            "export def shared [] { }\n" | save generator/lib.nu
            {
                _: {nusage: {catalog: {spec: {run: "mise run //generator:export"}}}}
                tasks: {check: {depends: ["^check"], run: 'echo alpha-check >> "$GRAPH_LOG"'}}
            } | to toml | save entries/alpha/mise.toml
            "use ../../generator/lib.nu *\n" | save entries/alpha/check.nu

            let projects = checked mise exec -- mise tasks graph --json | from json | get projects
            let ids = $projects | get id | sort
            assert equal $ids [cargo:a cargo:b catalog:alpha fixtures:demo gen:generator go:example.test/a go:example.test/b nu:bridge nu:consumer nu:root]
            assert equal ($projects | where id == cargo:a | get dependencies.0) [cargo:b]
            assert equal ($projects | where id == go:example.test/a | get dependencies.0) [go:example.test/b]
            assert equal ($projects | where id == nu:consumer | get dependencies.0) [fixtures:demo go:example.test/a]
            assert equal ($projects | where id == nu:bridge | get dependencies.0) [nu:consumer]
            assert equal ($projects | where id == nu:root | get dependencies.0) [nu:bridge]
            assert equal ($projects | where id == catalog:alpha | get dependencies.0) [gen:generator]
            assert equal ($projects | where id == gen:generator | get dependencies.0) [go:example.test/b]
            # Each added edge keeps its kind and the file and line it comes from.
            let declared = {|target| open --raw consumer/mise.toml | lines | enumerate | where {|l| $l.item | str contains $'"($target)"' } | get 0.index | $"consumer/mise.toml:($in + 1)" }
            assert equal (edges nu:consumer) [
                {to: "fixtures:demo", kind: fixtures, source: (do $declared fixtures:demo)}
                {to: "go:example.test/a", kind: declared, source: (do $declared go:example.test/a)}
            ]
            assert equal (edges catalog:alpha | select to kind) [
                {to: "gen:generator", kind: nu-use}
                {to: "gen:generator", kind: spec-generator}
            ]
            assert equal (edges catalog:alpha | where kind == nu-use | get source) ["entries/alpha/check.nu:1"]
            assert equal (edges gen:generator | select to kind) [{to: "go:example.test/b", kind: task-dir}]
            assert equal (graph | where id == catalog:alpha | get metadata.0.kind) catalog
            assert not ("events" | path exists)
            assert not ("events.unexpected" | path exists)

            # Cold execution: graph preparation precedes dependency resolution.
            let output = ".mise/conf.d/_project-graph.toml"
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

            # A warm run prepares nothing; each analyzer reruns only for what it reads, and the
            # assembler for anything an analyzer reads.
            let runs = open --raw provider-runs | lines | length
            checked mise exec -- "true" | ignore
            assert equal (runs-since $runs) []
            "\n# a comment\n" | save --append generator/lib.nu
            checked mise exec -- "true" | ignore
            assert equal (runs-since $runs) [nu-imports project-graph]
            let runs = open --raw provider-runs | lines | length
            "\n// a comment\n" | save --append services/b/b.go
            checked mise exec -- "true" | ignore
            assert equal (runs-since $runs) [go-imports project-graph]
            # Included task definitions are analyzer inputs, including hidden shared files.
            let runs = open --raw provider-runs | lines | length
            mkdir tooling/tasks
            "[probe]\nrun = 'true'\n" | save tooling/tasks/probe.tasks.toml
            checked mise exec -- "true" | ignore
            assert equal (runs-since $runs) [nu-imports project-graph]
            # Metadata in active config fragments extends native project dependencies.
            mkdir consumer/.mise/conf.d
            {_: {nusage: {project: {depends_add: ["cargo:a"]}}}} | to toml | save consumer/.mise/conf.d/project.toml
            checked mise exec -- "true" | ignore
            assert equal (dependencies nu:consumer) [cargo:a fixtures:demo go:example.test/a]
            assert equal (edges nu:consumer | where to == cargo:a | get source) ["consumer/.mise/conf.d/project.toml:2"]
            assert equal (dependencies cargo:a) [cargo:b]

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
**/.mise/conf.d/_*.toml
.cache/
provider-runs
events*
cache/
data/
config/
' | save .gitignore
            checked git init --quiet | ignore
            checked git config user.name "project graph test" | ignore
            checked git config user.email test@nusage.invalid | ignore
            checked git add . | ignore
            checked git -c commit.gpgsign=false commit --quiet --message base | ignore
            let base = checked git rev-parse HEAD
            "\n// changed\n" | save --append services/b/b.go
            checked git add services/b/b.go | ignore
            checked git -c commit.gpgsign=false commit --quiet --message change | ignore
            let selected = checked mise exec -- mise run --affected --affected-base $base --affected-head HEAD --affected-committed --affected-json //...:check
            | from json | get tasks | get name | sort
            # The entry follows its generator into the Go module the generator's task runs in.
            assert equal $selected [//consumer:check //entries/alpha:check //newcomer:check //services/a:check //services/b:check]
            # A data project's change selects what declares it.
            let data_base = checked git rev-parse HEAD
            "fixture\n" | save samples/case.txt
            checked git add samples/case.txt | ignore
            checked git -c commit.gpgsign=false commit --quiet --message data | ignore
            let data = checked mise exec -- mise run --affected --affected-base $data_base --affected-head HEAD --affected-committed --affected-json //...:check
            | from json | get tasks | get name | sort
            assert equal $data [//consumer:check //newcomer:check]
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
            assert not (graph | any {|p| $p.id == nu:newcomer })
            assert (graph | any {|p| $p.id == nu:moved })
            rm -r moved
            checked mise exec -- "true" | ignore
            assert not (graph | any {|p| $p.id == nu:moved })

            # Go test imports add edges; removing imports and modules removes them.
            "package a\nfunc Value() int { return 0 }\n" | save --force services/a/a.go
            'package a
import (_ "example.test/b"; "testing")
func TestLocal(t *testing.T) {}
' | save services/a/a_test.go
            checked mise exec -- "true" | ignore
            assert equal (dependencies go:example.test/a) [go:example.test/b]
            assert equal (edges go:example.test/a | get kind) [go-import]
            rm services/a/a_test.go
            checked mise exec -- "true" | ignore
            assert equal (dependencies go:example.test/a) []

            # A plain `mise run` that resolved its tasks from a graph its providers then
            # rewrote stops at the guard; the next run, or one through `mise exec`, does not.
            mkdir bridge/.mise/conf.d
            {_: {nusage: {project: {depends_add: ["cargo:b"]}}}} | to toml | save bridge/.mise/conf.d/extra.toml
            let stale = failing mise run //:root-check
            assert ($stale | str contains "The project graph changed after this mise process resolved its tasks") $stale
            checked mise run //:root-check | ignore
            rm bridge/.mise/conf.d/extra.toml
            checked mise exec -- mise run //:root-check | ignore

            rm -r services/b generator/mise.toml generator/lib.nu entries/alpha
            checked mise exec -- "true" | ignore
            assert not (graph | any {|p| $p.id == go:example.test/b })

            let previous = open --raw $output
            {_: {nusage: {project: {depends_add: ["nu:missing"]}}}} | to toml | save consumer/.mise/conf.d/bad.toml
            let bad = failing mise exec -- "true"
            assert ($bad | str contains "unknown project dependency nu:missing") $bad
            assert equal (open --raw $output) $previous
            rm consumer/.mise/conf.d/bad.toml
            # A cycle stops before mise reads it, naming the edges that close it.
            {_: {nusage: {project: {depends_add: ["nu:bridge"]}}}} | to toml | save consumer/.mise/conf.d/cycle.toml
            rm events
            let cycle = failing mise exec -- mise run //:root-check
            assert ($cycle | str contains "project dependency cycle") $cycle
            assert ($cycle | str contains "declared at consumer/.mise/conf.d/cycle.toml:2") $cycle
            assert not ("events" | path exists)
            rm consumer/.mise/conf.d/cycle.toml
            checked mise exec -- "true" | ignore
            assert equal (open --raw $output) $previous
            'package a
import _ "example.test/missing"
' | save --force services/a/a.go
            let failed = ^mise deps install go-imports | complete
            assert ($failed.exit_code != 0)
            assert ($failed.stderr | str contains "example.test/missing") $failed.stderr
            assert equal (open --raw $output) $previous
            "package a\n" | save --force services/a/a.go
            "invalid [toml" | save --force $output
            checked nus $assembler | ignore
            assert (graph | any {|p| $p.id == nu:consumer })
        }
        null
    } catch {|err| $err }
    rm -rf $scratch
    if $result != null { error make $result }
}

@test
def "the graph refuses what mise would drop or what the kinds forbid" [] {
    let scratch = mktemp -d | path expand
    let result = try {
        with-env (isolated $scratch) {
            cd $scratch
            mkdir app generator entry samples plain
            {
                monorepo_root: true
                monorepo: {config_roots: ["[!.]*"]}
                settings: {experimental: true}
                env: {NUS_MODULES: $env.NUS_MODULES, NUS_TOOLS: $env.NUS_TOOLS, _: {path: ($env.PATH | prepend ($nu.current-exe | path dirname))}}
                deps: (provider-config)
            } | to toml | save mise.toml
            {_: {nusage: {project: {}}}, tasks: {check: {run: "true"}}} | to toml | save app/mise.toml
            {_: {nusage: {project: {kind: gen}}}} | to toml | save generator/mise.toml
            {_: {nusage: {catalog: {spec: {run: "mise run //generator:x"}}}}} | to toml | save entry/mise.toml
            {_: {nusage: {project: {kind: fixtures, name: demo}}}} | to toml | save samples/mise.toml
            checked mise exec -- "true" | ignore
            assert equal (graph | get id | sort) [catalog:entry fixtures:demo gen:generator nu:app nu:root]

            # `^` dependencies in a config root that is no project resolve to nothing in mise.
            {tasks: {check: {depends: ["^check"], run: "true"}}} | to toml | save plain/mise.toml
            let caret = failing mise exec -- "true"
            assert ($caret | str contains "plain/mise.toml") $caret
            assert ($caret | str contains "^check in plain, which is no project") $caret
            rm plain/mise.toml

            # A computed task name is an error until its project lists the file.
            "let task = '//app:check'\nmise run $task\n" | save app/run.nu
            let dynamic = failing mise exec -- "true"
            assert ($dynamic | str contains "app/run.nu:2: mise run $task names no literal target") $dynamic
            assert ($dynamic | str contains "list run.nu in [_.nusage.project].dynamic of nu:app") $dynamic
            {_: {nusage: {project: {dynamic: [run.nu]}}}, tasks: {check: {run: "true"}}} | to toml | save --force app/mise.toml
            checked mise exec -- "true" | ignore

            # Entries depend on generators, and data projects on nothing.
            {_: {nusage: {project: {kind: gen, depends_add: [catalog:entry]}}}} | to toml | save --force generator/mise.toml
            let reversed = failing mise exec -- "true"
            assert ($reversed | str contains "generator gen:generator depends on catalog entry catalog:entry") $reversed
            {_: {nusage: {project: {kind: gen}}}} | to toml | save --force generator/mise.toml
            {_: {nusage: {project: {kind: fixtures, name: demo, depends_add: [nu:app]}}}} | to toml | save --force samples/mise.toml
            let data = failing mise exec -- "true"
            assert ($data | str contains "a fixtures project depends on nothing") $data
            {_: {nusage: {project: {kind: fixtures, name: demo, typo: true}}}} | to toml | save --force samples/mise.toml
            let typo = failing mise exec -- "true"
            assert ($typo | str contains "[_.nusage.project] has no key typo") $typo
            {_: {nusage: {project: {kind: fixtures, name: demo}}}} | to toml | save --force samples/mise.toml

            # A test suite's loads are its `nu-test` input group, beside it in generated config.
            "export def helper [] { }\n" | save app/helper.nu
            "use helper.nu *\n" | save app/suite_test.nu
            checked mise exec -- "true" | ignore
            let inputs = "app/.mise/conf.d/_nu-inputs.toml"
            assert equal (open $inputs | get task_config.input_groups.nu-test) [helper.nu suite_test.nu]
            # mise reads one file's input groups per config root, so hand-written ones conflict.
            mkdir app/.mise/conf.d
            {task_config: {input_groups: {mine: [x]}}} | to toml | save app/.mise/conf.d/groups.toml
            let groups = failing mise exec -- "true"
            assert ($groups | str contains "app: its config defines [task_config.input_groups]") $groups
            rm app/.mise/conf.d/groups.toml
            rm app/suite_test.nu
            checked mise exec -- "true" | ignore
            assert not ($inputs | path exists)
        }
        null
    } catch {|err| $err }
    rm -rf $scratch
    if $result != null { error make $result }
}

@test
def "managed target configurations stay outside the discovered project graph" [] {
    let project = $here | path dirname | path dirname
    let config = open ($project | path join mise.toml)
    let scratch = mktemp -d | path expand
    let targets = $scratch | path join .cache mbx-targets
    let result = try {
        mkdir ($targets | path join view) ($scratch | path join app)
        {tasks: {unwanted: {run: "true"}}} | to toml | save ($targets | path join view mise.toml)
        "not a Go module" | save ($targets | path join view go.mod)
        checked ln -s ($targets | path join view) ($scratch | path join target) | ignore
        cp ($project | path join .miserc.toml) ($scratch | path join .miserc.toml)
        with-env {
            NUS_MODULES: $env.NUS_MODULES, NUS_TOOLS: $env.NUS_TOOLS
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
                    NUS_MODULES: $env.NUS_MODULES, NUS_TOOLS: $env.NUS_TOOLS
                    MBX_TARGET_ROOT: $config.env.MBX_TARGET_ROOT
                    MISE_IGNORED_CONFIG_PATHS: $config.env.MISE_IGNORED_CONFIG_PATHS
                    _: {path: ($env.PATH | prepend ($nu.current-exe | path dirname))}
                }
                deps: (provider-config)
            } | to toml | save mise.toml
            {tasks: {check: {run: "true"}}} | to toml | save app/mise.toml
            assert equal (mise env | get MBX_TARGET_ROOT) $targets
            let discovered = ^mise exec -- mise tasks ls --all --json | complete
            assert equal $discovered.exit_code 0 $discovered.stderr
            assert not ($discovered.stderr | str contains "glob matched path outside") $discovered.stderr
            assert equal ($discovered.stdout | from json | get name) [//app:check]
            assert equal (graph | get id | sort) [nu:root]

            # `cargo package` leaves real crate configs in `target/package/<crate>`.
            rm target
            mkdir target/package/demo
            {tasks: {packaged: {run: "true"}}} | to toml | save target/package/demo/mise.toml
            let packaged = ^mise exec -- mise tasks ls --all --json | complete
            assert equal $packaged.exit_code 0 $packaged.stderr
            assert equal ($packaged.stdout | from json | get name) [//app:check]
        }
        null
    } catch {|err| $err }
    rm -rf $scratch
    if $result != null { error make $result }
}
