# The catalog's entries and the files of each, shared by the tasks.
#
# An entry is a table under `[_.nusage.catalog]` in the mise config of the directory the
# tasks run in, their config root. mise ignores the `_` table and `mise config get` prints
# it as TOML:
#
#   [_.nusage.catalog.mise]
#   spec = { run = "mise usage" }                   # what prints the tool's usage spec
#   switch = { flag = "--json", framing = "json" }  # the switch that selects structured output
#
# The entry's package is `lib/<tool>/`, a Nushell module directory: with `lib` on
# `$NU_LIB_DIRS`, `use <tool> *` names the commands as the tool does. It holds
#
#   <tool>.usage.kdl   the spec as `spec.run` printed it; `spec` refreshes it
#   <tool>.select.kdl  the overlay declaring the output `switch` selects; generated
#   *.overlay.kdl      hand-written overlays, merged in name order: types, outputs
#   mod.nu             the module; generated
#   check.nu           drives the tool through the module; `check` runs it with `lib` included
#   nupm.nuon          the package's manifest, as nupm and numan read it

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
        overlays: (glob ($dir | path join '*.overlay.kdl') | sort)
        module: ($dir | path join mod.nu)
        check: ($dir | path join check.nu)
    }
}

# The spec as the tool prints it now, through the entry's `spec.run`.
export def export-spec [entry: record]: nothing -> string {
    let run = $entry.spec?.run?
    if $run == null {
        error make --unspanned {
            msg: $"entry `($entry.name)`: `spec.run` is the one way to obtain a spec so far"
        }
    }
    let got = ^nu -c $run | complete
    if $got.exit_code != 0 {
        error make --unspanned {
            msg: $"entry `($entry.name)`: `($run)` failed: ($got.stderr | str trim)"
        }
    }
    $got.stdout
}

# Generate the entry's select overlay and module from its spec and overlays, into its package,
# or into `into`, where the spec is copied first so that the module's relative path to it is
# the one the package has. Returns the files written.
export def generate [entry: record, --into: path]: nothing -> record {
    let files = files $entry.name
    if not ($files.spec | path exists) {
        error make --unspanned {
            msg: $"entry `($entry.name)`: no spec at ($files.spec | path relative-to (root)); `mise run spec ($entry.name)` exports it"
        }
    }
    let out = $into | default $files.dir
    mkdir $out
    let spec = $out | path join ($files.spec | path basename)
    if $spec != $files.spec {
        cp $files.spec $spec
    }
    let select = $out | path join ($files.select | path basename)
    let module = $out | path join mod.nu
    let switch = $entry.switch?
    let generated = if $switch == null {
        []
    } else {
        ^nusage overlay $spec $"--switch=($switch.flag)" --framing $switch.framing | save --force $select
        [$select]
    }
    let overlays = $generated ++ $files.overlays
    ^nusage generate $spec ...($overlays | each {|overlay| ["--overlay" $overlay] } | flatten) --out $module
    {select: $generated, module: $module, overlays: $overlays}
}
