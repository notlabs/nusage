#!/usr/bin/env nu
# Check mise's raw JSON against the reviewed output schemas. The catalog's `check` runs this;
# `--bin` names a candidate mise binary, the one on PATH otherwise. A plain Nushell script: to
# the nus interpreter, the package's `mod.nu` beside it would read as the root of a tree.
use ../../schemas/lib.nu [load-suite check-examples run-suite finish]

const here = path self | path dirname

def main [--bin: string] {
    let suite = load-suite ($here | path join schemas outputs.nuon)

    let binary = if $bin != null {
        $bin | path expand
    } else {
        which mise | first | get path
    }

    # The schemas themselves, then the documents they must accept or reject: the shapes a
    # fixture cannot produce, such as an empty listing's rows.
    finish (check-examples $suite (open ($here | path join schemas examples.nuon)))

    let scratch = mktemp -d

    let result = try {
        cp -r ($here | path join schema-fixtures project) $scratch
        cp -r ($here | path join schema-fixtures data) $scratch
        for dir in [config cache state system] { mkdir ($scratch | path join $dir) }
        let project = $scratch | path join project
        # A fresh release-index cache makes version --json deterministic and network-free.
        "2026.10.21 0\n" | save ($scratch | path join cache latest-version.releases-v1)
        # Keep user settings such as MISE_ENV and MISE_*_VERSION out of this fixture.
        let inherited = $env | columns | where {|name| $name | str starts-with "MISE_" }
        hide-env --ignore-errors ...$inherited
        with-env {
            MISE_CONFIG_DIR: ($scratch | path join config)
            MISE_GLOBAL_CONFIG_FILE: ($scratch | path join config config.toml)
            MISE_SYSTEM_CONFIG_DIR: ($scratch | path join system)
            MISE_DATA_DIR: ($scratch | path join data)
            MISE_CACHE_DIR: ($scratch | path join cache)
            MISE_STATE_DIR: ($scratch | path join state)
            MISE_TRUSTED_CONFIG_PATHS: $project
            MISE_YES: "1"
            MISE_COLOR: "0"
            MISE_EXPERIMENTAL: "true"
            MISE_USE_VERSIONS_HOST: "false"
        } {
            # Register only the local fixture plugin; no remote plugin or tool is installed.
            let plugin = do {
                cd $project
                ^$binary plugins install schema-fixture | complete
            }
            if $plugin.exit_code != 0 {
                error make --unspanned {msg: $"Fixture plugin setup failed: ($plugin.stderr)"}
            }
            run-suite $suite $binary $project
        }
    } catch {|err|
        rm -r $scratch
        error make --unspanned {msg: $err.msg}
    }
    rm -r $scratch
    finish $result
}
