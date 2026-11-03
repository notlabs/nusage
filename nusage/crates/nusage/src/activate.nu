# nusage's activation for Nushell, as `nus activate nu` prints it, in place of `mise activate
# nu`. Save it beside Nushell's configuration, and use it from `config.nu`:
#
#     nus activate nu | save --force ($nu.default-config-dir | path join nus.nu)
#     use ($nu.default-config-dir | path join nus.nu)    # in config.nu
#
# The file is the same for every nusage and every machine, so it is saved once, or linked: a
# checkout of nusage's repository links it into place with `mise dot apply`, as `mise
# bootstrap` does. Its own commands stay in the module.
#
# The environment mise resolves for the working directory and `MISE_ENV` is an overlay,
# `mise-<n>`, and the typed commands of the packages it names, `NUS_MODULES`, another,
# `nus-<n>`. Before each prompt a hook asks mise for the environment and, when it changed,
# hides the overlays of the last one and uses those of this one, so the line after a `cd` has
# the directory's tools and commands, and leaving takes them away with all they set. Above
# them is `prompt`, where what is set at the prompt lands, so it stays from one directory to
# the next, with `mise shell`. Only an interactive shell is activated: a script, or `nu
# --mcp`, keeps the environment it started with.

# Make this shell's own environment the one from before mise, and keep its PATH as the one
# mise resolves from. A shell can start with mise's environment for its directory already
# set, as mise's `nu` wrapper, `mise exec`, an editor or an activated parent shell starts
# it: what mise sets there, from an empty PATH so that its PATH is only what mise adds, is
# taken out, so that what is below the overlays is the same wherever the shell started.
def --env nus-revert []: nothing -> nothing {
    # The program, not this module's `mise`.
    let mise = which --all mise | where type == external | get path.0?
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

# The overlay above an environment's, where what is set at the prompt lands, so that it stays
# from one environment to the next. It is made at the first prompt and used again at every
# change, keeping what is in it, and it has `mise shell`, which mise's own activation has,
# above the commands of any package of mise's: mise prints the variables for the shell to
# set, and takes a `__MISE_DIFF` as the sign of an activated shell, which is asked of mise's
# hook for that call alone. A variable it takes away is set to null, as `nus-unset` does.
const PROMPT = r##'# What is set at this shell's prompt, and `mise shell`, as `nus-overlays` writes it.
export def --env --wrapped "mise shell" [...args: string] {
    let diff = with-env {MISE_SHELL: nu} { ^mise hook-env -s nu }
    | lines
    | where $it starts-with "set,__MISE_DIFF,"
    | each { str substring ("set,__MISE_DIFF," | str length).. }
    | get -o 0
    | default ""
    let rows = with-env {MISE_SHELL: nu, __MISE_DIFF: $diff} { ^mise shell ...$args }
    | lines
    | where $it != ""
    | each {|line| $line | split row --number 3 "," }
    load-env ($rows | reduce --fold {} {|row, vars|
        $vars | insert $row.1 (if $row.0 == "set" { $row.2? | default "" } else { null })
    })
}

export def --env --wrapped "mise sh" [...args: string] {
    mise shell ...$args
}
'##

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
    # Each change uses the environment's overlays under names they have not had: Nushell does
    # not bring back the commands of an overlay that is used again after it was hidden, unless
    # it was first made before the first prompt. A module's file is named by what it holds, so
    # that one met again is the same file.
    let count = (
        try {
            open --raw ($dir | path join count) | into int
        } catch {
            0
        }
    ) + 1
    $count | into string | save --force ($dir | path join count)
    let modules = [[kind, text]; [mise, $environment] [nus, $packages]]
    | where ($it.text | str trim | is-not-empty)
    | each {|module|
        let file = $dir | path join $"($module.kind)-($module.text | hash sha256 | str substring 0..<8).nu"
        if not ($file | path exists) {
            $module.text | save $file
        }
        {file: $file, name: $"($module.kind)-($count)"}
    }
    let prompt = $dir | path join prompt.nu
    if not ($prompt | path exists) {
        $PROMPT | save $prompt
    }
    let used = overlay list
    | where active and (($it.name starts-with "mise-") or ($it.name starts-with "nus-"))
    | get name
    [
        "# How this shell's overlays change, as `nus-overlays` writes it."
        ...($used | each {|name| $"overlay hide ($name | to nuon)" })
        ...(
            $modules
            | each {|module| $"overlay use ($module.file | to nuon) as ($module.name | to nuon)" }
        )
        $"overlay use ($prompt | to nuon)"
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
