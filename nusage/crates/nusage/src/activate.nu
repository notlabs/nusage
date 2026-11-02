# nusage's activation for Nushell, as `nus activate nu` prints it. Save it where Nushell
# autoloads, in place of `mise activate nu`:
#
#     nus activate nu | save --force ($nu.user-autoload-dirs | first | path join nus.nu)
#
# The environment mise resolves for the working directory and `MISE_ENV` is the overlay
# `mise`, and the typed commands of the packages that environment names, `NUS_MODULES`, are
# the overlay `nus` above it. Before each prompt a hook asks mise for the environment and,
# when it changed, reloads both, so the line after a `cd` already has them. `overlay list`
# shows them, and `overlay hide` takes one away until the environment next changes. What is
# set at the prompt lands in `nus`, the top overlay, and stays from one directory to the
# next. Only an interactive shell is activated: a script, or `nu --mcp`, keeps the
# environment it started with.

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

# Write the modules of the overlays for the working directory into `dir`, and whether they
# changed: the environment mise resolves from the PATH from before mise, with what it no
# longer sets hidden, and the module `nus modules` writes for the packages it names.
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
    let names = $vars | columns
    [
        "# The environment mise resolves for the working directory, as `nus-overlays` writes it."
        "export-env {"
        ("    for name in ($env.__NUS_MISE? | default [] | where $it not-in " + ($names | to nuon) + ") {")
        "        hide-env --ignore-errors $name"
        "    }"
        ("    load-env " + ($vars | to nuon))
        ("    $env.__NUS_MISE = " + ($names | to nuon))
        "}"
    ]
    | str join "\n"
    | save --force ($dir | path join mise.nu)
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
    $packages | save --force ($dir | path join nus.nu)
    $key | save --force ($dir | path join key)
    true
}

# The hook's code: reload the overlays from the modules in `dir`.
def nus-overlays-code [dir: path]: nothing -> string {
    [
        $"overlay use --reload (($dir | path join mise.nu) | to nuon) as mise"
        $"overlay use --reload (($dir | path join nus.nu) | to nuon) as nus"
    ]
    | str join "; "
}

export-env {
    if $nu.is-interactive {
        nus-revert
        let root = "@root@"
        # A shell's modules are rewritten whenever they are missing, so the directories that
        # have not changed for a week can go, whether their shell has ended or not.
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
