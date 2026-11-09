#!/usr/bin/env nus
#MISE description="Run the packaged tasks from an unrelated consumer project"
#MISE sources=["mise-tasks/**/*.nu", "lib/**/*.nu", "packages/**/*", "../target/install/bin/nus"]
#MISE outputs=[]
use std/assert
use ../packages/mise *

const tasks = path self | path dirname

# A consumer owns its entries and schemas; the package must supply everything else.
let scratch = mktemp --directory | path expand
let consumer = $scratch | path join consumer
let alias = $scratch | path join consumer-link
let package = $alias | path join dist
mkdir ($consumer | path join packages demo schemas) ($consumer | path join bin)
# Exercise output through a symlink, including macOS temporary-directory aliases.
^ln -s $consumer $alias
let config = $consumer | path join mise.toml
{
    monorepo_root: true
    monorepo: {
        config_roots: ["[!.]*", "[!.]*/[!.]*", "[!.]*/[!.]*/[!.]*"]
    }
    task_config: {
        includes: [
            ($package | path join oci)
        ]
    }
    vars: {catalog_version: "0.0.0"}
    env: {
        _: {
            path: (
                # The program itself, not a shim or command wrapper that links to another,
                # such as mise's: a `nu` wrapper, which a project's `[wrappers.nu]` makes, is
                # first on PATH everywhere.
                [nus nu usage]
                | each {|tool|
                    which --all $tool
                    | where type == external
                    | where {|found| ($found.path | path expand | path parse | get stem) == $tool }
                    | first
                    | get path
                    | path dirname
                }
                | uniq
            )
        }
    }
} | to toml | save $config
{
    _: {
        nusage: {
            catalog: {
                spec: {
                    run: "open --raw packages/demo/source.kdl | print --no-newline"
                }
            }
        }
    }
    tasks: {
        check: {run: "true"}
    }
} | to toml | save ($consumer | path join packages demo mise.toml)
'name "demo"
bin "demo"
' | save ($consumer | path join packages demo source.kdl)
"# generated below\n" | save ($consumer | path join packages demo mod.nu)
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
} | to nuon | save ($consumer | path join packages demo schemas outputs.nuon)
{
    type: object
    properties: {
        ok: {type: boolean}
    }
    required: [ok]
    additionalProperties: false
} | to json | save ($consumer | path join packages demo schemas result.schema.json)
'#!/usr/bin/env nu
def main [--json] { {ok: true} | to json --raw }
' | save ($consumer | path join bin demo)
^chmod +x ($consumer | path join bin demo)
'use std/assert
use demo *
assert equal (demo).ok true
' | save ($consumer | path join packages demo check.nu)

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
        # Packaged tasks must use the bundled library, without this repository's module map.
        $env.NUS_MODULES = "{}"
        $env.NUS_TOOLS = "{}"
        let names = mise tasks ls | get name | where $it != "//packages/demo:check" | each { str replace --regex "^//:" "" } | sort
        assert equal $names [catalog:check catalog:generate catalog:spec]
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
