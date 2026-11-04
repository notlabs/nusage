#!/usr/bin/env nu
#MISE description="Check discovery and dependency edges without building nusage"
use std/assert

const generator = path self | path dirname | path join ../workspace-graph.nu | path expand

def --wrapped checked [...args: string] {
    let result = run-external ...$args | complete
    assert equal $result.exit_code 0 ($result.stderr + $result.stdout)
    $result.stdout
}

def graph [] {
    checked mise tasks graph --json | from json | get projects
}

let provider = open (
    $generator
    | path dirname
    | path dirname
    | path join mise.toml
) | get deps.workspace-graph

let scratch = mktemp -d

let result = try {
    with-env {
        MISE_CONFIG_DIR: ($scratch | path join config)
        MISE_DATA_DIR: ($scratch | path join data)
        MISE_CACHE_DIR: ($scratch | path join cache)
        MISE_TRUSTED_CONFIG_PATHS: $scratch
        MISE_IGNORED_CONFIG_PATHS: ""
        GOWORK: ""
        GOPROXY: "off"
    } {
        cd $scratch
        checked git init --quiet | ignore
        {
            monorepo_root: true
            monorepo: {config_roots: ["[!.]*" "[!.]*/[!.]*" "[!.]*/[!.]*/[!.]*"]}
            settings: {experimental: true}
            env: {_: {path: $env.PATH}}
            deps: {workspace-graph: ($provider | update run $'nu "($generator)" && echo prepared >> provider-runs')}
        } | to toml | save mise.toml
        mkdir crates/a/src crates/b/src services/a services/b consumer
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
            {tasks: {check: {run: "touch task-executed"}}} | to toml | save ($scratch | path join services $module mise.toml)
        }
        "package b\nfunc Value() int { return 1 }\n" | save services/b/b.go
        'package a
import "example.test/b"
func Value() int { return b.Value() }
' | save services/a/a.go
        {tasks: {check: {depends: ["//services/a:check"] run: "touch task-executed"}}} | to toml | save consumer/mise.toml

        let projects = checked mise exec -- mise tasks graph --json | from json | get projects
        assert equal ($projects | where id == cargo:a | get dependencies.0) [cargo:b]
        assert equal ($projects | where id == go:example.test/a | get dependencies.0) [go:example.test/b]
        assert equal ($projects | where id == custom:consumer | get dependencies.0) [go:example.test/a]
        assert not ("consumer/task-executed" | path exists)
        let output = ".mise/conf.d/_workspace-graph.toml"
        assert equal (open --raw provider-runs | lines | length) 1
        let before = open --raw $output
        checked mise exec -- "true" | ignore
        assert equal (open --raw $output) $before
        assert equal (open --raw provider-runs | lines | length) 1

        # Configuration fragments are inputs; generated fragments do not retrigger it.
        {env: {WORKSPACE_GRAPH_PROBE: "changed"}} | to toml | save .mise/conf.d/probe.toml
        checked mise exec -- "true" | ignore
        assert equal (open --raw provider-runs | lines | length) 2
        checked mise exec -- "true" | ignore
        assert equal (open --raw provider-runs | lines | length) 2

        # No registry edit: a new config appears; moving and deleting it removes old IDs.
        mkdir added
        {tasks: {check: {run: "true"}}} | to toml | save added/mise.toml
        checked mise exec -- "true" | ignore
        assert (graph | any {|p| $p.id == custom:added})
        mv added moved
        checked mise exec -- "true" | ignore
        assert not (graph | any {|p| $p.id == custom:added})
        assert (graph | any {|p| $p.id == custom:moved})
        rm -r moved
        checked mise exec -- "true" | ignore
        assert not (graph | any {|p| $p.id == custom:moved})

        # Test-only imports are edges too; removing all imports removes the edge.
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
        'package a
import _ "example.test/missing"
' | save --force services/a/a.go
        let failed = ^mise deps install workspace-graph | complete
        assert ($failed.exit_code != 0)
        assert ($failed.stderr | str contains "example.test/missing") $failed.stderr
        assert equal (open --raw $output) $previous
        "package a\n" | save --force services/a/a.go

        # An invalid previous output cannot prevent the collector from repairing it.
        "invalid [toml" | save --force $output
        checked nu $generator | ignore
        assert (graph | any {|p| $p.id == custom:consumer})
    }
    null
} catch {|err| $err }
rm -rf $scratch
if $result != null { error make $result }
print "workspace graph: native Cargo, Go imports, task prerequisites, discovery and refresh"
