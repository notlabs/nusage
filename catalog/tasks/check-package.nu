#!/usr/bin/env nus
#USAGE about "Run the packaged catalog tasks from an unrelated project"
use std/assert

const tasks = path self | path dirname

# A consumer owns its entries and schemas; the package must supply everything else.
let scratch = mktemp --directory
let consumer = $scratch | path join consumer
let package = $consumer | path join dist
mkdir ($consumer | path join lib demo schemas) ($consumer | path join bin)
let config = $consumer | path join mise.toml
{
    task_config: {
        includes: [
            ($package | path join oci)
        ]
    }
    env: {
        _: {
            path: (
                [nus nu usage]
                | each {|tool| which $tool | where type == external | first | get path | path dirname }
                | uniq
            )
        }
    }
    _: {
        nusage: {
            catalog: {
                demo: {
                    spec: {run: "open --raw lib/demo/source.kdl | print --no-newline"}
                }
            }
        }
    }
    vars: {catalog_version: "0.0.0"}
} | to toml | save $config
'name "demo"
bin "demo"
' | save ($consumer | path join lib demo source.kdl)
"# generated below\n" | save ($consumer | path join lib demo mod.nu)
{
    format: 1
    outputs: [
        {
            id: result
            command: []
            name: json
            framing: json
            select: ["--json"]
            schema: result.schema.json
        }
    ]
} | to nuon | save ($consumer | path join lib demo schemas outputs.nuon)
{
    type: object
    properties: {
        ok: {type: boolean}
    }
    required: [ok]
    additionalProperties: false
} | to json | save ($consumer | path join lib demo schemas result.schema.json)
'#!/usr/bin/env nu
def main [--json] { {ok: true} | to json --raw }
' | save ($consumer | path join bin demo)
^chmod +x ($consumer | path join bin demo)
'use std/assert
use demo *
assert equal (demo).ok true
' | save ($consumer | path join lib demo check.nu)

let checked = try {
    with-env {
        MISE_CONFIG_ROOT: $consumer
        MISE_CONFIG_DIR: ($scratch | path join config)
        MISE_TRUSTED_CONFIG_PATHS: $scratch
        PATH: ($env.PATH | prepend ($consumer | path join bin))
        CI: "true"
    } {
        cd $consumer
        let packed = ^nus ($tasks | path join package.nu) --out $package | complete
        assert equal $packed.exit_code 0 $packed.stderr
        let listed = ^mise tasks ls --json | complete
        assert equal $listed.exit_code 0 $listed.stderr
        let names = $listed.stdout | from json | get name | sort
        assert equal $names [catalog:check catalog:generate catalog:install catalog:spec]
        for task in [catalog:spec catalog:generate catalog:check] {
            let result = ^mise run $task | complete
            assert equal $result.exit_code 0 $"($task): ($result.stdout)($result.stderr)"
        }
        # The clap runner has no internal dependencies beyond the executable tools.
        let clap = ^nus ($package | path join oci catalog .support clap spec.nu) --help | complete
        assert equal $clap.exit_code 0 $clap.stderr
    }
    null
} catch {|err| $err }
rm --recursive $scratch
if $checked != null {
    error make --unspanned {msg: $checked.msg}
}
print "packaged catalog: spec, schema generation and check work outside the repository"
