#!/usr/bin/env nu
# Offline checks: the real version command, formatter fixtures, and generated ps wrapper.
use std/assert
use docker-compose *
use ../../schemas/lib.nu [load-suite check-examples finish]

const here = path self | path dirname

let version = docker-compose version
assert equal ($version | describe) 'record<version: string>'
assert ($version.version | str starts-with 'v')

let fixture = $here | path join schemas fixtures ps.jsonl
let records = open --raw $fixture | lines | each { from json }
let suite = load-suite ($here | path join schemas outputs.nuon)

let examples = [
    {
        id: running
        output: ps
        document: $records.0
        valid: true
    }
    {
        id: exited
        output: ps
        document: $records.1
        valid: true
    }
    {
        id: exit-code-type
        output: ps
        document: ($records.1 | update ExitCode "7")
        valid: false
    }
    {
        id: publisher-type
        output: ps
        document: (
            $records.0
            | update Publishers [
                {
                    URL: ""
                    TargetPort: "80"
                    PublishedPort: 8080
                    Protocol: tcp
                }
            ]
        )
        valid: false
    }
    {
        id: missing-state
        output: ps
        document: ($records.0 | reject State)
        valid: false
    }
]
finish (check-examples $suite $examples)

let scratch = mktemp -d
try {
    let fake = $scratch | path join docker-compose
    '#!/usr/bin/env nu
def --wrapped main [...args: string] {
    $args | to json | save --force $env.COMPOSE_PS_ARGV
    if ($env.COMPOSE_PS_FAIL? | default false | into bool) {
        print --stderr "fixture daemon unavailable"
        exit 1
    }
    if not ($env.COMPOSE_PS_EMPTY? | default false | into bool) {
        print --no-newline (open --raw $env.COMPOSE_PS_FIXTURE)
    }
}
' | save $fake
    ^chmod +x $fake
    let argv = $scratch | path join argv.json
    with-env {
        PATH: ($env.PATH | prepend $scratch)
        COMPOSE_PS_FIXTURE: $fixture
        COMPOSE_PS_ARGV: $argv
        COMPOSE_PS_EMPTY: "false"
        COMPOSE_PS_FAIL: "false"
    } {
        let containers = docker-compose ps web job --all --status [running exited] --filter status=running
        assert equal $containers $records
        assert equal ($containers | get ExitCode | describe) 'list<int>'
        assert equal ($containers.0.ID | str length) 64
        assert equal $containers.1.Publishers null
        assert equal $containers.0.Publishers.0.PublishedPort 8080

        let passed = open $argv
        assert equal ($passed | skip 4 | first 2) [web job]
        assert equal ($passed | where {|word| $word == --format } | length) 1
        assert equal ($passed | where {|word| $word == --no-trunc } | length) 1
        assert equal ($passed | where {|word| $word == --all } | length) 1
        let format_at = $passed | enumerate | where item == --format | first | get index
        assert equal ($passed | get ($format_at + 1)) json
        let statuses = $passed | enumerate | where item == --status | each {|entry| $passed | get ($entry.index + 1) }
        assert equal $statuses [running exited]
        let filter_at = $passed | enumerate | where item == --filter | first | get index
        assert equal ($passed | get ($filter_at + 1)) status=running

        with-env {COMPOSE_PS_EMPTY: "true"} {
            assert equal (docker-compose ps) []
        }
        let failure = try {
            with-env {COMPOSE_PS_FAIL: "true"} { docker-compose ps }
            null
        } catch {|err| $err }
        assert ($failure != null) "A failed Docker command must not look like an empty table"
    }

    let signature = scope commands | where name == 'docker-compose ps' | first | get signatures.nothing
    let names = $signature | get parameter_name
    for hidden in [format no-trunc quiet services orphans] {
        assert ($hidden not-in $names) $"($hidden) must not override structured ps output"
    }
} catch {|err|
    rm -r $scratch
    error make $err
}
rm -r $scratch
print "docker-compose: version, ps schemas and generated-wrapper checks passed"
