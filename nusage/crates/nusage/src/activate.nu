# nusage's activation for Nushell, as `nus activate nu` prints it. Save it where Nushell
# autoloads, in place of `mise activate nu`:
#
#     nus activate nu | save --force ($nu.user-autoload-dirs | first | path join nus.nu)
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
# mise resolves from. A shell started through mise, by its `nu` wrapper or `mise exec`, has a
# project's environment from the start: mise reverts it, so that what is below the overlays
# is the same whichever directory the shell started in.
def --env nus-revert []: nothing -> nothing {
    $env.__NUS_PATH = ^mise -C / env --json | from json | get PATH | split row (char esep)
    if "__MISE_DIFF" in $env {
        let added = ^mise -C / hook-env -s nu
        | lines
        | where $it starts-with "hide,"
        | each { split row "," | get 1 }
        if ($added | is-not-empty) {
            hide-env --ignore-errors ...$added
        }
        hide-env --ignore-errors __MISE_DIFF __MISE_SESSION
    }
    $env.PATH = $env.__NUS_PATH
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
        # The nus the environment has, as the packages are its; else the one that wrote this.
        let nus = with-env {PATH: ($vars.PATH? | default $env.__NUS_PATH)} { which nus | get path.0? }
        | default "@nus@"
        try {
            with-env $vars { ^$nus modules }
        } catch {|err|
            print --stderr $err.msg
            ""
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

export-env {
    if $nu.is-interactive {
        nus-revert
        let root = "@root@"
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
