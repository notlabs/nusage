# nusage's activation for Nushell, as `nus activate nu` prints it, in place of `mise activate
# nu`. Save it beside Nushell's configuration, and use it from `config.nu`:
#
#     nus activate nu | save --force ($nu.default-config-dir | path join nus.nu)
#     use ($nu.default-config-dir | path join nus.nu) *    # in config.nu
#
# The file is the same for every nusage and every machine, so it is saved once, or linked: a
# checkout of nusage's repository links it into place with `mise dot apply`, as `mise
# bootstrap` does. The `*` brings in `mise`, for `mise shell`; the rest stays in the module.
#
# The environment mise resolves for the working directory and `MISE_ENV` is an overlay,
# `mise-<digest>`, and the typed commands of the packages it names, `NUS_MODULES`, another,
# `nus-<digest>`, each named by what it holds. Before each prompt a hook asks mise for the
# environment and, when it changed, hides the overlays of the last one and uses those of this
# one, so the line after a `cd` has the directory's tools and commands, and leaving takes
# them away with all they set. An environment met again has its overlays back as they were.
# Above them is `prompt`, where what is set at the prompt lands, so it stays from one
# directory to the next. Only an interactive shell is activated: a script, or `nu --mcp`,
# keeps the environment it started with.

# Make this shell's own environment the one from before mise, and keep its PATH as the one
# mise resolves from. A shell can start with mise's environment for its directory already
# set, as mise's `nu` wrapper, `mise exec`, an editor or an activated parent shell starts
# it: what mise sets there, from an empty PATH so that its PATH is only what mise adds, is
# taken out, so that what is below the overlays is the same wherever the shell started.
def --env nus-revert []: nothing -> nothing {
    let mise = which mise | get path.0?
    if $mise != null {
        let here = try {
            do {
                hide-env --ignore-errors __MISE_DIFF __MISE_SESSION
                $env.PATH = []
                ^$mise env --json
            }
            | from json
        } catch {
            {}
        }
        let added = $here.PATH? | default "" | split row (char esep) | where $it != ""
        # PATH is a list once Nushell's configuration has converted it, a string before.
        $env.PATH = $env.PATH
        | if ($in | describe) == "string" { split row (char esep) } else { $in }
        | where $it not-in $added
        let set = $here
        | items {|name, value| if $name != "PATH" and ($env | get -o $name) == $value { $name } }
        | compact
        nus-unset ...$set
    }
    nus-unset __MISE_DIFF __MISE_SESSION
    $env.__NUS_PATH = $env.PATH
}

# Take variables out of this shell's own environment, below the overlays, by setting them to
# null: Nushell passes no null to the programs it runs, and reads it as no value. Hiding them
# would not last, as Nushell brings back what is hidden below an overlay when the overlay is
# hidden, and the overlays change with every environment.
def --env nus-unset [...names: string]: nothing -> nothing {
    load-env ($names | reduce --fold {} {|name, vars| $vars | insert $name null })
}

