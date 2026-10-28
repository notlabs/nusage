#!/usr/bin/env nusage
#USAGE about "Check mise's raw JSON against the reviewed output schemas"
#USAGE flag "--bin <path>" help="Candidate mise binary; defaults to the one on PATH"
use ../schemas/lib.nu [load-suite run-suite finish]

const here = path self | path dirname

let suite = load-suite ($here | path join schemas outputs.nuon)

let binary = if $usage.flags.bin != null {
    $usage.flags.bin | path expand
} else {
    which mise | first | get path
}

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
    } {
        run-suite $suite $binary $project
    }
} catch {|err|
    rm -r $scratch
    error make --unspanned {msg: $err.msg}
}
rm -r $scratch
finish $result
