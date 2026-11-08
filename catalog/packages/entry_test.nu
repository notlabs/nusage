use std/assert
use std/testing *

const here = path self | path dirname

def --wrapped checked [...args: string] {
    let result = run-external ...$args | complete
    assert equal $result.exit_code 0 ($result.stderr + $result.stdout)
    $result.stdout | str trim
}

@test
def "included entry tasks retain local context Usage and upstream checks" [] {
    let scratch = mktemp -d | path expand
    let result = try {
        mkdir ($scratch | path join catalog packages) ($scratch | path join catalog lib) ($scratch | path join catalog mise-tasks) ($scratch | path join producer)
        cp ($here | path join package.tasks.toml) ($scratch | path join catalog packages package.tasks.toml)
        for file in [catalog.nu support.nu] {
            cp ($here | path join ../lib $file) ($scratch | path join catalog lib $file)
        }
        mkdir ($scratch | path join catalog packages mise)
        cp ($here | path join mise mod.nu) ($scratch | path join catalog packages mise mod.nu)
        for name in [spec generate check] {
            let script = '#!' + $nu.current-exe + (char nl) + '#USAGE flag "--probe" help="Fixture flag"' + (char nl) + 'use std/assert
use ../lib/catalog.nu [entries root]
let selected = entries
assert equal ($selected | length) 1
{entry: $selected.0.name, task: $env.MISE_TASK_NAME, cwd: $env.PWD, catalog: (root)} | to json --raw | $in + (char nl) | save --append $env.GRAPH_LOG
'
            let file = $scratch | path join catalog mise-tasks ($name + ".nu")
            $script | save $file
            checked chmod +x $file | ignore
        }
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
                monorepo: {
                    config_roots: ["[!.]*" "[!.]*/[!.]*" "[!.]*/[!.]*/[!.]*"]
                    projects: {
                        "gen:producer": {root: producer}
                        "catalog:alpha": {root: "catalog/packages/alpha", depends_add: [gen:producer]}
                        "catalog:beta": {root: "catalog/packages/beta", depends_add: [gen:producer]}
                    }
                }
                settings: {experimental: true}
                env: {
                    GRAPH_LOG: ($scratch | path join events)
                }
                # The entry checks hold their graph to the one on disk through the root's guard.
                tasks: {graph-current: {run: "true"}}
            } | to toml | save mise.toml
            {tasks: {
                build: {run: 'echo build >> "$GRAPH_LOG.providers"'}
                check: {depends: [":build"], run: 'echo check >> "$GRAPH_LOG.providers"'}
                "check:platform": {depends: [":build"], run: 'echo platform >> "$GRAPH_LOG.providers"'}
            }} | to toml | save producer/mise.toml
            for entry in [alpha beta] {
                let dir = $scratch | path join catalog packages $entry
                mkdir $dir
                {
                    _: {nusage: {catalog: {version: "1.0.0"}}}
                    task_config: {includes: ["../package.tasks.toml"]}
                } | to toml | save ($dir | path join mise.toml)
            }
            for task in [spec generate check "check:platform"] {
                checked mise run --force $"//catalog/packages/alpha:($task)" | ignore
            }
            assert ((checked mise run //catalog/packages/alpha:spec --help) | str contains "--probe")
            cd catalog/packages/beta
            checked mise run --force check | ignore
            cd $scratch
            let events = open --raw events | lines | each {from json}
            assert equal ($events | get entry) [alpha alpha alpha alpha beta]
            for event in $events {
                assert equal $event.cwd ($scratch | path join catalog packages $event.entry)
                assert equal $event.catalog ($scratch | path join catalog)
            }
            # Only the checks run upstream tasks: the entry's own spec and generate need none.
            assert equal (open --raw events.providers | lines) [build check build platform build check]
        }
        null
    } catch {|err| $err}
    rm -rf $scratch
    if $result != null { error make $result }
}
