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
        mkdir ($scratch | path join catalog tasks) ($scratch | path join producer)
        for file in [entry.tasks.toml catalog.nu support.nu] {
            cp ($here | path join $file) ($scratch | path join catalog tasks $file)
        }
        for name in [spec generate check] {
            let script = '#!' + $nu.current-exe + (char nl) + '#USAGE flag "--probe" help="Fixture flag"' + (char nl) + 'use std/assert
use catalog.nu [entries root]
let selected = entries
assert equal ($selected | length) 1
{entry: $selected.0.name, task: $env.MISE_TASK_NAME, cwd: $env.PWD, catalog: (root)} | to json --raw | $in + (char nl) | save --append $env.GRAPH_LOG
'
            let file = $scratch | path join catalog tasks ($name + ".nu")
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
                        "custom:producer": {root: producer}
                        "custom:alpha": {root: "catalog/lib/alpha", depends_add: [custom:producer]}
                        "custom:beta": {root: "catalog/lib/beta", depends_add: [custom:producer]}
                    }
                }
                settings: {experimental: true}
                env: {
                    NU_LIB_DIRS: ($env.NU_LIB_DIRS | str join (char esep))
                    GRAPH_LOG: ($scratch | path join events)
                }
            } | to toml | save mise.toml
            {tasks: {
                build: {run: 'echo build >> "$GRAPH_LOG.providers"'}
                check: {depends: [":build"], run: 'echo check >> "$GRAPH_LOG.providers"'}
                "check:platform": {depends: [":build"], run: 'echo platform >> "$GRAPH_LOG.providers"'}
            }} | to toml | save producer/mise.toml
            for entry in [alpha beta] {
                let dir = $scratch | path join catalog lib $entry
                mkdir $dir
                {
                    _: {nusage: {catalog: {version: "1.0.0"}}}
                    task_config: {includes: ["../../tasks/entry.tasks.toml"]}
                } | to toml | save ($dir | path join mise.toml)
            }
            for task in [spec generate check "check:platform"] {
                checked mise run --force $"//catalog/lib/alpha:($task)" | ignore
            }
            assert ((checked mise run //catalog/lib/alpha:spec --help) | str contains "--probe")
            cd catalog/lib/beta
            checked mise run --force check | ignore
            cd $scratch
            let events = open --raw events | lines | each {from json}
            assert equal ($events | get entry) [alpha alpha alpha alpha beta]
            for event in $events {
                assert equal $event.cwd ($scratch | path join catalog lib $event.entry)
                assert equal $event.catalog ($scratch | path join catalog)
            }
            assert equal (open --raw events.providers | lines) [build build build check build platform build check]
        }
        null
    } catch {|err| $err}
    rm -rf $scratch
    if $result != null { error make $result }
}
