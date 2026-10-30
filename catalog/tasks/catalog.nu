# The catalog's entries and the files of each, shared by the tasks.
#
# An entry is a table under `[_.nusage.catalog]` in the mise config of the directory the
# tasks run in, their config root. mise ignores the `_` table and `mise config get` prints
# it as TOML:
#
#   [_.nusage.catalog.mise]
#   spec = { run = "mise usage" }                   # a command line that prints the tool's spec
#   switch = { flag = "--json", framing = "json" }  # the switch that selects structured output
#
#   [_.nusage.catalog.jj]
#   spec = { clap = "spec" }                        # an extractor `../clap/spec.nu` builds and runs
#
# `spec` names one way to obtain the spec: `run` for a tool that prints its own, `clap` for a
# binary whose crate builds its clap command, the directory of the extractor under the package.
# `check` asks whether the committed spec is the tool's on PATH with a `probe`: `export` runs
# `run` again and compares, the default for a `run` entry whose export is cheap; `version`
# compares the spec's own `version` to `<bin> --version`, the default for `clap`, and the
# choice for a `run` whose export builds something, `probe = "version"`.
#
# The entry's package is `lib/<tool>/`, a Nushell module directory: with `lib` on
# `$NU_LIB_DIRS`, `use <tool> *` names the commands as the tool does. It holds
#
#   <tool>.usage.kdl    the spec, as obtained; `spec` refreshes it
#   <tool>.select.kdl   the overlay declaring the output `switch` selects; generated
#   <tool>.schemas.kdl  the overlay `../schemas/overlay.nu` writes from `schemas/outputs.nuon`,
#                       declaring each output with its schema; generated when the suite exists
#   *.overlay.kdl       hand-written overlays, merged in name order: types, outputs, decoders
#   mod.nu              the module; generated
#   schemas/            the output-schema suite, its schemas, manifest and examples
#   check-schemas.nu    holds the tool's raw output to the suite; `check` runs it
#   check.nu            drives the tool through the module; `check` runs it with `lib` included
#   spec/               a clap extractor, for an entry whose `spec` is `clap`
#   nupm.nuon           the package's manifest, as nupm and numan read it

# The directory the packages are under: the config root mise runs the task in.
export def root []: nothing -> string {
    $env.MISE_CONFIG_ROOT? | default $env.PWD
}

# Every entry as a row with its tool's name, or the one named.
export def entries [tool?: string]: nothing -> table {
    let got = ^mise config get _.nusage.catalog | complete
    if $got.exit_code != 0 {
        error make --unspanned {
            msg: $"no `[_.nusage.catalog]` entries in the mise config of (root): ($got.stderr | str trim)"
        }
    }
    let all = $got.stdout | from toml | transpose name entry | each {|row| {name: $row.name} | merge $row.entry }
    if $tool == null {
        return $all
    }
    let found = $all | where name == $tool
    if ($found | is-empty) {
        error make --unspanned {
            msg: $"no entry `($tool)` under `[_.nusage.catalog]`; the entries are ($all | get name | str join ', ')"
        }
    }
    $found
}

# The package's files: where `generate` writes and `check` reads.
export def files [tool: string]: nothing -> record {
    let dir = root | path join lib $tool
    {
        dir: $dir
        spec: ($dir | path join $"($tool).usage.kdl")
        select: ($dir | path join $"($tool).select.kdl")
        schemas_overlay: ($dir | path join $"($tool).schemas.kdl")
        schemas: ($dir | path join schemas outputs.nuon)
        overlays: (glob ($dir | path join '*.overlay.kdl') | sort)
        module: ($dir | path join mod.nu)
        check: ($dir | path join check.nu)
        check_schemas: ($dir | path join check-schemas.nu)
    }
}

# How the entry's spec is obtained: `run` or `clap`.
export def spec-kind [entry: record]: nothing -> string {
    let spec = $entry.spec? | default {}
    let kinds = [run clap] | where {|kind| $kind in ($spec | columns) }
    if ($kinds | length) != 1 {
        error make --unspanned {
            msg: $"entry `($entry.name)`: `spec` names one way to obtain the spec, `run` or `clap`; it has ($kinds | str join ', ')"
        }
    }
    $kinds.0
}

# How `check` asks whether the committed spec is current: `export` or `version`.
export def spec-probe [entry: record]: nothing -> string {
    let probe = $entry.spec.probe? | default (if (spec-kind $entry) == clap { "version" } else { "export" })
    if $probe not-in [export version] {
        error make --unspanned {
            msg: $"entry `($entry.name)`: `spec.probe` is `export` or `version`, not `($probe)`"
        }
    }
    $probe
}

# What the committed spec says of itself: its `bin`, and the `version` it describes, when it
# declares one.
export def spec-identity [files: record]: nothing -> record {
    let lines = open --raw $files.spec | lines
    let bin = $lines | parse --regex '^bin\s+"?(?<bin>[^"\s]+)"?\s*$' | get 0?.bin?
    let version = $lines | parse --regex '^version\s+"?(?<version>[^"\s]+)"?\s*$' | get 0?.version?
    {bin: $bin, version: $version}
}

# The spec as a `run` entry's tool prints it now.
export def export-spec [entry: record]: nothing -> string {
    let run = $entry.spec.run
    let got = ^nu -c $run | complete
    if $got.exit_code != 0 {
        error make --unspanned {
            msg: $"entry `($entry.name)`: `($run)` failed: ($got.stderr | str trim)"
        }
    }
    $got.stdout
}

# A `clap` entry's extractor: its directory, and the binary and crate its manifest names.
export def extractor [entry: record]: nothing -> record {
    let dir = root | path join lib $entry.name $entry.spec.clap
    let manifest = $dir | path join Cargo.toml
    if not ($manifest | path exists) {
        error make --unspanned {
            msg: $"entry `($entry.name)`: no extractor at ($manifest | path relative-to (root))"
        }
    }
    let target = open $manifest | get package.metadata.clap-spec
    {dir: $dir, bin: $target.bin, crate: $target.crate}
}

# Generate the entry's overlays and module from its spec, suite and overlays, into its package,
# or into `into`, where the spec is copied first so that the module's relative path to it is
# the one the package has. Returns the files generated, and every overlay the module took.
export def generate [entry: record, --into: string]: nothing -> record {
    let files = files $entry.name
    if not ($files.spec | path exists) {
        error make --unspanned {
            msg: $"entry `($entry.name)`: no spec at ($files.spec | path relative-to (root)); `mise run spec ($entry.name)` obtains it"
        }
    }
    let out = $into | default $files.dir
    mkdir $out
    let spec = $out | path join ($files.spec | path basename)
    if $spec != $files.spec {
        cp $files.spec $spec
    }
    let module = $out | path join mod.nu
    mut generated = []
    let switch = $entry.switch?
    if $switch != null {
        let select = $out | path join ($files.select | path basename)
        ^nusage overlay $spec $"--switch=($switch.flag)" --framing $switch.framing | save --force $select
        $generated = $generated | append $select
    }
    if ($files.schemas | path exists) {
        let schemas = $out | path join ($files.schemas_overlay | path basename)
        ^nusage (root | path join schemas overlay.nu) $files.schemas | save --force $schemas
        $generated = $generated | append $schemas
    }
    let overlays = $generated ++ $files.overlays
    ^nusage generate $spec ...($overlays | each {|overlay| ["--overlay" $overlay] } | flatten) --out $module
    {generated: $generated, module: $module, overlays: $overlays}
}