# Write what changes this shell's overlays into `dir`, and whether the environment changed:
# the module of the environment mise resolves from the PATH from before mise, the module
# `nus modules` writes for the packages it names, each named by what it holds, and
# `switch.nu`, which hides the overlays in use and uses these.
def nus-overlays [dir: path]: nothing -> bool {
    mkdir $dir
    let found = with-env {PATH: $env.__NUS_PATH} { ^mise env --json | complete }
    if $found.exit_code != 0 {
        # Said once for each cause, not at every prompt.
        let why = $found.stderr | str trim
        if (try { open --raw ($dir | path join why) } catch { "" }) != $why {
            $why | save --force ($dir | path join why)
            print --stderr $why
        }
        return false
    }
    rm --force ($dir | path join why)
    let key = $found.stdout | hash sha256
    if (try { open --raw ($dir | path join key) } catch { "" }) == $key {
        return false
    }
    let vars = $found.stdout
    | from json
    | if "PATH" in $in { update PATH {|vars| $vars.PATH | split row (char esep) } } else { $in }
    let environment = [
        "# An environment mise resolves, as `nus-overlays` writes it."
        ("export-env { load-env " + ($vars | to nuon) + " }")
    ]
    | str join "\n"
    let packages = if "NUS_MODULES" in $vars {
        # The nus the environment has, as the packages are its; else the one outside it.
        let nus = with-env {PATH: ($vars.PATH? | default [] | append $env.__NUS_PATH)} {
            which nus | get path.0?
        }
        if $nus == null {
            print --stderr "nus: the environment names packages, and nus is not on its PATH"
            ""
        } else {
            try {
                with-env $vars { ^$nus modules }
            } catch {|err|
                print --stderr $err.msg
                ""
            }
        }
    } else {
        ""
    }
    # A module's file is named by what it holds, and so is the overlay `overlay use` makes of
    # it: one met again is the same overlay.
    let named = {|kind: string, text: string|
        let file = $dir | path join $"($kind)-($text | hash sha256 | str substring 0..<8).nu"
        if not ($file | path exists) {
            $text | save $file
        }
        $file
    }
    let modules = [(do $named mise $environment)]
    | append (if ($packages | str trim | is-empty) { [] } else { [(do $named nus $packages)] })
    let prompt = $dir | path join prompt.nu
    if not ($prompt | path exists) {
        "" | save $prompt
    }
    let used = overlay list
    | where active and (($it.name starts-with "mise-") or ($it.name starts-with "nus-"))
    | get name
    [
        "# How this shell's overlays change, as `nus-overlays` writes it."
        ...($used | each {|name| $"overlay hide ($name | to nuon)" })
        ...($modules | append $prompt | each {|file| $"overlay use ($file | to nuon)" })
    ]
    | str join "\n"
    | save --force ($dir | path join switch.nu)
    $key | save --force ($dir | path join key)
    true
}

# The hook's code: change the overlays as `nus-overlays` wrote into `dir`.
def nus-overlays-code [dir: path]: nothing -> string {
    $"source (($dir | path join switch.nu) | to nuon)"
}

# `mise`, as mise's own activation has it, so that `mise shell` sets a tool's version in this
# shell, which the next prompt's environment then has. mise prints the variables for the
# shell to set, and takes a `__MISE_DIFF` as the sign of an activated shell: the one its hook
# would have set is asked of it, for that call alone. Any other command is mise's as it is.
export def --env --wrapped mise [...args: string] {
    if ($args | get 0? | default "") in [shell sh] {
        let diff = with-env {MISE_SHELL: nu} { ^mise hook-env -s nu }
        | lines
        | where $it starts-with "set,__MISE_DIFF,"
        | each { str substring ("set,__MISE_DIFF," | str length).. }
        | last
        | default ""
        let rows = with-env {MISE_SHELL: nu, __MISE_DIFF: $diff} { ^mise ...$args }
        | from csv --noheaders --no-infer
        | rename op name value
        load-env ($rows | where op == set | reduce --fold {} {|row, vars| $vars | insert $row.name $row.value })
        nus-unset ...($rows | where op == hide | get name)
    } else {
        ^mise ...$args
    }
}

export-env {
    # `nu --mcp` and `nu --lsp` count as interactive too, and have no prompt.
    let served = ($nu.is-mcp? | default false) or ($nu.is-lsp? | default false)
    if $nu.is-interactive and not $served {
        nus-revert
        # Beside Nushell's own cache, as nus keeps its.
        let root = $nu.cache-dir | path dirname | path join nusage activate
        # A shell's files are written again whenever its environment changes, so the
        # directories that have not changed for a week can go, whether their shell has ended
        # or not.
        let old = try { ls $root } catch { [] }
        | where type == dir and modified < ((date now) - 7day)
        | get name
        for dir in $old {
            rm --recursive --force $dir
        }
        let dir = $root | path join ($nu.pid | into string)
        $env.config.hooks.pre_prompt = (
            $env.config.hooks.pre_prompt?
            | default []
            | append {condition: {|| nus-overlays $dir }, code: (nus-overlays-code $dir)}
        )
    }
}
