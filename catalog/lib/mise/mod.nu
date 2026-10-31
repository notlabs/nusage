alias "attr usage" = echo

# A value as an argv word: a datetime in ISO 8601, anything else as Nushell writes it.
def "nus word" []: any -> string {
    if ($in | describe --detailed | get type) == datetime {
        $in | format date "%+"
    } else {
        $in | into string
    }
}

# The argv for a wrapper's parameters: positionals in order, absent ones dropped, each
# preceded by the clause-scoped flags, then the other flags. A flag goes by its value: a
# switch once when on, a count that many times, a list once per item with its value, any
# other value once with its value; null and false add nothing.
def "nus argv" [positionals: list<any>, flags: record, scoped: record = {}]: nothing -> list<string> {
    let scoped = $scoped | nus flag-words
    let words = $positionals | compact | each { nus word }
    let instances = if ($words | is-empty) {
        $scoped
    } else {
        $words | each {|word| $scoped ++ [$word] } | flatten
    }
    $instances ++ ($flags | nus flag-words)
}

def "nus flag-words" []: record -> list<string> {
    $in | transpose name value | each {|flag|
        match ($flag.value | describe --detailed | get type) {
            bool => (if $flag.value { [$flag.name] } else { [] })
            int => (0..<$flag.value | each { $flag.name })
            list => ($flag.value | each {|value| [$flag.name ($value | nus word)] } | flatten)
            nothing => []
            _ => [$flag.name ($flag.value | nus word)]
        }
    } | flatten
}

# Completions from usage's own completer, against the spec this module was generated
# from, with the words typed so far. Nothing when the `usage` CLI is not installed.
def "nus complete" [place: record] {
    const spec = (path self | path dirname | path join "mise.usage.kdl")
    if (which usage | is-empty) {
        return []
    }
    let name = $place.command | first
    let command = if $name == "main" { [mise] } else { $name | split row " " }
    let words = $place.command | skip 1
    (^usage complete-word -f $spec --shell nu -- ...$command ...$words | complete).stdout
    | lines
    | each {|line| $line | split column "	" value description | into record }
}

# A binary's output decoded as the module's closure decodes it. When that fails and the
# `nus` this module was generated with is on PATH, the output is held to the schema the
# spec declares, line by line with `--lines`, so the error names what does not match it
# rather than what failed to convert; what failed to convert follows, as the inner error.
# The error is the decoding's own when the output matches or there is no `nus` to ask,
# and the inner one under why the output could not be held to its schema when the check
# did not run.
def "nus decoded" [
    text: string
    schema: string
    decode: closure
    --lines
]: nothing -> any {
    try {
        $text | do $decode
    } catch {|err|
        if (which nusage | is-empty) {
            error make $err
        }
        let file = mktemp --tmpdir nusage-XXXXXX.schema.json
        $schema | save --force $file
        let flags = if $lines { [--lines] } else { [] }
        let checked = $text | ^nus validate $file - ...$flags | complete
        rm $file
        match $checked.exit_code {
            0 => { error make $err }
            1 => {
                $err | error make --unspanned {
                    msg: $"the output does not match its schema\n($checked.stderr | str trim)"
                }
            }
            _ => {
                $err | error make --unspanned {
                    msg: $"the output could not be held to its schema: nus validate exited ($checked.exit_code)\n($checked.stderr | str trim)"
                }
            }
        }
    }
}

# Dev tools, env vars, and tasks in one CLI
#
# mise installs the development tools your projects need, sets their environment variables, and runs their tasks.
#
# You declare tools, environment variables, and tasks in mise.toml. `mise use <TOOL>` installs a tool and adds it to the project's mise.toml, `mise install` installs everything the config requests, and `mise run <TASK>` runs a task. Docs: https://mise.jdx.dev
@usage 'min_usage_version "6.11"'
@usage 'author "Jeff Dickey <@jdx>"'
@usage r#'source_code_link_template #"""
{%- set path = path | replace(from='-', to='_') -%}
{%- if path == "bootstrap/dotfiles" or path is starting_with(pat="bootstrap/dotfiles/") -%}
{%- set path = path | replace(from="bootstrap/dotfiles", to="dotfiles") -%}
{%- endif -%}
{%- if path == "daemons/providers" or path is starting_with(pat="daemons/providers/") -%}
{%- set path = "daemons/providers.rs" -%}
{%- elif path == "daemons" or path is starting_with(pat="daemons/") -%}
{%- set path = "cli/daemons.rs" -%}
{%- elif path == "dotfiles/history" -%}
{%- set path = "cli/dotfiles/history/mod.rs" -%}
{%- elif path == "dotfiles/include" -%}
{%- set path = "cli/dotfiles/exclude.rs" -%}
{%- elif path == "dotfiles/origin" or path == "dotfiles/origin/set" -%}
{%- set path = "cli/dotfiles/origin.rs" -%}
{%- elif path == "bootstrap/packages/apply" -%}
{%- set path = "cli/system/install.rs" -%}
{%- elif path == "bootstrap/packages/export" -%}
{%- set path = "cli/system/export.rs" -%}
{%- elif path == "bootstrap/packages/import" -%}
{%- set path = "cli/system/import.rs" -%}
{%- elif path == "bootstrap/packages/prune" -%}
{%- set path = "cli/system/prune.rs" -%}
{%- elif path == "bootstrap/packages/status" -%}
{%- set path = "cli/system/status.rs" -%}
{%- elif path == "bootstrap/packages/upgrade" -%}
{%- set path = "cli/system/upgrade.rs" -%}
{%- elif path == "bootstrap/packages/use" -%}
{%- set path = "cli/system/use.rs" -%}
{%- elif path == "bootstrap/packages/where" -%}
{%- set path = "cli/system/where.rs" -%}
{%- elif path == "bootstrap/packages/brew/tap" -%}
{%- set path = "cli/system/brew/tap.rs" -%}
{%- elif path == "bootstrap/packages/brew/untap" -%}
{%- set path = "cli/system/brew/untap.rs" -%}
{%- elif path == "bootstrap/packages/brew" -%}
{%- set path = "cli/system/brew/mod.rs" -%}
{%- elif path is starting_with(pat="bootstrap") -%}
{%- set path = "cli/bootstrap.rs" -%}
{%- elif path == "tasks/run" -%}
{%- set path = "cli/run.rs" -%}
{%- elif cmd.subcommands | length > 0 -%}
{%- set parts = path | split(pat="/") -%}
{%- set path = "cli/" ~ parts[0] ~ "/mod.rs" -%}
{%- else -%}
{%- set path = "cli/" ~ path ~ ".rs" -%}
{%- endif -%}
https://github.com/jdx/mise/blob/main/src/{{path}}
"""#'#
@usage 'logo #"""
  ▄▄  ▄▄▄  ▄▄
 ▟  ▙▟   ▙▟  ▙
 ▜▄▄▄▄▄▄▄▄▄▄▄▛
  ▀▀▀▀▀▀▀▀▀▀▀
   ▗▄▄▄▄▄▄▄▖
   ▌ ▀   ▔ ▐
   ▝▄ ▀▄▀ ▄▘

"""# style=green'
@usage 'unknown_flags error'
@usage 'default_subcommand run'
@usage 'flag "-c --continue-on-error" help="Continue running tasks even if one fails" hide=#true'
@usage 'flag "-C --cd" help="Run as if mise were started in DIR" global=#true {
    arg <DIR>
}'
@usage 'flag "-E --env" help="Load the `mise.<ENV>.toml` config files (same as MISE_ENV)" var=#true global=#true {
    long_help #"""
Load the `mise.<ENV>.toml` config files (same as MISE_ENV)

Repeat the flag or separate names with commas to load several environments.
"""#
    arg <ENV>
}'
@usage 'flag "-f --force" help="Force the operation" hide=#true'
@usage 'flag "-j --jobs" help="How many jobs to run in parallel; defaults to the `jobs` setting" global=#true env=MISE_JOBS {
    long_help #"""
How many jobs to run in parallel; defaults to the `jobs` setting

Values below 1 are treated as 1.
"""#
    arg <JOBS>
}'
@usage r#'flag "-n --dry-run" help="Dry run, don't actually do anything" hide=#true'#
@usage 'flag "-P --profile" help="Set the profile (environment)" var=#true hide=#true global=#true conflicts=--env {
    arg <PROFILE>
}'
@usage 'flag "-q --quiet" help="Suppress non-error messages" global=#true env=MISE_QUIET {
    overrides "--silent" "--trace" "--verbose" "--debug" "--log-level"
}'
@usage 'flag "-s --shell" hide=#true {
    arg <SHELL>
}'
@usage 'flag "-t --tool" help="Tools to load in addition to those in mise.toml, such as `node@24 python@3.13`" var=#true hide=#true {
    arg <TOOL@VERSION>
}'
@usage 'flag "-v --verbose" help="Show extra output (use -vv for even more)" var=#true global=#true count=#true {
    overrides "--quiet" "--silent" "--trace" "--debug"
}'
@usage 'flag "-V --version" hide=#true'
@usage 'flag "-y --yes" help="Answer yes to all confirmation prompts" global=#true'
@usage 'flag --debug help="Set the log level to debug" hide=#true global=#true {
    overrides "--quiet" "--trace" "--verbose" "--silent" "--log-level"
}'
@usage 'flag --log-level hide=#true global=#true {
    overrides "--quiet" "--trace" "--verbose" "--silent" "--debug"
    arg <LEVEL> {
        choices {
            choice trace
            choice debug
            choice info
            choice warn {
                alias warning hide=#true
            }
            choice error
        }
    }
}'
@usage 'flag --no-config help="Do not load any config files" {
    long_help #"""
Do not load any config files

Same as `MISE_NO_CONFIG=1`.
"""#
}'
@usage 'flag --no-env help="Do not load environment variables from config files" {
    long_help #"""
Do not load environment variables from config files

Same as `MISE_NO_ENV=1`.
"""#
}'
@usage 'flag --no-hooks help="Do not run hooks from config files" {
    long_help #"""
Do not run hooks from config files

Same as `MISE_NO_HOOKS=1`.
"""#
}'
@usage 'flag --no-timings help="Hide the elapsed time printed after each task completes" hide=#true {
    alias "--no-timing" hide=#true
    long_help #"""
Hide the elapsed time printed after each task completes

Set `MISE_TASK_TIMINGS=0` to hide it by default
"""#
}'
@usage 'flag --output help="How task output is displayed when running a task (same as `mise run --output`)" hide=#true {
    arg <OUTPUT>
}'
@usage 'flag --raw help="Connect tasks and install commands directly to the terminal" global=#true {
    long_help #"""
Connect tasks and install commands directly to the terminal

Commands then run one at a time. Same as `MISE_RAW=1` or the `raw` setting.
"""#
}'
@usage 'flag --locked help="Require download URLs from the lockfile when installing" global=#true {
    long_help #"""
Require download URLs from the lockfile when installing

Installing fails when the lockfile has no pre-resolved URL for a tool on the current platform, so mise does not call the GitHub or aqua registry APIs to find one. Same as `MISE_LOCKED=1` or the `locked` setting.
"""#
}'
@usage 'flag --silent help="Suppress all task output and mise non-error messages" global=#true {
    overrides "--quiet" "--trace" "--verbose" "--debug" "--log-level"
}'
@usage 'flag --timings help="Show the elapsed time after each task completes" hide=#true {
    alias "--timing" hide=#true
    long_help #"""
Show the elapsed time after each task completes

Set `MISE_TASK_TIMINGS=1` to show it by default
"""#
}'
@usage 'flag --trace help="Set the log level to trace" hide=#true global=#true {
    overrides "--quiet" "--silent" "--verbose" "--debug" "--log-level"
}'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[TASK]" help="Task to run" help_long=#"""
Task to run

Shorthand for `mise run <TASK>`.
"""# required=#false double_dash=automatic'
@usage 'arg "[TASK_ARGS]…" help="Task arguments" required=#false var=#true hide=#true'
@usage 'arg "[-- TASK_ARGS_LAST]…" required=#false var=#true hide=#true'
@usage r#'example "mise use node@24" help="Install node 24 and add it to the project's mise.toml"'#
@usage 'example "mise use -g node@24" help="Make node 24 your global default"'
@usage 'example "mise install" help="Install every tool the config requests"'
@usage r#'example "mise x -- npm install" help="Run a command with the project's tools on PATH"'#
@usage 'example "mise x python@3.13 -- python app.py" help="Run a command with a tool that is not in the config"'
@usage 'example "mise set NODE_ENV=production" help="Add an environment variable to mise.toml"'
@usage 'example "mise run build" help="Run the build task"'
@usage 'example "mise watch build" help="Rerun the build task when its sources change"'
@usage 'example "mise upgrade --interactive" help="Choose tools to upgrade from a menu"'
@usage 'example "mise settings color=0" help="Turn off color in the global config"'
@usage 'complete dir type=dir'
@usage r#'complete alias run="mise alias ls -- {{words[PREV] | shell_quote}} | awk '{print $2}'"'#
@usage 'complete config_file type=file'
@usage 'complete new_plugin run="mise plugins --all"'
@usage r#'complete installed_tool run="mise ls -i | awk '{print $1}' | uniq"'#
@usage 'complete plugin run="mise plugins --core --user"'
@usage 'complete prefix run="mise ls-remote -- {{words[PREV] | shell_quote}}"'
@usage 'complete setting run="mise settings --complete" descriptions=#true'
@usage 'complete task run="mise tasks ls --complete" descriptions=#true'
@usage 'complete tool run="mise search --complete -- {{words[CURRENT] | shell_quote}}" descriptions=#true'
@usage r#'complete env_var run="mise set --complete | awk '{print $1\"=\"}'"'#
@usage 'complete env_key run="mise set --complete"'
@usage 'complete secret run="mise secrets ls --complete"'
@usage 'complete backend run="mise backends"'
@usage 'complete bin_name run="mise which --complete"'
@usage r#'complete tool@version run=#"""
cur={{words[CURRENT] | shell_quote}}
case $cur in
  *@*)
    tool="$(echo "$cur" | cut -d'@' -f1)"
    prefix="$(echo "$cur" | cut -d'@' -f2)"

    versions=$(mise ls-remote -- "$tool" ${prefix:+"$prefix"} | sed '1!G;h;$!d')

    for version in $versions; do
      echo "$tool@$version"
    done
    ;;
  *)
    plugins=$(mise search --complete-ids "$cur")
    for plugin in $plugins; do
      echo "$plugin@"
    done
    ;;
esac
"""#'#
@usage r#'complete installed_tool@version run=#"""
cur={{words[CURRENT] | shell_quote}}
case $cur in
  *@*)
    tool="$(echo "$cur" | cut -d'@' -f1)"
    prefix="$(echo "$cur" | cut -d'@' -f2)"

    versions=$(mise ls --installed ${prefix:+--prefix "$prefix"} -- "$tool" | awk '{print $2}' | sed '1!G;h;$!d')

    for version in $versions; do
      echo "$tool@$version"
    done
    ;;
  *)
    plugins=$(mise ls --installed | awk '{print $1}' | uniq | sed '1!G;h;$!d')
    for plugin in $plugins; do
      echo "$plugin@"
    done
    ;;
esac
"""#'#
export def main [
    task?: string@"nus complete",    # Task to run
    ...task_args: string,            # Task arguments
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --no-config,                     # Do not load any config files
    --no-env,                        # Do not load environment variables from config files
    --no-hooks,                      # Do not run hooks from config files
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise ...(nus argv [$task ...$task_args] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --no-config: $no_config
        --no-env: $no_env
        --no-hooks: $no_hooks
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Print the script to activate mise in an interactive shell
#
# Evaluate this command's output with the syntax for your shell; running it alone
# only prints the script. Activation updates tools and environment variables as
# this shell changes directories.
#
# Add the matching example below once to your interactive startup file:
# ~/.bashrc for Bash, ~/.zshrc for Zsh, ~/.config/fish/config.fish for Fish,
# or $PROFILE for PowerShell. For Nushell, Elvish and other shells, see
# https://mise.jdx.dev/shell-setup.html.
#
# The mise executable must be on PATH before that line runs. Otherwise use its
# absolute path, for example `eval "$(~/.local/bin/mise activate zsh)"`.
#
# Use `mise exec -- command` for scripts and CI that do not need interactive hooks.
# The `status.*` settings control the messages mise prints when you change
# directories.
@usage r#'long_help #"""
Print the script to activate mise in an interactive shell

Evaluate this command's output with the syntax for your shell; running it alone
only prints the script. Activation updates tools and environment variables as
this shell changes directories.

Add the matching example below once to your interactive startup file:
~/.bashrc for Bash, ~/.zshrc for Zsh, ~/.config/fish/config.fish for Fish,
or $PROFILE for PowerShell. For Nushell, Elvish and other shells, see
https://mise.jdx.dev/shell-setup.html.

The mise executable must be on PATH before that line runs. Otherwise use its
absolute path, for example `eval "$(~/.local/bin/mise activate zsh)"`.

Use `mise exec -- command` for scripts and CI that do not need interactive hooks.
The `status.*` settings control the messages mise prints when you change
directories.
"""#'#
@usage 'flag "-q --quiet" help="Suppress non-error messages from the hook that runs at each prompt"'
@usage 'flag "-s --shell" help="Shell type to generate the script for" hide=#true {
        arg <SHELL> {
            choices {
                choice bash
                choice elvish
                choice fish
                choice nu
                choice xonsh
                choice zsh
                choice pwsh {
                    alias powershell
                }
            }
        }
    }'
@usage 'flag --no-hook-env help="Do not run hook-env automatically" {
        long_help #"""
Do not run hook-env automatically

Use it for debugging: after `eval "$(mise activate zsh --no-hook-env)"`, run `mise hook-env` yourself to print the shell code it would evaluate, or `mise hook-env --trace` for more detail.
"""#
    }'
@usage 'flag --shims help="Put the shims directory on PATH instead of updating PATH at each prompt" {
        long_help #"""
Put the shims directory on PATH instead of updating PATH at each prompt

Roughly equivalent to:

    PATH="$HOME/.local/share/mise/shims:$PATH"

Shims do not support every feature of `mise activate`; see
https://mise.jdx.dev/dev-tools/shims.html#shims-vs-path.
"""#
    }'
@usage 'flag --status help="Show \"mise: <TOOL>@<VERSION>\" message when changing directories" hide=#true'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[SHELL_TYPE]" help="Shell type to generate the script for" help_long=#"""
Shell type to generate the script for

Defaults to the shell named by MISE_SHELL or SHELL. mise reports an error when neither names a supported shell, as in PowerShell and cmd on Windows.
"""# required=#false {
        choices {
            choice bash
            choice elvish
            choice fish
            choice nu
            choice xonsh
            choice zsh
            choice pwsh {
                alias powershell
            }
        }
    }'
@usage 'example "eval \"$(mise activate bash)\"" help="Activate mise in Bash"'
@usage 'example "eval \"$(mise activate zsh)\"" help="Activate mise in Zsh"'
@usage 'example "mise activate fish | source" help="Activate mise in Fish"'
@usage 'example "execx($(mise activate xonsh))" help="Activate mise in Xonsh"'
@usage 'example "(&mise activate pwsh) | Out-String | Invoke-Expression" help="Activate mise in PowerShell"'
export def "mise activate" [
    shell_type?: string@[bash elvish fish nu xonsh zsh pwsh],  # Shell type to generate the script for
    --cd (-C): path@"nus complete",                            # Run as if mise were started in DIR
    --env_ (-E): list<string>,                                 # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                                       # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                                              # Suppress non-error messages
    --verbose (-v): int,                                       # Show extra output (use -vv for even more)
    --yes (-y),                                                # Answer yes to all confirmation prompts
    --raw,                                                     # Connect tasks and install commands directly to the terminal
    --locked,                                                  # Require download URLs from the lockfile when installing
    --silent,                                                  # Suppress all task output and mise non-error messages
    --no-hook-env,                                             # Do not run hook-env automatically
    --shims,                                                   # Put the shims directory on PATH instead of updating PATH at each prompt
]: nothing -> string {
    ^mise activate ...(nus argv [$shell_type] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --no-hook-env: $no_hook_env
        --shims: $shims
    })
}

# Manage tool backend and version aliases
#
# A backend alias makes a tool name install from another backend:
# `[tool_alias] ripgrep = "aqua:BurntSushi/ripgrep"`. A version alias names a
# version request: `[tool_alias.node.versions] project = "20"` lets you write
# `node@project`.
#
# With no subcommand, lists version aliases (same as `mise tool-alias ls`; the
# flags below are passed to it). See https://mise.jdx.dev/dev-tools/aliases.html
@usage 'alias alias aliases'
@usage 'long_help #"""
Manage tool backend and version aliases

A backend alias makes a tool name install from another backend:
`[tool_alias] ripgrep = "aqua:BurntSushi/ripgrep"`. A version alias names a
version request: `[tool_alias.node.versions] project = "20"` lets you write
`node@project`.

With no subcommand, lists version aliases (same as `mise tool-alias ls`; the
flags below are passed to it). See https://mise.jdx.dev/dev-tools/aliases.html
"""#'
@usage 'flag "-p --tool" help="Filter aliases by tool" {
        alias "--plugin" hide=#true
        arg <TOOL>
    }'
@usage 'flag --no-header help="Do not print the table header"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise tool-alias" [
    --cd (-C): path@"nus complete",      # Run as if mise were started in DIR
    --env_ (-E): list<string>,           # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                 # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                        # Suppress non-error messages
    --tool (-p): string@"nus complete",  # Filter aliases by tool
    --verbose (-v): int,                 # Show extra output (use -vv for even more)
    --yes (-y),                          # Answer yes to all confirmation prompts
    --raw,                               # Connect tasks and install commands directly to the terminal
    --locked,                            # Require download URLs from the lockfile when installing
    --silent,                            # Suppress all task output and mise non-error messages
    --no-header,                         # Do not print the table header
]: nothing -> string {
    ^mise tool-alias ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --tool: $tool
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --no-header: $no_header
    })
}

# Show the version a tool's version alias stands for
#
# Reads `[tool_alias.TOOL.versions]` from every loaded config file and the
# aliases the tool's backend provides, such as node's `lts-*` aliases. It
# prints the stored request, which may itself be a prefix.
@usage r#'long_help #"""
Show the version a tool's version alias stands for

Reads `[tool_alias.TOOL.versions]` from every loaded config file and the
aliases the tool's backend provides, such as node's `lts-*` aliases. It
prints the stored request, which may itself be a prefix.
"""#'#
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <TOOL> help="The tool to show the alias for"'
@usage 'arg <ALIAS> help="The alias to show"'
@usage r#'example #"""
mise tool-alias get node lts
24
"""# help="Show the version node's lts alias stands for"'#
@usage 'example #"""
mise tool-alias set node project 20
mise tool-alias get node project
20
"""# help="Read back an alias you set"'
export def "mise tool-alias get" [
    tool: string@"nus complete",     # The tool to show the alias for
    alias: string@"nus complete",    # The alias to show
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise tool-alias get ...(nus argv [$tool $alias] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# List tool version aliases
#
# Lists version aliases from `[tool_alias.<tool>.versions]` in any loaded
# config file and the aliases that tool backends provide, such as node's
# `lts-*` names or an asdf plugin's `bin/list-aliases`. For example:
#
#     [tool_alias.node.versions]
#     project = "20"
#
# Backend aliases (`[tool_alias] tool = "backend"`) are not listed; run
# `mise tool <TOOL>` to see the backend a tool uses.
@usage 'alias list'
@usage r#'long_help #"""
List tool version aliases

Lists version aliases from `[tool_alias.<tool>.versions]` in any loaded
config file and the aliases that tool backends provide, such as node's
`lts-*` names or an asdf plugin's `bin/list-aliases`. For example:

    [tool_alias.node.versions]
    project = "20"

Backend aliases (`[tool_alias] tool = "backend"`) are not listed; run
`mise tool <TOOL>` to see the backend a tool uses.
"""#'#
@usage 'flag --no-header help="Do not print the table header"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[TOOL]" help="Only show aliases for this tool" required=#false'
@usage r#'example #"""
mise tool-alias ls node
tool  alias      version
node  lts        24
node  lts-jod    22
node  project    20
"""# help="List node's version aliases"'#
export def "mise tool-alias ls" [
    tool?: string@"nus complete",    # Only show aliases for this tool
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --no-header,                     # Do not print the table header
]: nothing -> string {
    ^mise tool-alias ls ...(nus argv [$tool] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --no-header: $no_header
    })
}

# Set a backend alias or a version alias in the global config
#
# `mise tool-alias set TOOL BACKEND` makes TOOL install from BACKEND, written as
# `[tool_alias] TOOL = "BACKEND"`. `mise tool-alias set TOOL ALIAS VERSION` makes
# `TOOL@ALIAS` mean VERSION, written under `[tool_alias.TOOL.versions]`. Writes
# the global config (~/.config/mise/config.toml by default); add aliases to a
# project's mise.toml to share them.
@usage 'alias add create'
@usage r#'long_help #"""
Set a backend alias or a version alias in the global config

`mise tool-alias set TOOL BACKEND` makes TOOL install from BACKEND, written as
`[tool_alias] TOOL = "BACKEND"`. `mise tool-alias set TOOL ALIAS VERSION` makes
`TOOL@ALIAS` mean VERSION, written under `[tool_alias.TOOL.versions]`. Writes
the global config (~/.config/mise/config.toml by default); add aliases to a
project's mise.toml to share them.
"""#'#
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <TOOL> help="The tool to alias"'
@usage 'arg <ALIAS> help="The version alias to set, or the backend when VALUE is omitted"'
@usage 'arg "[VALUE]" help="The version request the alias stands for" required=#false'
@usage 'example "mise tool-alias set ripgrep aqua:BurntSushi/ripgrep" help="Install ripgrep from its aqua backend"'
@usage 'example "mise tool-alias set node project 20" help="Make node@project mean node@20"'
export def "mise tool-alias set" [
    tool: string@"nus complete",     # The tool to alias
    alias: string@"nus complete",    # The version alias to set, or the backend when VALUE is omitted
    value?: string,                  # The version request the alias stands for
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise tool-alias set ...(nus argv [$tool $alias $value] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Remove a backend alias or a version alias from the global config
#
# With only TOOL, removes the tool's backend alias. With TOOL and ALIAS,
# removes that version alias. Edits the global config
# (~/.config/mise/config.toml by default).
@usage 'alias rm remove delete del'
@usage r#'long_help #"""
Remove a backend alias or a version alias from the global config

With only TOOL, removes the tool's backend alias. With TOOL and ALIAS,
removes that version alias. Edits the global config
(~/.config/mise/config.toml by default).
"""#'#
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <TOOL> help="The tool to remove the alias from"'
@usage 'arg "[ALIAS]" help="The version alias to remove; omit it to remove the backend alias" required=#false'
@usage r#'example "mise tool-alias unset ripgrep" help="Remove ripgrep's backend alias"'#
@usage r#'example "mise tool-alias unset node project" help="Remove node's project version alias"'#
export def "mise tool-alias unset" [
    tool: string@"nus complete",     # The tool to remove the alias from
    alias?: string@"nus complete",   # The version alias to remove; omit it to remove the backend alias
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise tool-alias unset ...(nus argv [$tool $alias] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Manage backends
#
# A backend is where mise installs a tool from: a package registry such as npm or
# cargo, a release host such as GitHub, or a plugin. Each tool uses one, either
# written as a prefix (`npm:prettier`) or chosen by the registry. With no
# subcommand, lists the built-in backends. See
# https://mise.jdx.dev/dev-tools/backends/.
@usage 'alias b backend backend-list'
@usage 'long_help #"""
Manage backends

A backend is where mise installs a tool from: a package registry such as npm or
cargo, a release host such as GitHub, or a plugin. Each tool uses one, either
written as a prefix (`npm:prettier`) or chosen by the registry. With no
subcommand, lists the built-in backends. See
https://mise.jdx.dev/dev-tools/backends/.
"""#'
@usage 'after_long_help "\u{1b}[1m\u{1b}[4mDeprecation:\u{1b}[22m\u{1b}[24m\n\nThe `mise b` alias is deprecated and will be removed in mise 2027.4.0; use\n`mise backends`.\n"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise backends" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise backends ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# List built-in backends
#
# Backends that plugins add are listed by `mise plugins ls`.
@usage 'alias list'
@usage 'long_help #"""
List built-in backends

Backends that plugins add are listed by `mise plugins ls`.
"""#'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise backends ls" help="List the backends built into mise"'
export def "mise backends ls" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise backends ls ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Switch tools to the backend the registry now installs them from
#
# When the registry moves a tool to another backend, mise keeps installing it
# from the backend recorded in mise.lock and warns that the registry has a
# newer one. This moves those lock entries to the registry's backend at the
# same versions, relocks them to record the new backend's checksums and URLs,
# and reinstalls installed versions so they come from the new backend.
#
# It covers the lockfiles `mise lock` writes: the current project's, or the
# global config's with `--global`.
@usage r#'long_help #"""
Switch tools to the backend the registry now installs them from

When the registry moves a tool to another backend, mise keeps installing it
from the backend recorded in mise.lock and warns that the registry has a
newer one. This moves those lock entries to the registry's backend at the
same versions, relocks them to record the new backend's checksums and URLs,
and reinstalls installed versions so they come from the new backend.

It covers the lockfiles `mise lock` writes: the current project's, or the
global config's with `--global`.
"""#'#
@usage 'flag "-n --dry-run" help="Show what would switch without changing the lockfile or installs"'
@usage r#'flag "-g --global" help="Switch tools in the global config's lockfile instead of the project's"'#
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[TOOL@VERSION]…" help="Tools to switch" help_long=#"""
Tools to switch

Defaults to every configured tool whose locked backend the registry
has replaced. A version (`hk@1.58.1`) limits the switch to that version.
"""# required=#false var=#true'
@usage r#'example "mise backends switch communique" help="Move communique to the registry's current backend"'#
@usage 'example "mise backends switch --dry-run" help="List every locked tool the registry now installs from another backend"'
export def "mise backends switch" [
    ...tool_version: string@"nus complete",  # Tools to switch
    --cd (-C): path@"nus complete",          # Run as if mise were started in DIR
    --env_ (-E): list<string>,               # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                     # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                          # Show what would switch without changing the lockfile or installs
    --quiet (-q),                            # Suppress non-error messages
    --verbose (-v): int,                     # Show extra output (use -vv for even more)
    --yes (-y),                              # Answer yes to all confirmation prompts
    --raw,                                   # Connect tasks and install commands directly to the terminal
    --locked,                                # Require download URLs from the lockfile when installing
    --silent,                                # Suppress all task output and mise non-error messages
    --global (-g),                           # Switch tools in the global config's lockfile instead of the project's
]: nothing -> string {
    ^mise backends switch ...(nus argv [...$tool_version] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --global: $global
    })
}

# List the bin directories of the active tools
#
# Prints the bin directories of the tool versions the current config selects. It
# does not include `_.path` entries from [env]; `mise doctor path` lists everything
# mise adds to PATH.
@usage 'long_help #"""
List the bin directories of the active tools

Prints the bin directories of the tool versions the current config selects. It
does not include `_.path` entries from [env]; `mise doctor path` lists everything
mise adds to PATH.
"""#'
@usage 'flag --bin-names help="Print executable names instead of bin directories"'
@usage 'flag "-J --json" help="Print executables as JSON objects with `name`, `path`, and `symlink` (implies --bin-names)"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[TOOL@VERSION]…" help="Only list these tools, such as `ruby@3`" required=#false var=#true'
@usage 'example "mise bin-paths" help="Print the bin directory of every active tool"'
@usage r#'example "mise bin-paths node" help="Print only node's bin directory"'#
@usage 'example "mise bin-paths --bin-names" help="List the executables the active tools provide"'
@usage 'output "json" framing="json" select="--json" {
    schema "{\n  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",\n  \"title\": \"mise bin-paths --json\",\n  \"type\": \"array\",\n  \"items\": {\n    \"type\": \"object\",\n    \"properties\": {\n      \"name\": {\n        \"type\": \"string\"\n      },\n      \"path\": {\n        \"type\": \"string\"\n      },\n      \"symlink\": {\n        \"type\": \"boolean\"\n      }\n    },\n    \"required\": [\n      \"name\",\n      \"path\",\n      \"symlink\"\n    ],\n    \"additionalProperties\": false\n  }\n}\n"
}'
export def "mise bin-paths" [
    ...tool_version: string@"nus complete",  # Only list these tools, such as `ruby@3`
    --cd (-C): path@"nus complete",          # Run as if mise were started in DIR
    --env_ (-E): list<string>,               # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                     # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                            # Suppress non-error messages
    --verbose (-v): int,                     # Show extra output (use -vv for even more)
    --yes (-y),                              # Answer yes to all confirmation prompts
    --raw,                                   # Connect tasks and install commands directly to the terminal
    --locked,                                # Require download URLs from the lockfile when installing
    --silent,                                # Suppress all task output and mise non-error messages
    --bin-names,                             # Print executable names instead of bin directories
]: nothing -> table<name: string, path: string, symlink: bool> {
    let text = ^mise bin-paths --json ...(nus argv [...$tool_version] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --bin-names: $bin_names
    })
    nus decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"title\":\"mise bin-paths --json\",\"type\":\"array\",\"items\":{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"},\"path\":{\"type\":\"string\"},\"symlink\":{\"type\":\"boolean\"}},\"required\":[\"name\",\"path\",\"symlink\"],\"additionalProperties\":false}}" { from json }
}

# Set up this machine from your mise config
#
# Applies each part your config declares, in this order. Each step names its
# parts as `--only` and `--skip` accept them, followed by any condition.
#
# 1. `accounts`, then `plugins` (package manager plugins)
# 2. `files` with `phase = "pre-packages"`, then built-in `packages`
# 3. The remaining `files`, then `services`, `firewall`, and `compose`
# 4. `repos`, then `dotfiles`
# 5. `mise-shell-activate`, `macos-defaults`, and `macos-launchd-agents`
# 6. `linux-systemd-units`, then `user` (the login shell)
# 7. `tools`
# 8. Plugin `packages`, then user `services` with `requires_tools = true`
# 9. `task` (the `bootstrap` task, if defined), then `final-hook`
#
# Hooks run before and after packages, repos, dotfiles, macOS defaults, the
# login shell, and tools. The post-packages hook runs right after built-in
# packages, or after plugin packages when any are configured. See
# https://mise.jdx.dev/bootstrap.html#how-it-runs.
#
# Parts that already match the config are left alone, but hooks and the
# `bootstrap` task run every time, so make them safe to repeat. Checking
# dotfile state can render templates, which may run `exec()`.
#
# Preview with `--dry-run`. To inspect without applying, use
# `mise bootstrap status` for current state or `mise bootstrap plan` for
# resource-level changes.
@usage 'alias bs'
@usage 'long_help #"""
Set up this machine from your mise config

Applies each part your config declares, in this order. Each step names its
parts as `--only` and `--skip` accept them, followed by any condition.

1. `accounts`, then `plugins` (package manager plugins)
2. `files` with `phase = "pre-packages"`, then built-in `packages`
3. The remaining `files`, then `services`, `firewall`, and `compose`
4. `repos`, then `dotfiles`
5. `mise-shell-activate`, `macos-defaults`, and `macos-launchd-agents`
6. `linux-systemd-units`, then `user` (the login shell)
7. `tools`
8. Plugin `packages`, then user `services` with `requires_tools = true`
9. `task` (the `bootstrap` task, if defined), then `final-hook`

Hooks run before and after packages, repos, dotfiles, macOS defaults, the
login shell, and tools. The post-packages hook runs right after built-in
packages, or after plugin packages when any are configured. See
https://mise.jdx.dev/bootstrap.html#how-it-runs.

Parts that already match the config are left alone, but hooks and the
`bootstrap` task run every time, so make them safe to repeat. Checking
dotfile state can render templates, which may run `exec()`.

Preview with `--dry-run`. To inspect without applying, use
`mise bootstrap status` for current state or `mise bootstrap plan` for
resource-level changes.
"""#'
@usage 'flag --from help="Clone a bootstrap project (a Git repository with a mise.toml) and apply it" {
        long_help #"""
Clone a bootstrap project (a Git repository with a mise.toml) and apply it

The checkout is reused on later runs; add `--update` to fast-forward it first. Append `?ref=<branch|tag|commit>` to check out a ref instead of the default branch, for example `https://github.com/example/workstation.git?ref=v1`. See https://mise.jdx.dev/bootstrap/from-repository.html.
"""#
        arg <GIT_URL>
    }'
@usage 'flag --adopt help="Clone a repository of global mise config or dotfile history, then apply it" conflicts=--from {
        long_help #"""
Clone a repository of global mise config or dotfile history, then apply it

A repository of global config (`config.toml`, `conf.d/`, `tasks/`) is cloned into the global config directory, normally ~/.config/mise. A setup repository shared with `mise dotfiles origin set` restores its tracked files instead. `OWNER/REPO` is short for `https://github.com/OWNER/REPO.git`. Append `?ref=<branch>` to adopt a branch other than the default branch.
"""#
        arg "<GIT_URL|OWNER/REPO>"
    }'
@usage r#'flag --replace-history help="Discard this machine's dotfile history and adopt the repository's" requires=--adopt {
        long_help #"""
Discard this machine's dotfile history and adopt the repository's

Use it with `--adopt` when the two histories are unrelated. Files that differ from the repository still stop the adoption until you resolve them, or add `--take-remote-all` to take the repository's version of each.
"""#
    }'#
@usage r#'flag --take-remote-all help="Take the setup repository's version of every existing file that differs while adopting" requires=--adopt {
        long_help #"""
Take the setup repository's version of every existing file that differs while adopting

The replaced versions are saved first, so `mise dot undo` restores them.
"""#
    }'#
@usage 'flag --from-dir help="Directory for the `--from` checkout (default: `$MISE_DATA_DIR/bootstrap-repo`)" requires=--from {
        arg <DIR>
    }'
@usage r#'flag --config-dir help="Link the global config directory to this directory of the `--from` checkout" requires=--from {
        long_help #"""
Link the global config directory to this directory of the `--from` checkout

mise links its config directory, normally ~/.config/mise, to the directory, then bootstraps from it, so its `config.toml`, `config.<env>.toml`, `conf.d/`, and `miserc.toml` are the global config from this run on. The directory must exist in the checkout, and the path to it is relative to the checkout and must stay inside it; `.` is the checkout itself. mise's config directory, where the link goes, must be missing, empty, or already this link. See https://mise.jdx.dev/bootstrap/from-repository.html#global-config-elsewhere.
"""#
        arg <DIR>
    }'#
@usage 'flag "-n --dry-run" help="Show what would change without changing anything" {
        long_help #"""
Show what would change without changing anything

Hooks and the `bootstrap` task are printed instead of run.
"""#
    }'
@usage 'flag "-y --yes" help="Skip confirmation prompts"'
@usage 'flag --skip-dirty help="Skip configured repositories with local changes instead of failing"'
@usage 'flag --force-dotfiles help="Overwrite existing files that conflict with whole-file dotfile entries"'
@usage 'flag --prune-dotfiles help="Remove files that dotfile groups deployed but no active entry deploys now" {
        long_help #"""
Remove files that dotfile groups deployed but no active entry deploys now

The same pruning as `mise dot apply --prune`, run at the end of the dotfiles phase before its post hook: files of a group that is no longer selected or declared, and files a group stopped deploying because of a new `exclude` or a deleted source. Changed copies stay in place, and mise asks before removing anything unless `--yes` is given or there is no terminal. With `--dry-run`, nothing is removed.
"""#
    }'
@usage 'flag --only help="Run only these parts" var=#true conflicts=--skip {
        long_help #"""
Run only these parts

Repeat the flag or separate parts with commas. Cannot be combined with `--skip`.
"""#
        arg <PART> delimiter=, {
            choices {
                choice plugins
                choice packages
                choice accounts
                choice files
                choice services
                choice firewall
                choice compose
                choice repos
                choice dotfiles
                choice mise-shell-activate {
                    alias shell hide=#true
                }
                choice macos-defaults {
                    alias defaults hide=#true
                }
                choice macos-launchd-agents {
                    alias launchd hide=#true
                }
                choice linux-systemd-units {
                    alias systemd hide=#true
                }
                choice user
                choice tools
                choice task
                choice final-hook
            }
        }
    }'
@usage 'flag --prompt-secrets help="Prompt securely for missing bootstrap secret inputs"'
@usage 'flag --prompt-vars help="Ask for `[vars]` entries that declare a `prompt` and have no saved answer" {
        long_help #"""
Ask for `[vars]` entries that declare a `prompt` and have no saved answer

mise saves each answer under `$MISE_STATE_DIR`, not in any config file, and never asks for it again. Without a terminal, a var keeps its default. A `--dry-run` still saves the answers it asks for.
"""#
    }'
@usage 'flag --skip help="Skip these parts" var=#true {
        long_help #"""
Skip these parts

Repeat the flag or separate parts with commas. Cannot be combined with `--only`.
"""#
        arg <PART> delimiter=, {
            choices {
                choice plugins
                choice packages
                choice accounts
                choice files
                choice services
                choice firewall
                choice compose
                choice repos
                choice dotfiles
                choice mise-shell-activate {
                    alias shell hide=#true
                }
                choice macos-defaults {
                    alias defaults hide=#true
                }
                choice macos-launchd-agents {
                    alias launchd hide=#true
                }
                choice linux-systemd-units {
                    alias systemd hide=#true
                }
                choice user
                choice tools
                choice task
                choice final-hook
            }
        }
    }'
@usage 'flag --update help="Refresh package metadata and update repositories before applying" {
        long_help #"""
Refresh package metadata and update repositories before applying

Also fast-forwards a checkout that `--from` or `--adopt` reuses. Without `--update`, a reused checkout stays at its current commit.
"""#
    }'
@usage 'flag --upgrade help="Upgrade installed packages and tools as well as installing missing ones" {
        long_help #"""
Upgrade installed packages and tools as well as installing missing ones

In the packages phase, runs the equivalent of `mise bootstrap packages upgrade` after installing; in the tools phase, runs `mise upgrade` (without `--bump`) after installing. Package pins and tool version ranges are respected. Does not update mise itself, repositories, or container images, and does not restart services; see `--update` for repositories and `mise self-update` for mise.
"""#
    }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise bootstrap --dry-run" help="Preview every configured part"'
@usage 'example "mise bootstrap" help="Apply every configured part"'
@usage 'example "mise bootstrap --only dotfiles,tools" help="Apply only dotfiles and tools"'
@usage 'example "mise bootstrap --skip tools,task" help="Apply everything except tools and the bootstrap task"'
@usage 'example "mise bootstrap --force-dotfiles" help="Replace files that conflict with whole-file dotfile entries"'
@usage 'example "mise bootstrap --from git@github.com:example/workstation.git" help="Clone a bootstrap project and apply it"'
@usage r#'example "mise -E work bootstrap --from git@github.com:example/workstation.git" help="Do the same and also load the project's mise.work.toml"'#
@usage 'example "mise bootstrap --from https://github.com/example/dotfiles.git --from-dir ~/.dotfiles --config-dir .config/mise" help="Clone a dotfiles repository and link ~/.config/mise to its .config/mise"'
@usage 'example "mise bootstrap --adopt example/mise-config" help="Clone global config into ~/.config/mise, then apply it"'
@usage r#'example "mise bootstrap --adopt example/setup --replace-history --yes" help="Use a setup repository's dotfile history instead of this machine's"'#
@usage 'example "mise bootstrap --update" help="Refresh package metadata and fast-forward repositories first"'
export def "mise bootstrap" [
    --cd (-C): path@"nus complete",                                                                                                                                                                          # Run as if mise were started in DIR
    --env_ (-E): list<string>,                                                                                                                                                                               # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                                                                                                                                                                                     # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                                                                                                                                                                                          # Show what would change without changing anything
    --quiet (-q),                                                                                                                                                                                            # Suppress non-error messages
    --verbose (-v): int,                                                                                                                                                                                     # Show extra output (use -vv for even more)
    --yes (-y),                                                                                                                                                                                              # Answer yes to all confirmation prompts
    --raw,                                                                                                                                                                                                   # Connect tasks and install commands directly to the terminal
    --locked,                                                                                                                                                                                                # Require download URLs from the lockfile when installing
    --silent,                                                                                                                                                                                                # Suppress all task output and mise non-error messages
    --from: string,                                                                                                                                                                                          # Clone a bootstrap project (a Git repository with a mise.toml) and apply it
    --adopt: string,                                                                                                                                                                                         # Clone a repository of global mise config or dotfile history, then apply it
    --replace-history,                                                                                                                                                                                       # Discard this machine's dotfile history and adopt the repository's
    --take-remote-all,                                                                                                                                                                                       # Take the setup repository's version of every existing file that differs while adopting
    --from-dir: path@"nus complete",                                                                                                                                                                         # Directory for the `--from` checkout (default: `$MISE_DATA_DIR/bootstrap-repo`)
    --config-dir: path@"nus complete",                                                                                                                                                                       # Link the global config directory to this directory of the `--from` checkout
    --skip-dirty,                                                                                                                                                                                            # Skip configured repositories with local changes instead of failing
    --force-dotfiles,                                                                                                                                                                                        # Overwrite existing files that conflict with whole-file dotfile entries
    --prune-dotfiles,                                                                                                                                                                                        # Remove files that dotfile groups deployed but no active entry deploys now
    --only: list<string>@[plugins packages accounts files services firewall compose repos dotfiles mise-shell-activate macos-defaults macos-launchd-agents linux-systemd-units user tools task final-hook],  # Run only these parts
    --prompt-secrets,                                                                                                                                                                                        # Prompt securely for missing bootstrap secret inputs
    --prompt-vars,                                                                                                                                                                                           # Ask for `[vars]` entries that declare a `prompt` and have no saved answer
    --skip: list<string>@[plugins packages accounts files services firewall compose repos dotfiles mise-shell-activate macos-defaults macos-launchd-agents linux-systemd-units user tools task final-hook],  # Skip these parts
    --update,                                                                                                                                                                                                # Refresh package metadata and update repositories before applying
    --upgrade,                                                                                                                                                                                               # Upgrade installed packages and tools as well as installing missing ones
]: nothing -> string {
    ^mise bootstrap ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --from: $from
        --adopt: $adopt
        --replace-history: $replace_history
        --take-remote-all: $take_remote_all
        --from-dir: $from_dir
        --config-dir: $config_dir
        --skip-dirty: $skip_dirty
        --force-dotfiles: $force_dotfiles
        --prune-dotfiles: $prune_dotfiles
        --only: $only
        --prompt-secrets: $prompt_secrets
        --prompt-vars: $prompt_vars
        --skip: $skip
        --update: $update
        --upgrade: $upgrade
    })
}

# Manage Linux users and groups
#
# Creates, updates, or removes the local accounts declared in
# `[bootstrap.users]` and `[bootstrap.groups]` on Linux. Run `status` or
# `apply --dry-run` before changing user IDs, group memberships, or account
# state.
@usage 'long_help #"""
Manage Linux users and groups

Creates, updates, or removes the local accounts declared in
`[bootstrap.users]` and `[bootstrap.groups]` on Linux. Run `status` or
`apply --dry-run` before changing user IDs, group memberships, or account
state.
"""#'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise bootstrap accounts" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise bootstrap accounts ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Create, update, or remove the configured Linux users and groups
@usage 'flag "-n --dry-run" help="Show what would change without changing anything"'
@usage 'flag "-y --yes" help="Skip the confirmation prompt"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise bootstrap accounts apply" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                  # Show what would change without changing anything
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise bootstrap accounts apply ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Show the state of the configured Linux users and groups
@usage 'flag "-J --json" help="Output in JSON format"'
@usage 'flag --missing help="Exit with status 1 if any account differs from the config (all are still listed)"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'output json framing=json select=--json'
export def "mise bootstrap accounts status" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --missing,                       # Exit with status 1 if any account differs from the config (all are still listed)
] {
    ^mise bootstrap accounts status --json ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --missing: $missing
    }) | from json
}

# Manage Docker Compose projects from `[bootstrap.compose]`
#
# Needs a running Docker engine and the Docker Compose command on this
# machine.
@usage 'long_help #"""
Manage Docker Compose projects from `[bootstrap.compose]`

Needs a running Docker engine and the Docker Compose command on this
machine.
"""#'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise bootstrap compose status" help="Show the state of every declared project"'
@usage 'example "mise bootstrap compose apply --dry-run" help="Show what would change"'
export def "mise bootstrap compose" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise bootstrap compose ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Apply Docker Compose projects from `[bootstrap.compose]`
@usage 'flag "-n --dry-run" help="Show what would change without changing anything"'
@usage 'flag "-y --yes" help="Skip the confirmation prompt"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise bootstrap compose apply" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                  # Show what would change without changing anything
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise bootstrap compose apply ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Show the state of Docker Compose projects from `[bootstrap.compose]`
@usage 'flag "-J --json" help="Output in JSON format"'
@usage 'flag --missing help="Exit with status 1 if any Compose project differs from the config (all are still listed)"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'output json framing=json select=--json'
export def "mise bootstrap compose status" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --missing,                       # Exit with status 1 if any Compose project differs from the config (all are still listed)
] {
    ^mise bootstrap compose status --json ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --missing: $missing
    }) | from json
}

# Manage system files and directories declared in `[bootstrap]`
#
# Applies `[bootstrap.files]` and `[bootstrap.directories]`: paths that need a
# specific owner, group, or mode, or that must exist or be absent system-wide,
# such as configuration under /etc. For files in your home directory that you
# edit, use `[dotfiles]` and `mise dotfiles`.
@usage 'long_help #"""
Manage system files and directories declared in `[bootstrap]`

Applies `[bootstrap.files]` and `[bootstrap.directories]`: paths that need a
specific owner, group, or mode, or that must exist or be absent system-wide,
such as configuration under /etc. For files in your home directory that you
edit, use `[dotfiles]` and `mise dotfiles`.
"""#'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise bootstrap files status --missing" help="Exit with status 1 if any file or directory differs from the config"'
@usage 'example "mise bootstrap files apply --dry-run" help="Show what would change"'
@usage 'example "mise bootstrap files apply --yes" help="Apply without a prompt"'
export def "mise bootstrap files" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise bootstrap files ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Create, update, or remove the configured system files and directories
@usage 'flag "-n --dry-run" help="Show what would change without changing anything"'
@usage 'flag "-y --yes" help="Skip the confirmation prompt"'
@usage 'flag --prompt-secrets help="Prompt securely for missing bootstrap secret inputs"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise bootstrap files apply" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                  # Show what would change without changing anything
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --prompt-secrets,                # Prompt securely for missing bootstrap secret inputs
]: nothing -> string {
    ^mise bootstrap files apply ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --prompt-secrets: $prompt_secrets
    })
}

# Show the state of the configured system files and directories
@usage 'flag "-J --json" help="Output in JSON format"'
@usage 'flag --missing help="Exit with status 1 if any file or directory differs from the config (all are still listed)"'
@usage 'flag --prompt-secrets help="Prompt securely for missing bootstrap secret inputs"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'output json framing=json select=--json'
export def "mise bootstrap files status" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --prompt-secrets,                # Prompt securely for missing bootstrap secret inputs
    --missing,                       # Exit with status 1 if any file or directory differs from the config (all are still listed)
] {
    ^mise bootstrap files status --json ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --prompt-secrets: $prompt_secrets
        --missing: $missing
    }) | from json
}

# Manage the Linux host firewall from `[bootstrap.linux.firewall]`
#
# Works with nftables, firewalld, or UFW, and keeps mise's rules separate from
# other host rules. Over SSH, mise refuses a default incoming policy of deny
# or reject unless a rule allows the current connection or the config sets
# `allow_lockout = true`. Check `apply --dry-run` before applying a policy to
# a remote machine.
@usage r#'long_help #"""
Manage the Linux host firewall from `[bootstrap.linux.firewall]`

Works with nftables, firewalld, or UFW, and keeps mise's rules separate from
other host rules. Over SSH, mise refuses a default incoming policy of deny
or reject unless a rule allows the current connection or the config sets
`allow_lockout = true`. Check `apply --dry-run` before applying a policy to
a remote machine.
"""#'#
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage r#'example "mise bootstrap firewall status" help="Show the firewall's state"'#
@usage 'example "mise bootstrap firewall apply --dry-run" help="Show the policy and rules that would change"'
export def "mise bootstrap firewall" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise bootstrap firewall ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Apply the firewall from `[bootstrap.linux.firewall]`
@usage 'flag "-n --dry-run" help="Show what would change without changing anything"'
@usage 'flag "-y --yes" help="Skip the confirmation prompt"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise bootstrap firewall apply" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                  # Show what would change without changing anything
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise bootstrap firewall apply ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Show the state of the firewall from `[bootstrap.linux.firewall]`
@usage 'flag "-J --json" help="Output in JSON format"'
@usage 'flag --missing help="Exit with status 1 if the firewall differs from the config"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'output json framing=json select=--json'
export def "mise bootstrap firewall status" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --missing,                       # Exit with status 1 if the firewall differs from the config
] {
    ^mise bootstrap firewall status --json ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --missing: $missing
    }) | from json
}

# Manage systemd user units from `[bootstrap.linux.systemd.units]`
#
# The host firewall in `[bootstrap.linux.firewall]` is managed by
# `mise bootstrap firewall`.
@usage 'long_help #"""
Manage systemd user units from `[bootstrap.linux.systemd.units]`

The host firewall in `[bootstrap.linux.firewall]` is managed by
`mise bootstrap firewall`.
"""#'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise bootstrap linux" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise bootstrap linux ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Manage systemd user units from `[bootstrap.linux.systemd.units]`
#
# Writes unit files to ~/.config/systemd/user, then enables and starts them
# as configured. An entry with `state = "absent"` is stopped, disabled, and
# deleted instead. Units run with your permissions and need a reachable
# systemd user manager. For system units, or a user service that also works
# on macOS and Windows, use `[bootstrap.services]`.
@usage 'alias systemd'
@usage 'long_help #"""
Manage systemd user units from `[bootstrap.linux.systemd.units]`

Writes unit files to ~/.config/systemd/user, then enables and starts them
as configured. An entry with `state = "absent"` is stopped, disabled, and
deleted instead. Units run with your permissions and need a reachable
systemd user manager. For system units, or a user service that also works
on macOS and Windows, use `[bootstrap.services]`.
"""#'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise bootstrap linux systemd-units" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise bootstrap linux systemd-units ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Install and start the configured systemd user units
@usage 'flag "-n --dry-run" help="Show what would change without changing anything"'
@usage 'flag "-y --yes" help="Skip the confirmation prompt"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise bootstrap linux systemd-units apply" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                  # Show what would change without changing anything
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise bootstrap linux systemd-units apply ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Show the state of the configured systemd user units
@usage 'flag "-J --json" help="Output in JSON format"'
@usage 'flag --missing help="Exit with status 1 if any unit differs from the config (all are still listed)"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'output json framing=json select=--json'
export def "mise bootstrap linux systemd-units status" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --missing,                       # Exit with status 1 if any unit differs from the config (all are still listed)
] {
    ^mise bootstrap linux systemd-units status --json ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --missing: $missing
    }) | from json
}

# Manage macOS preferences and LaunchAgents from `[bootstrap.macos]`
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise bootstrap macos" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise bootstrap macos ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Manage macOS preferences such as Dock, Finder, and keyboard settings
#
# Applies `[bootstrap.macos.defaults]`, `[[bootstrap.macos.defaults_entries]]`,
# and the `[bootstrap.macos.dock]`, `finder`, `keyboard`, and `trackpad`
# sections. Preferences are written the way `defaults write` writes them.
# mise does not restart apps: Dock, Finder, and some others show a change
# only after they relaunch.
@usage 'long_help #"""
Manage macOS preferences such as Dock, Finder, and keyboard settings

Applies `[bootstrap.macos.defaults]`, `[[bootstrap.macos.defaults_entries]]`,
and the `[bootstrap.macos.dock]`, `finder`, `keyboard`, and `trackpad`
sections. Preferences are written the way `defaults write` writes them.
mise does not restart apps: Dock, Finder, and some others show a change
only after they relaunch.
"""#'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise bootstrap macos defaults" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise bootstrap macos defaults ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Write the configured macOS preferences
@usage 'flag "-n --dry-run" help="Show what would change without changing anything"'
@usage 'flag "-y --yes" help="Skip the confirmation prompt"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise bootstrap macos defaults apply" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                  # Show what would change without changing anything
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise bootstrap macos defaults apply ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Show the state of the configured macOS preferences
@usage 'flag "-J --json" help="Output in JSON format"'
@usage 'flag --missing help="Exit with status 1 if any preference differs from the config (all are still listed)"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'output json framing=json select=--json'
export def "mise bootstrap macos defaults status" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --missing,                       # Exit with status 1 if any preference differs from the config (all are still listed)
] {
    ^mise bootstrap macos defaults status --json ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --missing: $missing
    }) | from json
}

# Manage macOS LaunchAgents from `[bootstrap.macos.launchd.agents]`
#
# Writes each agent to ~/Library/LaunchAgents/dev.mise.<name>.plist and loads
# it into your GUI login session. Run it as the user who owns the agents; an
# SSH session without a GUI login may not be able to load them. For a user
# service that also works on Linux and Windows, use `[bootstrap.services]`
# with `scope = "user"`.
@usage 'alias launchd'
@usage 'long_help #"""
Manage macOS LaunchAgents from `[bootstrap.macos.launchd.agents]`

Writes each agent to ~/Library/LaunchAgents/dev.mise.<name>.plist and loads
it into your GUI login session. Run it as the user who owns the agents; an
SSH session without a GUI login may not be able to load them. For a user
service that also works on Linux and Windows, use `[bootstrap.services]`
with `scope = "user"`.
"""#'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise bootstrap macos launchd-agents" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise bootstrap macos launchd-agents ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Install and load LaunchAgents from `[bootstrap.macos.launchd.agents]`
@usage 'flag "-n --dry-run" help="Show what would change without changing anything"'
@usage 'flag "-y --yes" help="Skip the confirmation prompt"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise bootstrap macos launchd-agents apply" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                  # Show what would change without changing anything
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise bootstrap macos launchd-agents apply ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Show the state of the configured LaunchAgents
@usage 'flag "-J --json" help="Output in JSON format"'
@usage 'flag --missing help="Exit with status 1 if any LaunchAgent differs from the config (all are still listed)"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'output json framing=json select=--json'
export def "mise bootstrap macos launchd-agents status" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --missing,                       # Exit with status 1 if any LaunchAgent differs from the config (all are still listed)
] {
    ^mise bootstrap macos launchd-agents status --json ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --missing: $missing
    }) | from json
}

# Manage mise shell activation from `[bootstrap.mise_shell_activate]`
#
# Writes a managed activation block into each configured shell startup file.
# It does not activate mise in the shell you run it from; open a new shell
# afterward.
@usage 'alias shell'
@usage 'long_help #"""
Manage mise shell activation from `[bootstrap.mise_shell_activate]`

Writes a managed activation block into each configured shell startup file.
It does not activate mise in the shell you run it from; open a new shell
afterward.
"""#'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise bootstrap mise-shell-activate" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise bootstrap mise-shell-activate ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Write mise activation into the configured shell startup files
@usage 'flag "-n --dry-run" help="Show what would change without changing anything"'
@usage 'flag "-y --yes" help="Skip the confirmation prompt"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise bootstrap mise-shell-activate apply" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                  # Show what would change without changing anything
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise bootstrap mise-shell-activate apply ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Show the state of the configured shell activation
@usage 'flag "-J --json" help="Output in JSON format"'
@usage 'flag --missing help="Exit with status 1 if any shell activation differs from the config (all are still listed)"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'output json framing=json select=--json'
export def "mise bootstrap mise-shell-activate status" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --missing,                       # Exit with status 1 if any shell activation differs from the config (all are still listed)
] {
    ^mise bootstrap mise-shell-activate status --json ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --missing: $missing
    }) | from json
}

# Manage packages from `[bootstrap.packages]`
#
# Declare packages as `"manager:package" = "version"`. `apply` installs what
# is missing and removes what is declared absent, `use` adds an entry and
# installs it, and `upgrade` updates configured packages that are installed.
# `prune` uninstalls Homebrew formulae, casks, or package plugin packages that
# no config declares. `import` records installed Homebrew formulae, and
# `status` shows what differs from the config. See
# https://mise.jdx.dev/bootstrap/packages/ for each package manager.
@usage 'long_help #"""
Manage packages from `[bootstrap.packages]`

Declare packages as `"manager:package" = "version"`. `apply` installs what
is missing and removes what is declared absent, `use` adds an entry and
installs it, and `upgrade` updates configured packages that are installed.
`prune` uninstalls Homebrew formulae, casks, or package plugin packages that
no config declares. `import` records installed Homebrew formulae, and
`status` shows what differs from the config. See
https://mise.jdx.dev/bootstrap/packages/ for each package manager.
"""#'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise bootstrap packages" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise bootstrap packages ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Install or remove packages to match `[bootstrap.packages]`
#
# Installs each configured package that is missing or does not match its
# declared version, and removes packages declared `state = "absent"` on the
# managers that support removal (pacman, scoop, snap, and zypper). On other
# managers, an installed package declared absent is left in place with a
# warning; `apply` fails for it only when you pass `--manager` or name the
# package.
# Built-in managers may use sudo when not running as root (see the
# `system_packages.sudo` setting); package plugins never do. Managers that
# are not available on this machine are skipped.
#
# Name packages as `manager:package`, for example `apt:curl` or `brew:jq`, to
# install them without adding them to config; use
# `mise bootstrap packages use` to record them as well. When you name packages
# or pass `--manager`, an unavailable manager is an error instead of a skip.
@usage 'alias i install'
@usage 'long_help #"""
Install or remove packages to match `[bootstrap.packages]`

Installs each configured package that is missing or does not match its
declared version, and removes packages declared `state = "absent"` on the
managers that support removal (pacman, scoop, snap, and zypper). On other
managers, an installed package declared absent is left in place with a
warning; `apply` fails for it only when you pass `--manager` or name the
package.
Built-in managers may use sudo when not running as root (see the
`system_packages.sudo` setting); package plugins never do. Managers that
are not available on this machine are skipped.

Name packages as `manager:package`, for example `apt:curl` or `brew:jq`, to
install them without adding them to config; use
`mise bootstrap packages use` to record them as well. When you name packages
or pass `--manager`, an unavailable manager is an error instead of a skip.
"""#'
@usage 'flag "-m --manager" help="Only apply packages for this built-in or plugin manager" {
                arg <MANAGER>
            }'
@usage 'flag "-n --dry-run" help="Show what would change without changing anything"'
@usage 'flag "-y --yes" help="Skip the confirmation prompt"'
@usage 'flag --update help="Refresh package manager metadata first, where the manager supports it" {
                long_help #"""
Refresh package manager metadata first, where the manager supports it

For example, apt runs `apt-get update` and dnf adds `--refresh`. brew, brew-cask, flatpak, flatpak-user, macos-app, mas, and snap ignore this flag.
"""#
            }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[PACKAGE]…" help="Packages as `manager:package`; defaults to every package in `[bootstrap.packages]`" required=#false var=#true'
@usage 'example "mise bootstrap packages apply" help="Install missing packages and remove ones declared absent"'
@usage 'example "mise bootstrap packages apply --dry-run" help="Show what would change"'
@usage 'example "mise bootstrap packages apply --manager apt --yes" help="Apply only apt packages, without a prompt"'
@usage 'example "mise bootstrap packages apply apt:curl" help="On Debian or Ubuntu, install one package without adding it to config"'
@usage 'example "mise bootstrap packages apply brew:jq brew-cask:firefox" help="On macOS, install a formula and a cask without adding them to config"'
export def "mise bootstrap packages apply" [
    ...package: string,              # Packages as `manager:package`; defaults to every package in `[bootstrap.packages]`
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                  # Show what would change without changing anything
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --update,                        # Refresh package manager metadata first, where the manager supports it
    --manager (-m): string,          # Only apply packages for this built-in or plugin manager
]: nothing -> string {
    ^mise bootstrap packages apply ...(nus argv [...$package] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --update: $update
        --manager: $manager
    })
}

# Manage Homebrew tap URLs in `[bootstrap.brew.taps]`
#
# mise finds a third-party tap such as `acme/tools` at
# `https://github.com/acme/homebrew-tools` without an entry. Add one only
# when the tap's repository lives at a different GitHub URL; only GitHub taps
# are supported. These commands edit config; they do not run Homebrew.
#
# Not available on Windows.
@usage r#'long_help #"""
Manage Homebrew tap URLs in `[bootstrap.brew.taps]`

mise finds a third-party tap such as `acme/tools` at
`https://github.com/acme/homebrew-tools` without an entry. Add one only
when the tap's repository lives at a different GitHub URL; only GitHub taps
are supported. These commands edit config; they do not run Homebrew.

Not available on Windows.
"""#'#
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise bootstrap packages brew" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise bootstrap packages brew ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Add a Homebrew tap URL to the global `[bootstrap.brew.taps]`
@usage 'flag "-l --local" help="Write to the local config instead of the global config"'
@usage 'flag "-n --dry-run" help="Show the config change without writing it"'
@usage 'flag "-p --path --file" help="Write to this config file or directory" conflicts=--local {
                    arg <PATH>
                }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <TAP> help="Tap name, e.g. `owner/repo`"'
@usage 'arg "[URL]" help="GitHub URL of the tap; defaults to `https://github.com/<owner>/homebrew-<repo>.git`" required=#false'
@usage 'example "mise bootstrap packages brew tap acme/tools https://github.com/acme/brew-tools.git" help="Record a tap whose repository is not acme/homebrew-tools"'
@usage 'example "mise bootstrap packages brew tap acme/tools https://github.com/acme/brew-tools.git --local" help="Write the entry to the local config instead"'
@usage 'complete url type=url'
export def "mise bootstrap packages brew tap" [
    tap: string,                     # Tap name, e.g. `owner/repo`
    url?: string@"nus complete",     # GitHub URL of the tap; defaults to `https://github.com/<owner>/homebrew-<repo>.git`
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                  # Show the config change without writing it
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --local (-l),                    # Write to the local config instead of the global config
    --path (-p): string,             # Write to this config file or directory
]: nothing -> string {
    ^mise bootstrap packages brew tap ...(nus argv [$tap $url] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --local: $local
        --path: $path
    })
}

# Remove Homebrew tap URLs from `[bootstrap.brew.taps]`
@usage 'alias remove rm'
@usage 'flag "-l --local" help="Write to the local config instead of the global config"'
@usage 'flag "-n --dry-run" help="Show the config change without writing it"'
@usage 'flag "-p --path --file" help="Write to this config file or directory" conflicts=--local {
                    arg <PATH>
                }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <TAPS>… help="Tap names, e.g. `owner/repo`" var=#true'
@usage 'example "mise bootstrap packages brew untap acme/tools" help="Remove a tap entry from the global config"'
export def "mise bootstrap packages brew untap" [
    ...taps: string,                 # Tap names, e.g. `owner/repo`
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                  # Show the config change without writing it
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --local (-l),                    # Write to the local config instead of the global config
    --path (-p): string,             # Write to this config file or directory
]: nothing -> string {
    ^mise bootstrap packages brew untap ...(nus argv [...$taps] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --local: $local
        --path: $path
    })
}

# Print the configured `nix:` packages as a NixOS module
#
# Prints a module that adds each package to `environment.systemPackages`,
# without running Nix. Import it into a NixOS configuration; packages resolve
# against that configuration's `pkgs`. Entries for another OS or environment,
# and entries with `state = "absent"`, are left out. Only shorthand
# attributes such as `nix:ripgrep` can be exported: a flake reference or a
# version pin is an error, because the importing configuration decides where
# packages come from.
@usage r#'long_help #"""
Print the configured `nix:` packages as a NixOS module

Prints a module that adds each package to `environment.systemPackages`,
without running Nix. Import it into a NixOS configuration; packages resolve
against that configuration's `pkgs`. Entries for another OS or environment,
and entries with `state = "absent"`, are left out. Only shorthand
attributes such as `nix:ripgrep` can be exported: a flake reference or a
version pin is an error, because the importing configuration decides where
packages come from.
"""#'#
@usage 'flag --format help="Output format" required=#true {
                arg <FORMAT> {
                    choices nix
                }
            }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise bootstrap packages export --format nix > packages.nix" help="Write the module to a file you can import from a NixOS configuration"'
export def "mise bootstrap packages export" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --format: string@[nix],          # Output format
]: nothing -> string {
    ^mise bootstrap packages export ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --format: $format
    })
}

# Record installed Homebrew formulae in `[bootstrap.packages]`
#
# Adds a `brew:` entry for each linked formula you installed yourself,
# skipping formulae that were installed only as dependencies; `--all`
# includes those too. Formulae from third-party taps are written with their
# full name, and each tap gets a `[bootstrap.brew.taps]` entry with the URL
# already in your config or the default GitHub URL. Writes the local config
# unless you pass `-g`, `-e`, or `-p`.
@usage 'long_help #"""
Record installed Homebrew formulae in `[bootstrap.packages]`

Adds a `brew:` entry for each linked formula you installed yourself,
skipping formulae that were installed only as dependencies; `--all`
includes those too. Formulae from third-party taps are written with their
full name, and each tap gets a `[bootstrap.brew.taps]` entry with the URL
already in your config or the default GitHub URL. Writes the local config
unless you pass `-g`, `-e`, or `-p`.
"""#'
@usage 'flag "-e --env" help="Write to the config file for this environment (mise.<ENV>.toml)" {
                conflicts "--global" "--path"
                arg <ENV>
            }'
@usage 'flag "-g --global" help="Write to the global config (~/.config/mise/config.toml)" {
                long_help #"""
Write to the global config (~/.config/mise/config.toml)

New entries go to the `write_targets.packages` file when that setting is set.
"""#
                conflicts "--env" "--path"
            }'
@usage 'flag "-m --manager" help="Package manager to import from" default=brew {
                arg <MANAGER> {
                    choices brew
                }
            }'
@usage 'flag --all help="Import every linked formula, including dependencies"'
@usage 'flag "-n --dry-run" help="Show the entries that would be written without writing them"'
@usage 'flag "-p --path --file" help="Write to this config file or directory" conflicts=--global {
                arg <PATH>
            }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise bootstrap packages import --dry-run" help="Show the entries that would be written"'
@usage 'example "mise bootstrap packages import" help="Write them to the local config"'
@usage 'example "mise bootstrap packages import --all" help="Include formulae installed as dependencies"'
@usage 'example "mise bootstrap packages import -g" help="Write to the global config"'
export def "mise bootstrap packages import" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                  # Show the entries that would be written without writing them
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --global (-g),                   # Write to the global config (~/.config/mise/config.toml)
    --manager (-m): string@[brew],   # Package manager to import from
    --all,                           # Import every linked formula, including dependencies
    --path (-p): string,             # Write to this config file or directory
]: nothing -> string {
    ^mise bootstrap packages import ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --global: $global
        --manager: $manager
        --all: $all
        --path: $path
    })
}

# Uninstall packages that no config declares
#
# For `brew` (the default), removes every linked formula that is neither
# declared nor needed by a declared formula or cask, including formulae you
# installed with Homebrew itself. Run with `--dry-run` first, or record
# existing formulae with `mise bootstrap packages import`.
#
# For `brew-cask`, removes only casks mise installed and can prove are
# unchanged. For a package plugin that supports uninstalling, removes only
# packages mise installed. A package is kept while the current config, or any
# trusted config mise has tracked, still declares it.
@usage 'long_help #"""
Uninstall packages that no config declares

For `brew` (the default), removes every linked formula that is neither
declared nor needed by a declared formula or cask, including formulae you
installed with Homebrew itself. Run with `--dry-run` first, or record
existing formulae with `mise bootstrap packages import`.

For `brew-cask`, removes only casks mise installed and can prove are
unchanged. For a package plugin that supports uninstalling, removes only
packages mise installed. A package is kept while the current config, or any
trusted config mise has tracked, still declares it.
"""#'
@usage 'flag "-m --manager" help="Package manager to prune: `brew`, `brew-cask`, or a package plugin" default=brew {
                arg <MANAGER>
            }'
@usage 'flag "-n --dry-run" help="Show what would be removed without removing anything"'
@usage 'flag "-y --yes" help="Skip the confirmation prompt"'
@usage r#'flag --force help="Remove `brew-cask` casks that mise installed even when it cannot prove they are unchanged, such as self-updating apps or casks with install scripts" {
                long_help #"""
Remove `brew-cask` casks that mise installed even when it cannot prove they are unchanged, such as self-updating apps or casks with install scripts

mise removes the files it recorded installing that are still in place, but not what a cask's own install scripts created.
"""#
            }'#
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise bootstrap packages prune --dry-run" help="Preview which Homebrew formulae would be removed"'
@usage 'example "mise bootstrap packages prune --yes" help="Remove them without a prompt"'
@usage 'example "mise bootstrap packages prune --manager brew-cask --dry-run" help="Preview which casks would be removed"'
@usage 'example "mise bootstrap packages prune --manager vscode --dry-run" help="Preview removals for a package plugin named vscode"'
export def "mise bootstrap packages prune" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --force,                         # Remove `brew-cask` casks that mise installed even when it cannot prove they are unchanged, such as self-updating apps or casks with install scripts
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                  # Show what would be removed without removing anything
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --manager (-m): string,          # Package manager to prune: `brew`, `brew-cask`, or a package plugin
]: nothing -> string {
    ^mise bootstrap packages prune ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --force: $force
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --manager: $manager
    })
}

# Show the state of packages from `[bootstrap.packages]`
@usage 'alias ls list'
@usage 'flag "-J --json" help="Output in JSON format"'
@usage 'flag --missing help="Exit with status 1 if any package differs from the config (all are still listed)"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise bootstrap packages status" help="List every configured package and its state"'
@usage 'example "mise bootstrap packages status --json" help="Print the state as JSON"'
@usage 'example "mise bootstrap packages status --missing" help="Exit with status 1 if any package differs from the config"'
@usage 'output json framing=json select=--json'
export def "mise bootstrap packages status" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --missing,                       # Exit with status 1 if any package differs from the config (all are still listed)
] {
    ^mise bootstrap packages status --json ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --missing: $missing
    }) | from json
}

# Upgrade installed packages from `[bootstrap.packages]`
#
# Refreshes package manager metadata, then upgrades the configured packages
# that are already installed. Each manager decides which version is current.
# Version pins in config are honored where the manager can install them;
# other pinned entries are skipped with a warning. Packages that are not
# installed yet are skipped; install them with `mise bootstrap packages apply`.
# See https://mise.jdx.dev/bootstrap/packages/ for what each manager does.
#
# Name packages as `manager:package` to upgrade only those.
@usage 'alias up'
@usage 'long_help #"""
Upgrade installed packages from `[bootstrap.packages]`

Refreshes package manager metadata, then upgrades the configured packages
that are already installed. Each manager decides which version is current.
Version pins in config are honored where the manager can install them;
other pinned entries are skipped with a warning. Packages that are not
installed yet are skipped; install them with `mise bootstrap packages apply`.
See https://mise.jdx.dev/bootstrap/packages/ for what each manager does.

Name packages as `manager:package` to upgrade only those.
"""#'
@usage 'flag "-m --manager" help="Only upgrade packages for this built-in or plugin manager" {
                arg <MANAGER>
            }'
@usage 'flag "-n --dry-run" help="Show what would change without changing anything"'
@usage 'flag "-y --yes" help="Skip the confirmation prompt"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[PACKAGE]…" help="Packages as `manager:package`; defaults to every package in `[bootstrap.packages]`" required=#false var=#true'
@usage 'example "mise bootstrap packages upgrade --dry-run" help="Show what would be upgraded"'
@usage 'example "mise bootstrap packages upgrade" help="Upgrade every configured package that is already installed"'
@usage 'example "mise bootstrap packages upgrade --manager apt --yes" help="Upgrade only apt packages, without a prompt"'
@usage 'example "mise bootstrap packages upgrade brew:postgresql@17" help="Upgrade one Homebrew formula"'
export def "mise bootstrap packages upgrade" [
    ...package: string,              # Packages as `manager:package`; defaults to every package in `[bootstrap.packages]`
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                  # Show what would change without changing anything
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --manager (-m): string,          # Only upgrade packages for this built-in or plugin manager
]: nothing -> string {
    ^mise bootstrap packages upgrade ...(nus argv [...$package] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --manager: $manager
    })
}

# Add packages to `[bootstrap.packages]` and install them
#
# Like `mise use` for tools: writes a `"manager:package" = "version"` entry to
# the local mise.toml (or the global config with `-g`), then installs anything
# missing. If the manager is not available on this machine, such as `apt:` on
# macOS, the entry is written without installing.
#
# Pin a version with `@`, as in `apt:curl@8.5.0-2`; without `@`, or with
# `@latest`, the entry is `"latest"`. Homebrew puts versions in formula and
# cask names (`brew:postgresql@17`, `brew-cask:temurin@17`), so there `@` is
# part of the name. mas takes numeric App Store IDs and nix takes attribute
# paths or flake references, so neither accepts `@version`. aur, flatpak,
# flatpak-user, pacman, and snap accept `@version` but cannot install a pin,
# so installing skips those entries with a warning.
@usage 'alias u'
@usage 'long_help #"""
Add packages to `[bootstrap.packages]` and install them

Like `mise use` for tools: writes a `"manager:package" = "version"` entry to
the local mise.toml (or the global config with `-g`), then installs anything
missing. If the manager is not available on this machine, such as `apt:` on
macOS, the entry is written without installing.

Pin a version with `@`, as in `apt:curl@8.5.0-2`; without `@`, or with
`@latest`, the entry is `"latest"`. Homebrew puts versions in formula and
cask names (`brew:postgresql@17`, `brew-cask:temurin@17`), so there `@` is
part of the name. mas takes numeric App Store IDs and nix takes attribute
paths or flake references, so neither accepts `@version`. aur, flatpak,
flatpak-user, pacman, and snap accept `@version` but cannot install a pin,
so installing skips those entries with a warning.
"""#'
@usage 'flag "-e --env" help="Write to the config file for this environment (mise.<ENV>.toml)" {
                conflicts "--global" "--path"
                arg <ENV>
            }'
@usage 'flag "-g --global" help="Write to the global config (~/.config/mise/config.toml) instead of the local one" {
                long_help #"""
Write to the global config (~/.config/mise/config.toml) instead of the local one

New entries go to the `write_targets.packages` file when that setting is set.
"""#
            }'
@usage 'flag "-n --dry-run" help="Show what would change without writing config or installing"'
@usage 'flag "-p --path --file" help="Write to this config file or directory" conflicts=--global {
                arg <PATH>
            }'
@usage 'flag "-y --yes" help="Skip the confirmation prompt"'
@usage 'flag --no-install help="Write the package declarations without checking or installing packages"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <PACKAGE>… help="Packages in `manager:package[@version]` form" var=#true'
@usage 'example "mise bootstrap packages use apt:curl winget:BurntSushi.ripgrep.MSVC" help="Declare apt and winget packages; each machine installs the ones it can"'
@usage 'example "mise bootstrap packages use brew:jq brew-cask:firefox" help="On macOS, add a formula and a cask"'
@usage 'example "mise bootstrap packages use -g brew:postgresql@17" help="Add a versioned Homebrew formula to the global config"'
@usage 'example "mise bootstrap packages use apt:curl@8.5.0-2" help="Pin an apt package to a version"'
export def "mise bootstrap packages use" [
    ...package: string,              # Packages in `manager:package[@version]` form
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                  # Show what would change without writing config or installing
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --global (-g),                   # Write to the global config (~/.config/mise/config.toml) instead of the local one
    --path (-p): string,             # Write to this config file or directory
    --no-install,                    # Write the package declarations without checking or installing packages
]: nothing -> string {
    ^mise bootstrap packages use ...(nus argv [...$package] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --global: $global
        --path: $path
        --no-install: $no_install
    })
}

# Print the `opt` path of an installed Homebrew formula
#
# Prints a path such as /opt/homebrew/opt/openssl@3 that keeps pointing at
# the installed version across upgrades. Name the formula as `brew:<formula>`
# or `brew:<owner>/<tap>/<formula>`, using its installed name; aliases are not
# resolved, and a tap-qualified name matches by formula name only. The
# command does not read mise config files, so only environment variables and
# global flags apply. If the formula is not installed, it prints nothing and
# exits with a nonzero status. Works on macOS on Apple silicon and on Linux
# (x86_64 and arm64).
@usage 'long_help #"""
Print the `opt` path of an installed Homebrew formula

Prints a path such as /opt/homebrew/opt/openssl@3 that keeps pointing at
the installed version across upgrades. Name the formula as `brew:<formula>`
or `brew:<owner>/<tap>/<formula>`, using its installed name; aliases are not
resolved, and a tap-qualified name matches by formula name only. The
command does not read mise config files, so only environment variables and
global flags apply. If the formula is not installed, it prints nothing and
exits with a nonzero status. Works on macOS on Apple silicon and on Linux
(x86_64 and arm64).
"""#'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <PACKAGE> help="Formula to locate, as `brew:<formula>` or `brew:<owner>/<tap>/<formula>`"'
@usage r#'example #"""
if root="$(mise bootstrap packages where brew:unzip)"; then
  export PATH="$root/bin:$PATH"
fi
"""# help="Put a formula's bin directory on PATH when it is installed"'#
export def "mise bootstrap packages where" [
    package: string,                 # Formula to locate, as `brew:<formula>` or `brew:<owner>/<tap>/<formula>`
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise bootstrap packages where ...(nus argv [$package] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Show what applying bootstrap resources would change
#
# Covers accounts, packages, files and directories, system and user services,
# the firewall, and Compose projects, in dependency order. Repositories,
# dotfiles, shell activation, macOS defaults, LaunchAgents, systemd user
# units, the login shell, tools, hooks, and the `bootstrap` task are not
# planned; preview the whole run with `mise bootstrap --dry-run`.
@usage 'long_help #"""
Show what applying bootstrap resources would change

Covers accounts, packages, files and directories, system and user services,
the firewall, and Compose projects, in dependency order. Repositories,
dotfiles, shell activation, macOS defaults, LaunchAgents, systemd user
units, the login shell, tools, hooks, and the `bootstrap` task are not
planned; preview the whole run with `mise bootstrap --dry-run`.
"""#'
@usage 'flag "-J --json" help="Output a stable machine-readable plan in JSON format"'
@usage r#'flag --detailed-exitcode help="Exit 0 if nothing would change, 2 if something would, 1 on errors or unknown state" {
            long_help #"""
Exit 0 if nothing would change, 2 if something would, 1 on errors or unknown state

A resource's state is unknown when mise cannot reach its declared state on its own, for example a package whose manager is not available on this machine or cannot install the pinned version, or a service whose unit does not exist.
"""#
        }'#
@usage 'flag --prompt-secrets help="Prompt securely for missing bootstrap secret inputs"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise bootstrap plan" help="Show the planned changes"'
@usage 'example "mise bootstrap plan --json" help="Print the plan as JSON"'
@usage 'example "mise bootstrap plan --detailed-exitcode" help="Exit with status 2 if anything would change"'
@usage 'output json framing=json select=--json'
export def "mise bootstrap plan" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --prompt-secrets,                # Prompt securely for missing bootstrap secret inputs
    --detailed-exitcode,             # Exit 0 if nothing would change, 2 if something would, 1 on errors or unknown state
] {
    ^mise bootstrap plan --json ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --prompt-secrets: $prompt_secrets
        --detailed-exitcode: $detailed_exitcode
    }) | from json
}

# Manage package manager plugins declared in `[bootstrap.plugins]`
#
# A package plugin adds a package manager, such as one for VS Code extensions,
# that `[bootstrap.packages]` entries can use. `mise bootstrap` installs
# plugins before packages; when you run the narrower commands, run
# `plugins apply` before `packages apply`. Installing a plugin does not
# install its packages.
@usage 'long_help #"""
Manage package manager plugins declared in `[bootstrap.plugins]`

A package plugin adds a package manager, such as one for VS Code extensions,
that `[bootstrap.packages]` entries can use. `mise bootstrap` installs
plugins before packages; when you run the narrower commands, run
`plugins apply` before `packages apply`. Installing a plugin does not
install its packages.
"""#'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise bootstrap plugins" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise bootstrap plugins ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Install package manager plugins declared in `[bootstrap.plugins]`
#
# It does not ask for confirmation.
@usage 'long_help #"""
Install package manager plugins declared in `[bootstrap.plugins]`

It does not ask for confirmation.
"""#'
@usage 'flag "-n --dry-run" help="Show which plugins would be installed without installing them"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise bootstrap plugins apply" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                  # Show which plugins would be installed without installing them
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise bootstrap plugins apply ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Show whether declared package manager plugins are installed
@usage 'flag --missing help="Exit with status 1 if a declared plugin is not installed"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise bootstrap plugins status" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --missing,                       # Exit with status 1 if a declared plugin is not installed
]: nothing -> string {
    ^mise bootstrap plugins status ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --missing: $missing
    })
}

# Bootstrap one or more machines over SSH
#
# Packs a local project directory, copies it to each target, stages mise
# there, and runs `mise bootstrap`. The directory is `--source`. Without it,
# an inventory host uses its own `source`, then the one in
# `[bootstrap.remote]`, then the current directory; a `--host` target uses
# the current directory. Pick targets by name, `--tag`, or `--all` from
# `[bootstrap.remote.hosts]`, or give any SSH destination with `--host`.
#
# Targets need a POSIX shell plus `tar`, `mktemp`, `cksum`, and `uname`;
# Windows targets are not supported. `--dry-run` still connects, uploads, and
# inspects each target, but changes nothing there. With `--adopt`, each target
# adopts the repository as `mise bootstrap --adopt` does, instead of receiving
# a project directory.
#
# The `--github-relay-*` flags let targets read private GitHub repositories
# through this machine's credentials for the length of the run, without
# copying a token to them. See https://mise.jdx.dev/bootstrap/github-relay.html.
@usage r#'long_help #"""
Bootstrap one or more machines over SSH

Packs a local project directory, copies it to each target, stages mise
there, and runs `mise bootstrap`. The directory is `--source`. Without it,
an inventory host uses its own `source`, then the one in
`[bootstrap.remote]`, then the current directory; a `--host` target uses
the current directory. Pick targets by name, `--tag`, or `--all` from
`[bootstrap.remote.hosts]`, or give any SSH destination with `--host`.

Targets need a POSIX shell plus `tar`, `mktemp`, `cksum`, and `uname`;
Windows targets are not supported. `--dry-run` still connects, uploads, and
inspects each target, but changes nothing there. With `--adopt`, each target
adopts the repository as `mise bootstrap --adopt` does, instead of receiving
a project directory.

The `--github-relay-*` flags let targets read private GitHub repositories
through this machine's credentials for the length of the run, without
copying a token to them. See https://mise.jdx.dev/bootstrap/github-relay.html.
"""#'#
@usage 'flag --adopt help="Adopt global configuration or shared dotfile history on each target" {
            conflicts "--source" "--copy-link" "--copy-links" "--exclude"
            arg "<GIT_URL|OWNER/REPO>"
        }'
@usage 'flag --all help="Select every inventory host"'
@usage 'flag --bootstrap-command help="Shell command, run on each target, that installs mise and puts it on PATH" {
            conflicts "--mise-bin" "--remote-mise" "--install-mise"
            arg <COMMAND>
        }'
@usage 'flag --connect-timeout help="SSH connection timeout in seconds" default="10" {
            arg <SECONDS>
        }'
@usage 'flag --copy-link help="Copy the target of this source-relative symbolic link instead of the link; repeat for more" var=#true {
            arg <PATH>
        }'
@usage 'flag --copy-links help="Copy the targets of every symbolic link in the source instead of the links"'
@usage 'flag --exclude help="Another pattern to leave out of the archive; repeat for more" var=#true {
            arg <PATTERN>
        }'
@usage 'flag --fail-fast help="Stop after the first failed target"'
@usage 'flag --force-dotfiles help="Overwrite files on each target that conflict with whole-file dotfile entries"'
@usage 'flag --host help="SSH destination that is not in the inventory (`[user@]host`); repeat for more" var=#true {
            arg "<[USER@]HOST>"
        }'
@usage 'flag "-i --identity-file" help="SSH identity file, overriding the inventory and SSH config" {
            arg <PATH>
        }'
@usage 'flag "-n --dry-run" help="Show what would change on each target without changing it" {
            long_help #"""
Show what would change on each target without changing it

It still connects to each target, uploads the project, stages mise, and inspects the target.
"""#
        }'
@usage 'flag --install-mise help="Install the provisioned mise on each host instead of only staging it" require_equals=#true value_optional=#true default_missing="~/.local/bin/mise" {
            long_help #"""
Install the provisioned mise on each host instead of only staging it

Defaults to `~/.local/bin/mise`; pass `--install-mise=<PATH>` for another path.
"""#
            conflicts "--remote-mise" "--bootstrap-command" "--no-install-mise"
            arg "[PATH]" required=#false var_min=0 var_max=1
        }'
@usage 'flag --keep-staging help="Keep the remote staging directory for debugging"'
@usage 'flag --mise-bin help="Upload this local mise executable, for platforms without an official release binary" {
            conflicts "--remote-mise" "--bootstrap-command"
            arg <PATH>
        }'
@usage 'flag --no-install-mise help="Do not install mise on the host, even when the selected hosts configure it"'
@usage 'flag --only help="Run only these parts on each target" var=#true conflicts=--skip {
            long_help #"""
Run only these parts on each target

Repeat the flag or separate parts with commas. Cannot be combined with `--skip`.
"""#
            arg <PART> delimiter=, {
                choices {
                    choice plugins
                    choice packages
                    choice accounts
                    choice files
                    choice services
                    choice firewall
                    choice compose
                    choice repos
                    choice dotfiles
                    choice mise-shell-activate {
                        alias shell hide=#true
                    }
                    choice macos-defaults {
                        alias defaults hide=#true
                    }
                    choice macos-launchd-agents {
                        alias launchd hide=#true
                    }
                    choice linux-systemd-units {
                        alias systemd hide=#true
                    }
                    choice user
                    choice tools
                    choice task
                    choice final-hook
                }
            }
        }'
@usage 'flag --port help="SSH port, overriding the inventory and SSH config" {
            arg <PORT>
        }'
@usage 'flag --prompt-secrets help="Prompt securely for missing secret inputs on the remote host"'
@usage 'flag --remote-env help="Config environments to load on each target; repeat or separate with commas (for example, ci,dotfiles)" var=#true {
            arg <ENV> delimiter=,
        }'
@usage 'flag --remote-mise help="Existing mise executable name or path; relative paths use the staged project" {
            conflicts "--mise-bin" "--bootstrap-command" "--install-mise"
            arg <COMMAND>
        }'
@usage 'flag --skip help="Skip these parts on each target" var=#true {
            long_help #"""
Skip these parts on each target

Repeat the flag or separate parts with commas. Cannot be combined with `--only`.
"""#
            arg <PART> delimiter=, {
                choices {
                    choice plugins
                    choice packages
                    choice accounts
                    choice files
                    choice services
                    choice firewall
                    choice compose
                    choice repos
                    choice dotfiles
                    choice mise-shell-activate {
                        alias shell hide=#true
                    }
                    choice macos-defaults {
                        alias defaults hide=#true
                    }
                    choice macos-launchd-agents {
                        alias launchd hide=#true
                    }
                    choice linux-systemd-units {
                        alias systemd hide=#true
                    }
                    choice user
                    choice tools
                    choice task
                    choice final-hook
                }
            }
        }'
@usage 'flag --source help="Local directory to archive and send to each target" {
            arg <DIR>
        }'
@usage 'flag --ssh-option help="OpenSSH `-o` option; repeat for multiple options" var=#true {
            arg <OPTION>
        }'
@usage 'flag --tag help="Select configured hosts with this tag; repeat to match any tag" var=#true {
            arg <TAG>
        }'
@usage 'flag --update help="Refresh package metadata and update repositories on each target"'
@usage 'flag "-y --yes" help="Skip confirmation prompts on each target"'
@usage 'flag --github-relay-read-only help="Borrow read-only GitHub access for this run (Linux and macOS only)" {
            long_help #"""
Borrow read-only GitHub access for this run (Linux and macOS only)

Needs exactly one of `--github-relay-repo` or `--github-relay-all-repos`.
"""#
        }'
@usage 'flag --github-relay-repo help="Repository the targets may read through the relay; repeat for more (needs `--github-relay-read-only`)" var=#true {
            arg "<OWNER/REPO>"
        }'
@usage 'flag --github-relay-all-repos help="Let targets read every repository your local credentials can read (needs `--github-relay-read-only`)"'
@usage 'flag --github-relay-log-requests help="Log sanitized relay requests on local stderr (needs `--github-relay-read-only`)" conflicts=--github-relay-no-log-requests'
@usage 'flag --github-relay-no-log-requests help="Turn off request logging, overriding the `github_relay` settings (needs `--github-relay-read-only`)"'
@usage 'flag --github-relay-log-format help="Relay log and summary format, `text` or `jsonl` (needs `--github-relay-read-only`)" {
            arg <FORMAT>
        }'
@usage 'flag --github-relay-max-duration help="End borrowed access after a duration such as `1h`; `0s` lasts the whole run (needs `--github-relay-read-only`)" {
            arg <DURATION>
        }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[TARGET]…" help="Inventory host names from `[bootstrap.remote.hosts]`" required=#false var=#true'
@usage 'example "mise bootstrap remote --host devbox --dry-run" help="Preview a run on a host that is not in the inventory"'
@usage 'example "mise bootstrap remote cache" help="Bootstrap one inventory host"'
@usage 'example "mise bootstrap remote --tag canary --yes" help="Bootstrap every inventory host tagged canary, without prompts"'
@usage 'example "mise bootstrap remote --all --fail-fast" help="Bootstrap every inventory host and stop at the first failure"'
@usage 'example "mise bootstrap remote --host ubuntu@cache.example.com -i ~/.ssh/mise-cache --install-mise" help="Leave mise installed on the host after the run"'
@usage 'example "mise bootstrap remote --host devbox --github-relay-read-only --github-relay-repo example/setup" help="Let the host read one private GitHub repository during the run"'
@usage 'complete path type=path'
@usage 'complete dir type=dir'
export def "mise bootstrap remote" [
    ...target: string,                                                                                                                                                                                       # Inventory host names from `[bootstrap.remote.hosts]`
    --cd (-C): path@"nus complete",                                                                                                                                                                          # Run as if mise were started in DIR
    --env_ (-E): list<string>,                                                                                                                                                                               # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                                                                                                                                                                                     # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                                                                                                                                                                                          # Show what would change on each target without changing it
    --quiet (-q),                                                                                                                                                                                            # Suppress non-error messages
    --verbose (-v): int,                                                                                                                                                                                     # Show extra output (use -vv for even more)
    --yes (-y),                                                                                                                                                                                              # Answer yes to all confirmation prompts
    --raw,                                                                                                                                                                                                   # Connect tasks and install commands directly to the terminal
    --locked,                                                                                                                                                                                                # Require download URLs from the lockfile when installing
    --silent,                                                                                                                                                                                                # Suppress all task output and mise non-error messages
    --adopt: string,                                                                                                                                                                                         # Adopt global configuration or shared dotfile history on each target
    --force-dotfiles,                                                                                                                                                                                        # Overwrite files on each target that conflict with whole-file dotfile entries
    --only: list<string>@[plugins packages accounts files services firewall compose repos dotfiles mise-shell-activate macos-defaults macos-launchd-agents linux-systemd-units user tools task final-hook],  # Run only these parts on each target
    --prompt-secrets,                                                                                                                                                                                        # Prompt securely for missing secret inputs on the remote host
    --skip: list<string>@[plugins packages accounts files services firewall compose repos dotfiles mise-shell-activate macos-defaults macos-launchd-agents linux-systemd-units user tools task final-hook],  # Skip these parts on each target
    --update,                                                                                                                                                                                                # Refresh package metadata and update repositories on each target
    --all,                                                                                                                                                                                                   # Select every inventory host
    --bootstrap-command: string,                                                                                                                                                                             # Shell command, run on each target, that installs mise and puts it on PATH
    --connect-timeout: string,                                                                                                                                                                               # SSH connection timeout in seconds
    --copy-link: list<path>@"nus complete",                                                                                                                                                                  # Copy the target of this source-relative symbolic link instead of the link; repeat for more
    --copy-links,                                                                                                                                                                                            # Copy the targets of every symbolic link in the source instead of the links
    --exclude: list<string>,                                                                                                                                                                                 # Another pattern to leave out of the archive; repeat for more
    --fail-fast,                                                                                                                                                                                             # Stop after the first failed target
    --host: list<string>,                                                                                                                                                                                    # SSH destination that is not in the inventory (`[user@]host`); repeat for more
    --identity-file (-i): path@"nus complete",                                                                                                                                                               # SSH identity file, overriding the inventory and SSH config
    --install-mise: path@"nus complete",                                                                                                                                                                     # Install the provisioned mise on each host instead of only staging it
    --keep-staging,                                                                                                                                                                                          # Keep the remote staging directory for debugging
    --mise-bin: path@"nus complete",                                                                                                                                                                         # Upload this local mise executable, for platforms without an official release binary
    --no-install-mise,                                                                                                                                                                                       # Do not install mise on the host, even when the selected hosts configure it
    --port: string,                                                                                                                                                                                          # SSH port, overriding the inventory and SSH config
    --remote-env: list<string>,                                                                                                                                                                              # Config environments to load on each target; repeat or separate with commas (for example, ci,dotfiles)
    --remote-mise: string,                                                                                                                                                                                   # Existing mise executable name or path; relative paths use the staged project
    --source: path@"nus complete",                                                                                                                                                                           # Local directory to archive and send to each target
    --ssh-option: list<string>,                                                                                                                                                                              # OpenSSH `-o` option; repeat for multiple options
    --tag: list<string>,                                                                                                                                                                                     # Select configured hosts with this tag; repeat to match any tag
    --github-relay-read-only,                                                                                                                                                                                # Borrow read-only GitHub access for this run (Linux and macOS only)
    --github-relay-repo: list<string>,                                                                                                                                                                       # Repository the targets may read through the relay; repeat for more (needs `--github-relay-read-only`)
    --github-relay-all-repos,                                                                                                                                                                                # Let targets read every repository your local credentials can read (needs `--github-relay-read-only`)
    --github-relay-log-requests,                                                                                                                                                                             # Log sanitized relay requests on local stderr (needs `--github-relay-read-only`)
    --github-relay-no-log-requests,                                                                                                                                                                          # Turn off request logging, overriding the `github_relay` settings (needs `--github-relay-read-only`)
    --github-relay-log-format: string,                                                                                                                                                                       # Relay log and summary format, `text` or `jsonl` (needs `--github-relay-read-only`)
    --github-relay-max-duration: string,                                                                                                                                                                     # End borrowed access after a duration such as `1h`; `0s` lasts the whole run (needs `--github-relay-read-only`)
]: nothing -> string {
    ^mise bootstrap remote ...(nus argv [...$target] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --adopt: $adopt
        --force-dotfiles: $force_dotfiles
        --only: $only
        --prompt-secrets: $prompt_secrets
        --skip: $skip
        --update: $update
        --all: $all
        --bootstrap-command: $bootstrap_command
        --connect-timeout: $connect_timeout
        --copy-link: $copy_link
        --copy-links: $copy_links
        --exclude: $exclude
        --fail-fast: $fail_fast
        --host: $host
        --identity-file: $identity_file
        --install-mise: $install_mise
        --keep-staging: $keep_staging
        --mise-bin: $mise_bin
        --no-install-mise: $no_install_mise
        --port: $port
        --remote-env: $remote_env
        --remote-mise: $remote_mise
        --source: $source
        --ssh-option: $ssh_option
        --tag: $tag
        --github-relay-read-only: $github_relay_read_only
        --github-relay-repo: $github_relay_repo
        --github-relay-all-repos: $github_relay_all_repos
        --github-relay-log-requests: $github_relay_log_requests
        --github-relay-no-log-requests: $github_relay_no_log_requests
        --github-relay-log-format: $github_relay_log_format
        --github-relay-max-duration: $github_relay_max_duration
    })
}

# Manage Git repositories from `[bootstrap.repos]`
#
# A repository with uncommitted changes, a different origin, or something
# other than a Git checkout at its path stops `apply` and `update` before
# anything changes. Pass `--skip-dirty` to skip repositories with uncommitted
# changes and continue with the rest.
@usage 'long_help #"""
Manage Git repositories from `[bootstrap.repos]`

A repository with uncommitted changes, a different origin, or something
other than a Git checkout at its path stops `apply` and `update` before
anything changes. Pass `--skip-dirty` to skip repositories with uncommitted
changes and continue with the rest.
"""#'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise bootstrap repos" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise bootstrap repos ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Clone missing Git repositories and check out configured refs
@usage 'flag "-n --dry-run" help="Show what would change without changing anything"'
@usage 'flag "-y --yes" help="Skip the confirmation prompt"'
@usage 'flag --skip-dirty help="Skip repositories with local changes instead of failing"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise bootstrap repos apply" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                  # Show what would change without changing anything
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --skip-dirty,                    # Skip repositories with local changes instead of failing
]: nothing -> string {
    ^mise bootstrap repos apply ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --skip-dirty: $skip_dirty
    })
}

# Run a command in each configured Git repository
#
# Put the command and its arguments after `--`. Paths before `--` select
# repositories. The command runs directly, without a shell, so pipes and `&&`
# do not work. Missing or conflicting repositories are skipped with a
# warning. Use `--continue-on-error` to visit the rest after a failure.
@usage 'long_help #"""
Run a command in each configured Git repository

Put the command and its arguments after `--`. Paths before `--` select
repositories. The command runs directly, without a shell, so pipes and `&&`
do not work. Missing or conflicting repositories are skipped with a
warning. Use `--continue-on-error` to visit the rest after a failure.
"""#'
@usage 'flag "-c --continue-on-error" help="Continue running in other repositories after a command fails"'
@usage 'flag "-n --dry-run" help="Print the commands that would run without running them"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[PATH]…" help="Run only in repositories at these paths, as written in config or expanded" required=#false var=#true'
@usage 'arg "<-- COMMAND>…" help="Command and arguments to run in each repository" var=#true'
@usage 'example "mise bootstrap repos exec -- git status --short" help="Show uncommitted changes in every repository"'
@usage 'example "mise bootstrap repos exec ~/src/mise -- git log -1" help="Run a command in one repository"'
@usage 'example "mise bootstrap repos exec --continue-on-error -- git fetch" help="Fetch every repository, even after one fails"'
export def "mise bootstrap repos exec" [
    ...path: string,                 # Run only in repositories at these paths, as written in config or expanded
    --continue-on-error (-c),        # Continue running in other repositories after a command fails
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                  # Print the commands that would run without running them
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise bootstrap repos exec ...(nus argv [...$path] {
        --continue-on-error: $continue_on_error
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Show the state of Git repositories from `[bootstrap.repos]`
@usage 'flag "-J --json" help="Output in JSON format"'
@usage 'flag --missing help="Exit with status 1 if any repository differs from the config (all are still listed)"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'output json framing=json select=--json'
export def "mise bootstrap repos status" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --missing,                       # Exit with status 1 if any repository differs from the config (all are still listed)
] {
    ^mise bootstrap repos status --json ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --missing: $missing
    }) | from json
}

# Clone missing Git repositories and fast-forward the rest
#
# For a repository without a `ref`, fetches and fast-forwards the current
# branch; one with a detached HEAD is skipped with a warning. A repository
# with a `ref` is checked out at that ref.
@usage 'long_help #"""
Clone missing Git repositories and fast-forward the rest

For a repository without a `ref`, fetches and fast-forwards the current
branch; one with a detached HEAD is skipped with a warning. A repository
with a `ref` is checked out at that ref.
"""#'
@usage 'flag "-n --dry-run" help="Show what would change without changing anything"'
@usage 'flag "-y --yes" help="Skip the confirmation prompt"'
@usage 'flag --skip-dirty help="Skip repositories with local changes instead of failing"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[PATH]…" help="Only update repositories at these paths, as written in config or expanded (for example ~/src/mise)" required=#false var=#true'
@usage 'example "mise bootstrap repos update --dry-run" help="Show the Git commands that would run"'
@usage 'example "mise bootstrap repos update ~/src/mise" help="Update one repository"'
export def "mise bootstrap repos update" [
    ...path: string,                 # Only update repositories at these paths, as written in config or expanded (for example ~/src/mise)
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                  # Show what would change without changing anything
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --skip-dirty,                    # Skip repositories with local changes instead of failing
]: nothing -> string {
    ^mise bootstrap repos update ...(nus argv [...$path] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --skip-dirty: $skip_dirty
    })
}

# Inspect bootstrap secret inputs without revealing their values
#
# Secret inputs are values declared in `[bootstrap.secrets]` that file and
# dotfile templates read with `secret()`. mise reads them from environment
# variables, or prompts for missing ones with `--prompt-secrets`.
@usage 'long_help #"""
Inspect bootstrap secret inputs without revealing their values

Secret inputs are values declared in `[bootstrap.secrets]` that file and
dotfile templates read with `secret()`. mise reads them from environment
variables, or prompts for missing ones with `--prompt-secrets`.
"""#'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise bootstrap secrets" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise bootstrap secrets ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Show whether declared bootstrap secret inputs are available
@usage 'flag "-J --json" help="Output in JSON format"'
@usage 'flag --missing help="Exit with status 1 if a declared secret input is unset, empty, or not valid Unicode"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'output json framing=json select=--json'
export def "mise bootstrap secrets status" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --missing,                       # Exit with status 1 if a declared secret input is unset, empty, or not valid Unicode
] {
    ^mise bootstrap secrets status --json ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --missing: $missing
    }) | from json
}

# Manage services from `[bootstrap.services]`
#
# System-scope entries, the default for entries without `builtin`, start,
# stop, enable, disable, or mask systemd units that already exist on Linux.
# User-scope entries (`scope = "user"`, or any `builtin` service) define a
# service for the current user on every platform: a systemd user unit on
# Linux, a LaunchAgent on macOS, or a Scheduled Task on Windows. For options
# that only one platform has, see `mise bootstrap linux systemd-units` and
# `mise bootstrap macos launchd-agents`.
@usage 'long_help #"""
Manage services from `[bootstrap.services]`

System-scope entries, the default for entries without `builtin`, start,
stop, enable, disable, or mask systemd units that already exist on Linux.
User-scope entries (`scope = "user"`, or any `builtin` service) define a
service for the current user on every platform: a systemd user unit on
Linux, a LaunchAgent on macOS, or a Scheduled Task on Windows. For options
that only one platform has, see `mise bootstrap linux systemd-units` and
`mise bootstrap macos launchd-agents`.
"""#'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise bootstrap services status" help="Show the state of every declared service"'
@usage 'example "mise bootstrap services apply --dry-run" help="Show what would change"'
@usage 'example "mise bootstrap services remove mise-history" help="Uninstall a user service"'
export def "mise bootstrap services" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise bootstrap services ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Apply the service state declared in `[bootstrap.services]`
@usage 'flag "-n --dry-run" help="Show what would change without changing anything"'
@usage 'flag "-y --yes" help="Skip the confirmation prompt"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise bootstrap services apply" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                  # Show what would change without changing anything
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise bootstrap services apply ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Uninstall a user-scope service
#
# Removing a user-scope entry from config does not uninstall its systemd
# unit, LaunchAgent, or Scheduled Task. Use this command to uninstall it,
# whether or not it is still declared. If the entry is still declared, the
# next `mise bootstrap` installs it again.
#
# It removes the dev.mise.NAME.service unit or dev.mise.NAME.plist agent, so it
# also removes one that [bootstrap.linux.systemd.units] or
# [bootstrap.macos.launchd.agents] wrote under that name. It does not remove
# .timer units.
@usage 'long_help #"""
Uninstall a user-scope service

Removing a user-scope entry from config does not uninstall its systemd
unit, LaunchAgent, or Scheduled Task. Use this command to uninstall it,
whether or not it is still declared. If the entry is still declared, the
next `mise bootstrap` installs it again.

It removes the dev.mise.NAME.service unit or dev.mise.NAME.plist agent, so it
also removes one that [bootstrap.linux.systemd.units] or
[bootstrap.macos.launchd.agents] wrote under that name. It does not remove
.timer units.
"""#'
@usage 'flag "-n --dry-run" help="Show what would be removed without removing it"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <NAME> help="Name of the installed user service"'
@usage 'example "mise bootstrap services remove mise-history --dry-run" help="Preview uninstalling the user service named mise-history"'
export def "mise bootstrap services remove" [
    name: string,                    # Name of the installed user service
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                  # Show what would be removed without removing it
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise bootstrap services remove ...(nus argv [$name] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Show the state of services from `[bootstrap.services]`
@usage 'flag "-J --json" help="Output in JSON format"'
@usage 'flag --missing help="Exit with status 1 if any service differs from the config (all are still listed)"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'output json framing=json select=--json'
export def "mise bootstrap services status" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --missing,                       # Exit with status 1 if any service differs from the config (all are still listed)
] {
    ^mise bootstrap services status --json ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --missing: $missing
    }) | from json
}

# Show the state of every configured bootstrap part
#
# Lists secret inputs, packages, accounts, files and directories, services,
# the firewall, Compose projects, repositories, dotfiles, shell activation,
# macOS defaults, LaunchAgents, systemd user units, the login shell, `[tools]`,
# and the system dependencies of those tools, without changing anything.
# Checking dotfiles can render trusted templates, which may run `exec()`.
#
# `--missing` exits with status 1 if anything differs from the config; it
# still lists every entry.
@usage 'alias ls'
@usage 'long_help #"""
Show the state of every configured bootstrap part

Lists secret inputs, packages, accounts, files and directories, services,
the firewall, Compose projects, repositories, dotfiles, shell activation,
macOS defaults, LaunchAgents, systemd user units, the login shell, `[tools]`,
and the system dependencies of those tools, without changing anything.
Checking dotfiles can render trusted templates, which may run `exec()`.

`--missing` exits with status 1 if anything differs from the config; it
still lists every entry.
"""#'
@usage 'flag "-J --json" help="Output in JSON format"'
@usage 'flag --missing help="Exit with status 1 if anything differs from the config (all entries are still listed)"'
@usage 'flag --prompt-secrets help="Prompt securely for missing bootstrap secret inputs"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise bootstrap status" help="List every configured part and its state"'
@usage 'example "mise bootstrap status --missing" help="Exit with status 1 if anything differs from the config"'
@usage 'example "mise bootstrap status --json" help="Print the state as JSON"'
@usage 'output json framing=json select=--json'
export def "mise bootstrap status" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --prompt-secrets,                # Prompt securely for missing bootstrap secret inputs
    --missing,                       # Exit with status 1 if anything differs from the config (all entries are still listed)
] {
    ^mise bootstrap status --json ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --prompt-secrets: $prompt_secrets
        --missing: $missing
    }) | from json
}

# Remove what a config environment's bootstrap sections created
#
# Removes the files, directories, user services, systemd user units, and
# dotfile entries and edits that the named environments declare. Each named
# environment's config is loaded for this command even when `-E` or
# `MISE_ENV` does not select it.
#
# mise plans the removal from the current config, not from a record of past
# runs, so keep the environment's config files until cleanup is done. Anything
# another selected config still declares is kept, and so is anything changed
# since it was applied unless you pass `--force`. A directory is removed only
# if it is empty afterward. Dotfile sources and config entries are left in
# place.
#
# It asks before removing anything unless `--yes`, `MISE_YES`, or the `yes`
# setting is set, and fails when there is no terminal to ask. mise turns on
# the `yes` setting when `CI` is set.
#
# Packages, repositories, and Compose projects are not removed; the output
# says how to clean them up. Accounts, system services, the firewall, and
# other sections are left alone.
@usage r#'long_help #"""
Remove what a config environment's bootstrap sections created

Removes the files, directories, user services, systemd user units, and
dotfile entries and edits that the named environments declare. Each named
environment's config is loaded for this command even when `-E` or
`MISE_ENV` does not select it.

mise plans the removal from the current config, not from a record of past
runs, so keep the environment's config files until cleanup is done. Anything
another selected config still declares is kept, and so is anything changed
since it was applied unless you pass `--force`. A directory is removed only
if it is empty afterward. Dotfile sources and config entries are left in
place.

It asks before removing anything unless `--yes`, `MISE_YES`, or the `yes`
setting is set, and fails when there is no terminal to ask. mise turns on
the `yes` setting when `CI` is set.

Packages, repositories, and Compose projects are not removed; the output
says how to clean them up. Accounts, system services, the firewall, and
other sections are left alone.
"""#'#
@usage 'flag "-f --force" help="Remove targets that changed since they were applied"'
@usage 'flag "-n --dry-run" help="Show what would be removed without removing anything"'
@usage 'flag "-y --yes" help="Skip the confirmation prompt"'
@usage 'flag --prompt-secrets help="Prompt securely for missing bootstrap secret inputs"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <ENV>… help="Config environments whose resources should be removed" var=#true'
@usage r#'example "mise bootstrap unapply ssh --dry-run" help="Preview what removing the `ssh` environment's resources would do"'#
@usage 'example "mise bootstrap unapply ssh" help="Remove them after a confirmation prompt"'
@usage 'example "mise bootstrap unapply ssh gpg --yes" help="Remove the resources of two environments without a prompt"'
export def "mise bootstrap unapply" [
    ...env_: string,                 # Config environments whose resources should be removed
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --force (-f),                    # Remove targets that changed since they were applied
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                  # Show what would be removed without removing anything
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --prompt-secrets,                # Prompt securely for missing bootstrap secret inputs
]: nothing -> string {
    ^mise bootstrap unapply ...(nus argv [...$env_] {
        --cd: $cd
        --env: $env_
        --force: $force
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --prompt-secrets: $prompt_secrets
    })
}

# Manage your login shell from `[bootstrap.user]`
#
# Run it as the user whose shell should change. The new shell applies to
# future logins, not to the shell running this command.
@usage 'long_help #"""
Manage your login shell from `[bootstrap.user]`

Run it as the user whose shell should change. The new shell applies to
future logins, not to the shell running this command.
"""#'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise bootstrap user" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise bootstrap user ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Set your login shell from `[bootstrap.user]`
@usage 'flag "-n --dry-run" help="Show what would change without changing anything"'
@usage 'flag "-y --yes" help="Skip the confirmation prompt"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise bootstrap user apply" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                  # Show what would change without changing anything
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise bootstrap user apply ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Show whether your login shell matches `[bootstrap.user]`
@usage 'flag "-J --json" help="Output in JSON format"'
@usage 'flag --missing help="Exit with status 1 if your login shell differs from the config"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'output json framing=json select=--json'
export def "mise bootstrap user status" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --missing,                       # Exit with status 1 if your login shell differs from the config
] {
    ^mise bootstrap user status --json ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --missing: $missing
    }) | from json
}

# Manage the mise cache
#
# The cache holds data mise can fetch or rebuild again, such as version lists and
# release metadata. With no subcommand, prints the cache directory, like
# `mise cache path`. See https://mise.jdx.dev/cache-behavior.html.
@usage 'long_help #"""
Manage the mise cache

The cache holds data mise can fetch or rebuild again, such as version lists and
release metadata. With no subcommand, prints the cache directory, like
`mise cache path`. See https://mise.jdx.dev/cache-behavior.html.
"""#'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise cache" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise cache ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Delete cached data
#
# With no arguments, deletes the whole cache directory, the cached environment,
# and every task's cached artifacts. With TOOL arguments, deletes only the cached
# data of those tools, such as their version lists. With --task, deletes only that
# task's cached artifacts. Installed tools are not removed; mise downloads or
# rebuilds what it needs again.
@usage 'alias c clean'
@usage r#'long_help #"""
Delete cached data

With no arguments, deletes the whole cache directory, the cached environment,
and every task's cached artifacts. With TOOL arguments, deletes only the cached
data of those tools, such as their version lists. With --task, deletes only that
task's cached artifacts. Installed tools are not removed; mise downloads or
rebuilds what it needs again.
"""#'#
@usage 'flag --outdate help="Mark all cache files as old" hide=#true'
@usage 'flag --task help="[experimental] Clear task artifact cache entries for a task name or pattern" {
            conflicts TOOL "--outdate"
            arg <TASK>
        }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[TOOL]…" help="Only clear the cache of these tools, such as `node`" required=#false var=#true'
@usage 'example "mise cache clear" help="Clear the whole cache"'
@usage r#'example "mise cache clear node" help="Refresh node's version list"'#
@usage r#'example "mise cache clear --task build" help="[experimental] Forget the build task's cached artifacts"'#
export def "mise cache clear" [
    ...tool: string@"nus complete",  # Only clear the cache of these tools, such as `node`
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --task: string@"nus complete",   # [experimental] Clear task artifact cache entries for a task name or pattern
]: nothing -> string {
    ^mise cache clear ...(nus argv [...$tool] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --task: $task
    })
}

# Print the cache directory path
@usage 'alias dir'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise cache path" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise cache path ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Remove cache files that have not been accessed recently
#
# Removes cache files not accessed within the `cache_prune_age` setting. Set it to
# `0s` to keep cache files indefinitely. mise also prunes the cache now and then
# on its own.
@usage 'alias p'
@usage 'long_help #"""
Remove cache files that have not been accessed recently

Removes cache files not accessed within the `cache_prune_age` setting. Set it to
`0s` to keep cache files indefinitely. mise also prunes the cache now and then
on its own.
"""#'
@usage 'flag "-v --verbose" help="Show pruned files" var=#true count=#true'
@usage 'flag --dry-run help="Show what would be pruned without deleting anything"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[TOOL]…" help="Only prune the cache of these tools, such as `node`" required=#false var=#true'
@usage 'example "mise cache prune --dry-run" help="List what would be removed"'
export def "mise cache prune" [
    ...tool: string@"nus complete",  # Only prune the cache of these tools, such as `node`
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run,                       # Show what would be pruned without deleting anything
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise cache prune ...(nus argv [...$tool] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# [experimental] Inspect artifact cache entries for a task
#
# Lists the artifact cache entries of the tasks matching TASK with their key,
# size, run time, last access, and outputs, and marks the entry that matches the
# task's current inputs. Remove entries with `mise cache clear --task TASK`. See
# https://mise.jdx.dev/tasks/caching.html#enable-artifact-caching.
@usage r#'long_help #"""
[experimental] Inspect artifact cache entries for a task

Lists the artifact cache entries of the tasks matching TASK with their key,
size, run time, last access, and outputs, and marks the entry that matches the
task's current inputs. Remove entries with `mise cache clear --task TASK`. See
https://mise.jdx.dev/tasks/caching.html#enable-artifact-caching.
"""#'#
@usage 'flag "-J --json" help="Output in JSON format"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <TASK> help="Task name or pattern to inspect"'
@usage r#'example "mise cache task build" help="List the build task's cache entries"'#
@usage 'output json framing=json select=--json'
export def "mise cache task" [
    task: string@"nus complete",     # Task name or pattern to inspect
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
] {
    ^mise cache task --json ...(nus argv [$task] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    }) | from json
}

# Generate shell completions
#
# Prints a completion script for SHELL, or with --install writes it where that
# shell loads completions from. The script asks mise for candidates as you type,
# so it also completes your project's task names and tool versions. See
# https://mise.jdx.dev/shell-setup.html#autocompletion.
@usage 'alias complete completions'
@usage r#'long_help #"""
Generate shell completions

Prints a completion script for SHELL, or with --install writes it where that
shell loads completions from. The script asks mise for candidates as you type,
so it also completes your project's task names and tool versions. See
https://mise.jdx.dev/shell-setup.html#autocompletion.
"""#'#
@usage 'flag "-s --shell" help="Shell type to generate completions for" hide=#true {
        arg <SHELL> {
            choices {
                choice bash
                choice fish
                choice nu {
                    alias nushell
                }
                choice powershell {
                    alias pwsh
                }
                choice zsh
            }
        }
    }'
@usage 'flag --include-bash-completion-lib help="No longer has any effect; kept so older setup scripts keep working" hide=#true'
@usage 'flag --usage help="No longer has any effect; kept so older setup scripts keep working" hide=#true'
@usage r#'flag --install help="Install the script where this shell looks for it, instead of printing it" effect=write {
        long_help #"""
Install the script where this shell looks for it, instead of printing it

It writes only the script file, never a shell startup file or PowerShell
profile. If your shell needs a one-time setup line, such as zsh's `fpath+=`
or PowerShell's dot-source, mise prints it for you to add.
"""#
    }'#
@usage 'flag --force help="Replace a file at the target path that mise did not write" requires=--install effect=write'
@usage r#'flag --tool help="Generate completions for a tool installed with the `packslip:` backend" {
        long_help #"""
Generate completions for a tool installed with the `packslip:` backend

TOOL is the tool or one of its executables; with --install, pass the
executable's name. The script matches the version active in the current
directory and comes from the most verifiable source its packslip offers: a
file the vendor shipped, a script derived from its CLI spec, or a command of
the tool's own. With --install, mise writes a small stub that asks mise for
the script each time the shell completes the tool, so it follows version
changes without being rewritten.
"""#
        arg <TOOL>
    }'#
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[SHELL]" help="Shell type to generate completions for (required)" required=#false required_unless=--shell {
        choices {
            choice bash
            choice fish
            choice nu {
                alias nushell
            }
            choice powershell {
                alias pwsh
            }
            choice zsh
        }
    }'
@usage 'example "mise completion zsh --install" help="Install completions for zsh; bash, fish, and powershell work the same way"'
@usage 'example "mise completion zsh" help="Print the script to inspect it or save it somewhere else"'
@usage 'example "mise completion zsh --tool hk --install" help="Install completions for hk, a tool installed with the packslip backend"'
export def "mise completion" [
    shell?: string@[bash fish nu powershell zsh],  # Shell type to generate completions for (required)
    --cd (-C): path@"nus complete",                # Run as if mise were started in DIR
    --env_ (-E): list<string>,                     # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --force,                                       # Replace a file at the target path that mise did not write
    --jobs (-j): string,                           # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                                  # Suppress non-error messages
    --tool: string@"nus complete",                 # Generate completions for a tool installed with the `packslip:` backend
    --verbose (-v): int,                           # Show extra output (use -vv for even more)
    --yes (-y),                                    # Answer yes to all confirmation prompts
    --raw,                                         # Connect tasks and install commands directly to the terminal
    --locked,                                      # Require download URLs from the lockfile when installing
    --silent,                                      # Suppress all task output and mise non-error messages
    --install,                                     # Install the script where this shell looks for it, instead of printing it
]: nothing -> string {
    ^mise completion ...(nus argv [$shell] {
        --cd: $cd
        --env: $env_
        --force: $force
        --jobs: $jobs
        --quiet: $quiet
        --tool: $tool
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --install: $install
    })
}

# Manage config files
#
# With no subcommand, lists the config files mise loads, from lowest to highest precedence, like `mise config ls`; the flags below apply to that listing.
@usage 'alias cfg toml'
@usage 'long_help #"""
Manage config files

With no subcommand, lists the config files mise loads, from lowest to highest precedence, like `mise config ls`; the flags below apply to that listing.
"""#'
@usage 'flag --truncate help="Truncate long terminal output to fit the available width" negate=--no-truncate default="true"'
@usage 'flag "-J --json" help="Output in JSON format"'
@usage 'flag --no-header help="Do not print the table header" {
        alias "--no-headers" hide=#true
    }'
@usage 'flag --tracked-configs help="List every config file mise has loaded, in any project" {
        long_help #"""
List every config file mise has loaded, in any project

mise remembers the config files it loads so `mise prune` keeps the versions
they use.
"""#
    }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'output "json" framing="json" select="--json" {
    schema "{\n  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",\n  \"type\": \"array\",\n  \"items\": {\n    \"type\": \"object\",\n    \"properties\": {\n      \"path\": {\n        \"type\": \"string\"\n      },\n      \"tools\": {\n        \"type\": \"array\",\n        \"items\": {\n          \"type\": \"string\"\n        }\n      },\n      \"override\": {\n        \"type\": \"boolean\"\n      }\n    },\n    \"required\": [\n      \"path\",\n      \"tools\",\n      \"override\"\n    ],\n    \"additionalProperties\": false\n  }\n}\n"
}'
export def "mise config" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --truncate,                      # Truncate long terminal output to fit the available width
    --no-truncate,                   # Turn off --truncate
    --no-header,                     # Do not print the table header
    --tracked-configs,               # List every config file mise has loaded, in any project
]: nothing -> table<path: string, tools: list<string>, override: bool> {
    let text = ^mise config --json ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --truncate: $truncate
        --no-truncate: $no_truncate
        --no-header: $no_header
        --tracked-configs: $tracked_configs
    })
    nus decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":\"array\",\"items\":{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"tools\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}},\"override\":{\"type\":\"boolean\"}},\"required\":[\"path\",\"tools\",\"override\"],\"additionalProperties\":false}}" { from json }
}

# Describe each key in a mise TOML file
#
# Lists every key the file sets, with its line and what it does, from the same schema
# editors use to check a config. A key mise does not read is marked, with the known key it
# most likely meant, and so is a deprecated one. Reads the highest-precedence loaded TOML
# file by default; select another with `--file`, `--global`, or `--system`.
@usage 'long_help #"""
Describe each key in a mise TOML file

Lists every key the file sets, with its line and what it does, from the same schema
editors use to check a config. A key mise does not read is marked, with the known key it
most likely meant, and so is a deprecated one. Reads the highest-precedence loaded TOML
file by default; select another with `--file`, `--global`, or `--system`.
"""#'
@usage 'flag "-f --file --path" help="Config file to read, or a directory whose config file to read" {
            long_help #"""
Config file to read, or a directory whose config file to read

Defaults to the highest-precedence loaded TOML file other than the global override files.
"""#
            arg <FILE>
        }'
@usage 'flag "-g --global" help="Read the global config file" {
            conflicts "--file" "--system"
        }'
@usage 'flag --system help="Read the system config file" {
            conflicts "--file" "--global"
        }'
@usage 'flag --override help="Read the global override file, `config.override.toml`" {
            conflicts "--file" "--global" "--system"
        }'
@usage 'flag "-J --json" help="Print the keys as JSON"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage r#'arg "[KEY]" help="Dotted key path to describe, with the keys under it; omit for the whole file" help_long=#"""
Dotted key path to describe, with the keys under it; omit for the whole file

Quote a key with a dot in its name as TOML does, inside shell quotes: `'tasks."build.sh"'`. Unquoted, `tasks.build.sh` still finds the task `build.sh` when there is no key `build` in the way.
"""# required=#false'#
@usage 'example #"""
mise config explain
~/src/app/mise.toml
   1  tools                  dev tools to use
   2  tools.node             a version of the tool, or a table with its version and options
   4  settings               mise settings
   5  settings.experimantal  not a key mise reads; did you mean experimental?
"""# help="Describe the keys of the project config"'
@usage 'example "mise config explain tasks" help="Describe only the keys under [tasks]"'
@usage 'complete file type=path'
@usage 'complete key run="mise __complete_word__ --candidates key --line={{ words | shell_join | shell_quote }}"'
@usage 'output "json" framing="json" select="--json" {
    schema "{\n  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",\n  \"title\": \"mise config explain --json\",\n  \"type\": \"array\",\n  \"items\": {\n    \"type\": \"object\",\n    \"properties\": {\n      \"key\": {\n        \"type\": \"string\"\n      },\n      \"path\": {\n        \"type\": \"array\",\n        \"items\": {\n          \"type\": \"string\"\n        }\n      },\n      \"line\": {\n        \"type\": \"integer\",\n        \"minimum\": 0\n      },\n      \"description\": {\n        \"type\": [\n          \"string\",\n          \"null\"\n        ]\n      },\n      \"deprecated\": {\n        \"type\": \"boolean\"\n      },\n      \"known\": {\n        \"type\": \"boolean\"\n      },\n      \"suggestion\": {\n        \"type\": [\n          \"string\",\n          \"null\"\n        ]\n      }\n    },\n    \"required\": [\n      \"key\",\n      \"path\",\n      \"line\",\n      \"description\",\n      \"deprecated\",\n      \"known\",\n      \"suggestion\"\n    ],\n    \"additionalProperties\": false\n  }\n}\n"
}'
export def "mise config explain" [
    key?: string@"nus complete",       # Dotted key path to describe, with the keys under it; omit for the whole file
    --cd (-C): path@"nus complete",    # Run as if mise were started in DIR
    --env_ (-E): list<string>,         # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,               # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                      # Suppress non-error messages
    --verbose (-v): int,               # Show extra output (use -vv for even more)
    --yes (-y),                        # Answer yes to all confirmation prompts
    --raw,                             # Connect tasks and install commands directly to the terminal
    --locked,                          # Require download URLs from the lockfile when installing
    --silent,                          # Suppress all task output and mise non-error messages
    --file (-f): path@"nus complete",  # Config file to read, or a directory whose config file to read
    --global (-g),                     # Read the global config file
    --system,                          # Read the system config file
    --override,                        # Read the global override file, `config.override.toml`
]: nothing -> table<key: string, path: list<string>, line: int, description: oneof<string, nothing>, deprecated: bool, known: bool, suggestion: oneof<string, nothing>> {
    let text = ^mise config explain --json ...(nus argv [$key] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --file: $file
        --global: $global
        --system: $system
        --override: $override
    })
    nus decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"title\":\"mise config explain --json\",\"type\":\"array\",\"items\":{\"type\":\"object\",\"properties\":{\"key\":{\"type\":\"string\"},\"path\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}},\"line\":{\"type\":\"integer\",\"minimum\":0},\"description\":{\"type\":[\"string\",\"null\"]},\"deprecated\":{\"type\":\"boolean\"},\"known\":{\"type\":\"boolean\"},\"suggestion\":{\"type\":[\"string\",\"null\"]}},\"required\":[\"key\",\"path\",\"line\",\"description\",\"deprecated\",\"known\",\"suggestion\"],\"additionalProperties\":false}}" { from json }
}

# Print a value from one mise TOML file
#
# Reads the highest-precedence loaded TOML file by default. Select another with
# `--file`, `--global`, or `--system`. This reads stored values, not the merged or
# template-expanded environment; use `mise env` for the resolved environment.
@usage 'long_help #"""
Print a value from one mise TOML file

Reads the highest-precedence loaded TOML file by default. Select another with
`--file`, `--global`, or `--system`. This reads stored values, not the merged or
template-expanded environment; use `mise env` for the resolved environment.
"""#'
@usage 'flag "-f --file --path" help="Config file to read, or a directory whose config file to read" {
            long_help #"""
Config file to read, or a directory whose config file to read

For a directory, mise reads the TOML config file already there, such as `.mise.toml`, or `mise.toml` when there is none. Defaults to the highest-precedence loaded TOML file other than the global override files.
"""#
            arg <FILE>
        }'
@usage 'flag "-g --global" help="Read the global config file" {
            conflicts "--file" "--system"
        }'
@usage 'flag --system help="Read the system config file" {
            conflicts "--file" "--global"
        }'
@usage 'flag --override help="Read the global override file, `config.override.toml`" {
            conflicts "--file" "--global" "--system"
        }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage r#'arg "[KEY]" help="Dotted key path to print, such as `tools.python`; omit to print the whole file" help_long=#"""
Dotted key path to print, such as `tools.python`; omit to print the whole file

Quote a key with a dot in its name as TOML does, inside shell quotes: `'tasks."build.sh"'`. Unquoted, `tasks.build.sh` still finds the task `build.sh` when there is no key `build` in the way.
"""# required=#false'#
@usage 'example #"""
mise config get tools.python
3.13
"""# help="Print the python request"'
@usage 'example "mise config get" help="Print the whole file"'
@usage 'complete file type=path'
@usage 'complete key run="mise __complete_word__ --candidates key --line={{ words | shell_join | shell_quote }}"'
export def "mise config get" [
    key?: string@"nus complete",       # Dotted key path to print, such as `tools.python`; omit to print the whole file
    --cd (-C): path@"nus complete",    # Run as if mise were started in DIR
    --env_ (-E): list<string>,         # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,               # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                      # Suppress non-error messages
    --verbose (-v): int,               # Show extra output (use -vv for even more)
    --yes (-y),                        # Answer yes to all confirmation prompts
    --raw,                             # Connect tasks and install commands directly to the terminal
    --locked,                          # Require download URLs from the lockfile when installing
    --silent,                          # Suppress all task output and mise non-error messages
    --file (-f): path@"nus complete",  # Config file to read, or a directory whose config file to read
    --global (-g),                     # Read the global config file
    --system,                          # Read the system config file
    --override,                        # Read the global override file, `config.override.toml`
]: nothing -> string {
    ^mise config get ...(nus argv [$key] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --file: $file
        --global: $global
        --system: $system
        --override: $override
    })
}

# List config files currently in use, from lowest to highest precedence
#
# Later files override earlier ones. Global override files
# (`config.override.toml`) rank above all project config and are labeled
# `override`.
@usage 'alias list'
@usage 'long_help #"""
List config files currently in use, from lowest to highest precedence

Later files override earlier ones. Global override files
(`config.override.toml`) rank above all project config and are labeled
`override`.
"""#'
@usage 'flag --truncate help="Truncate long terminal output to fit the available width" negate=--no-truncate default="true"'
@usage 'flag "-J --json" help="Output in JSON format"'
@usage 'flag --no-header help="Do not print the table header" {
            alias "--no-headers" hide=#true
        }'
@usage 'flag --tracked-configs help="List every config file mise has loaded, in any project" {
            long_help #"""
List every config file mise has loaded, in any project

mise remembers the config files it loads so `mise prune` keeps the versions
they use.
"""#
        }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example #"""
mise config ls
Path                        Tools
~/.config/mise/config.toml  node, python
~/work/api/mise.toml        node, terraform
"""# help="List the loaded config files and the tools each one requests"'
@usage 'output "json" framing="json" select="--json" {
    schema "{\n  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",\n  \"type\": \"array\",\n  \"items\": {\n    \"type\": \"object\",\n    \"properties\": {\n      \"path\": {\n        \"type\": \"string\"\n      },\n      \"tools\": {\n        \"type\": \"array\",\n        \"items\": {\n          \"type\": \"string\"\n        }\n      },\n      \"override\": {\n        \"type\": \"boolean\"\n      }\n    },\n    \"required\": [\n      \"path\",\n      \"tools\",\n      \"override\"\n    ],\n    \"additionalProperties\": false\n  }\n}\n"
}'
export def "mise config ls" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --truncate,                      # Truncate long terminal output to fit the available width
    --no-truncate,                   # Turn off --truncate
    --no-header,                     # Do not print the table header
    --tracked-configs,               # List every config file mise has loaded, in any project
]: nothing -> table<path: string, tools: list<string>, override: bool> {
    let text = ^mise config ls --json ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --truncate: $truncate
        --no-truncate: $no_truncate
        --no-header: $no_header
        --tracked-configs: $tracked_configs
    })
    nus decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":\"array\",\"items\":{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"tools\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}},\"override\":{\"type\":\"boolean\"}},\"required\":[\"path\",\"tools\",\"override\"],\"additionalProperties\":false}}" { from json }
}

# Set a value in one mise TOML file
#
# Edits the highest-precedence loaded TOML file by default, which may be an
# environment-specific override. Use `--file` to select an existing project file,
# or `--global`/`--system` to edit or create those config files.
#
# This edits configuration without installing tools. Use `mise use` to install and
# select a version together. For environment variables and settings, `mise set`
# and `mise settings set` are shorter, but they choose their file differently:
# `mise set` writes the nearest `mise.toml`, and `mise settings set` writes the
# global config unless you pass `--local`.
#
# Known settings use their declared type; boolean settings accept `true`,
# `false`, `yes`, `no`, `1`, and `0`. For other keys, `true` and `false` become
# booleans and every other value is stored as a string. Use `--type bool` to
# store `yes`, `no`, `1` or `0` as a boolean, `--type string` to store `true`
# or `false` as text, and `--type integer` for a number.
@usage 'long_help #"""
Set a value in one mise TOML file

Edits the highest-precedence loaded TOML file by default, which may be an
environment-specific override. Use `--file` to select an existing project file,
or `--global`/`--system` to edit or create those config files.

This edits configuration without installing tools. Use `mise use` to install and
select a version together. For environment variables and settings, `mise set`
and `mise settings set` are shorter, but they choose their file differently:
`mise set` writes the nearest `mise.toml`, and `mise settings set` writes the
global config unless you pass `--local`.

Known settings use their declared type; boolean settings accept `true`,
`false`, `yes`, `no`, `1`, and `0`. For other keys, `true` and `false` become
booleans and every other value is stored as a string. Use `--type bool` to
store `yes`, `no`, `1` or `0` as a boolean, `--type string` to store `true`
or `false` as text, and `--type integer` for a number.
"""#'
@usage 'flag "-f --file --path" help="Config file to edit, or a directory whose config file to edit" {
            long_help #"""
Config file to edit, or a directory whose config file to edit

For a directory, mise edits the TOML config file already there, such as `.mise.toml`, or `mise.toml` when there is none. Defaults to the highest-precedence loaded TOML file other than the global override files.
"""#
            arg <FILE>
        }'
@usage 'flag "-g --global" help="Edit the global config file" {
            conflicts "--file" "--system"
        }'
@usage 'flag --override help="Edit the global override file, `config.override.toml`" {
            conflicts "--file" "--global" "--system"
        }'
@usage 'flag --system help="Edit the system config file" {
            conflicts "--file" "--global"
        }'
@usage 'flag --append help="Append the value to a list without duplicating an existing entry" conflicts=--remove'
@usage 'flag --remove help="Remove the value from an existing list" conflicts=--append'
@usage 'flag "-t --type" help="TOML type to store the value as; inferred from the value by default" default=infer {
            arg <TYPE> {
                choices {
                    choice infer
                    choice string
                    choice integer
                    choice float
                    choice bool
                    choice list
                    choice set
                }
            }
        }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage r#'arg <KEY> help="Dotted key path to set, such as `tools.python`" help_long=#"""
Dotted key path to set, such as `tools.python`

Quote a key with a dot in its name as TOML does, inside shell quotes: `'tasks."build.sh"'`. Unquoted, `tasks.build.sh` still finds the task `build.sh` when there is no key `build` in the way.
"""#'#
@usage 'arg "[VALUE]" help="The value to set the key to (optional if provided as KEY=VALUE)" required=#false'
@usage 'example "mise config set tools.python 3.13" help="Request python 3.13"'
@usage 'example "mise config set env.NODE_ENV production" help="Set an environment variable"'
@usage 'example "mise config set settings.jobs 4" help="Settings get their declared type, here an integer"'
@usage 'example "mise config set settings.disable_tools node,rust" help="List settings take comma-separated values"'
@usage 'example "mise config set --append env._.path ~/.local/bin" help="Add a PATH entry unless it is already there"'
@usage 'example "mise config set --remove env._.path ~/.local/bin" help="Remove that PATH entry"'
@usage 'example "mise config set -g settings.experimental true" help="Edit the global config"'
@usage 'complete file type=path'
@usage 'complete key run="mise __complete_word__ --candidates key --line={{ words | shell_join | shell_quote }}"'
export def "mise config set" [
    key: string@"nus complete",                                      # Dotted key path to set, such as `tools.python`
    value?: string,                                                  # The value to set the key to (optional if provided as KEY=VALUE)
    --cd (-C): path@"nus complete",                                  # Run as if mise were started in DIR
    --env_ (-E): list<string>,                                       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                                             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                                                    # Suppress non-error messages
    --verbose (-v): int,                                             # Show extra output (use -vv for even more)
    --yes (-y),                                                      # Answer yes to all confirmation prompts
    --raw,                                                           # Connect tasks and install commands directly to the terminal
    --locked,                                                        # Require download URLs from the lockfile when installing
    --silent,                                                        # Suppress all task output and mise non-error messages
    --file (-f): path@"nus complete",                                # Config file to edit, or a directory whose config file to edit
    --global (-g),                                                   # Edit the global config file
    --override,                                                      # Edit the global override file, `config.override.toml`
    --system,                                                        # Edit the system config file
    --append,                                                        # Append the value to a list without duplicating an existing entry
    --remove,                                                        # Remove the value from an existing list
    --type (-t): string@[infer string integer float bool list set],  # TOML type to store the value as; inferred from the value by default
]: nothing -> string {
    ^mise config set ...(nus argv [$key $value] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --file: $file
        --global: $global
        --override: $override
        --system: $system
        --append: $append
        --remove: $remove
        --type: $type
    })
}

# Print the script to disable mise in the current shell session
#
# In a shell where mise is activated, run `mise deactivate`: the activation
# function evaluates the script for you. Calling the executable directly
# (`command mise deactivate`) only prints the script, so evaluate it yourself as
# in the examples below. New shells still activate mise; remove the line from your
# shell startup file to stop that.
@usage 'long_help #"""
Print the script to disable mise in the current shell session

In a shell where mise is activated, run `mise deactivate`: the activation
function evaluates the script for you. Calling the executable directly
(`command mise deactivate`) only prints the script, so evaluate it yourself as
in the examples below. New shells still activate mise; remove the line from your
shell startup file to stop that.
"""#'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise deactivate" help="Turn mise off in an activated shell"'
@usage 'example "eval \"$(command mise deactivate)\"" help="Bash or Zsh, calling the executable rather than the activation function"'
@usage 'example "command mise deactivate | source" help="Fish, calling the executable rather than the activation function"'
export def "mise deactivate" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise deactivate ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# [experimental] Manage project daemons with pitchfork
#
# Declare long-running processes in `[daemons]`, either as commands or as service presets such as `postgres` and `redis`, and mise runs them under pitchfork with the project's tools and environment. Requires `experimental = true`.
#
# With no subcommand, lists the project's daemons like `mise daemons ls`.
#
# See https://mise.jdx.dev/daemons.html
@usage 'alias daemon'
@usage r#'long_help #"""
[experimental] Manage project daemons with pitchfork

Declare long-running processes in `[daemons]`, either as commands or as service presets such as `postgres` and `redis`, and mise runs them under pitchfork with the project's tools and environment. Requires `experimental = true`.

With no subcommand, lists the project's daemons like `mise daemons ls`.

See https://mise.jdx.dev/daemons.html
"""#'#
@usage 'flag --json help="Output in JSON format, including ports, URLs, and data directories"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise daemons start" help="Start the default group, or every project daemon"'
@usage r#'example "mise daemons logs api -n 50" help="Show the last 50 lines of api's output"'#
@usage 'example "mise daemons stop" help="Stop every registered project daemon"'
@usage 'output json framing=json select=--json'
export def "mise daemons" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
] {
    ^mise daemons --json ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    }) | from json
}

# [experimental] Manage shared servers from global `[daemon_providers]`
#
# A shared server is one PostgreSQL, CockroachDB, or NATS server declared in your global config, with a separate database or account for each checkout that uses it. Not supported on Windows. See https://mise.jdx.dev/daemons/sharing.html#shared-server-providers
@usage 'long_help #"""
[experimental] Manage shared servers from global `[daemon_providers]`

A shared server is one PostgreSQL, CockroachDB, or NATS server declared in your global config, with a separate database or account for each checkout that uses it. Not supported on Windows. See https://mise.jdx.dev/daemons/sharing.html#shared-server-providers
"""#'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise daemons providers ls" help="List shared servers"'
@usage 'example "mise daemons providers start local-postgres" help="Start the shared server named local-postgres"'
export def "mise daemons providers" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise daemons providers ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# [experimental] List shared servers
@usage 'flag --json help="Output in JSON format"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'output json framing=json select=--json'
export def "mise daemons providers ls" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
] {
    ^mise daemons providers ls --json ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    }) | from json
}

# [experimental] Start shared servers
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[NAMES]…" required=#false var=#true'
export def "mise daemons providers start" [
    ...names: string,
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise daemons providers start ...(nus argv [...$names] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# [experimental] Stop shared servers (data is kept)
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[NAMES]…" required=#false var=#true'
export def "mise daemons providers stop" [
    ...names: string,
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise daemons providers stop ...(nus argv [...$names] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# [experimental] Restart shared servers with their current configuration
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[NAMES]…" required=#false var=#true'
export def "mise daemons providers restart" [
    ...names: string,
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise daemons providers restart ...(nus argv [...$names] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# [experimental] Start project daemons and the daemons they depend on
#
# Installs missing tools and registers the project's daemons with pitchfork, then starts the selected daemons and waits until they are ready. With no names, starts the `default` group from `[daemon_groups]` when the project declares one, otherwise every project daemon.
#
# Select daemons by name (`api` or a qualified ID such as `shop/api`), by group with `--group NAME`, or all of them with `--all`. `--all` covers every daemon in this project, including those the `default` group leaves out; unlike pitchfork's own `--all`, it never reaches other projects, and it cannot be combined with names or `--group`. Other flags pass through to `pitchfork start`.
@usage r#'long_help #"""
[experimental] Start project daemons and the daemons they depend on

Installs missing tools and registers the project's daemons with pitchfork, then starts the selected daemons and waits until they are ready. With no names, starts the `default` group from `[daemon_groups]` when the project declares one, otherwise every project daemon.

Select daemons by name (`api` or a qualified ID such as `shop/api`), by group with `--group NAME`, or all of them with `--all`. `--all` covers every daemon in this project, including those the `default` group leaves out; unlike pitchfork's own `--all`, it never reaches other projects, and it cannot be combined with names or `--group`. Other flags pass through to `pitchfork start`.
"""#'#
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[ARGS]…" help="Daemon names (short, such as `api`, or qualified, such as `shop/api`), `--group NAME`, and flags passed to pitchfork" required=#false double_dash=automatic var=#true'
@usage 'example "mise daemons start" help="Start the default group, or every daemon"'
@usage 'example "mise daemons start api" help="Start api and the daemons it depends on"'
@usage 'example "mise daemons start --group backend" help="Start a group declared in [daemon_groups]"'
export def "mise daemons start" [
    ...args: string,                 # Daemon names (short, such as `api`, or qualified, such as `shop/api`), `--group NAME`, and flags passed to pitchfork
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise daemons start ...(nus argv [...$args] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# [experimental] Register project daemons for on-demand startup
#
# Installs missing tools, validates daemon definitions and dependencies, and registers the generated configuration with pitchfork without starting anything. Covers every project daemon, including imported dependencies and daemons outside the `default` group. Daemons that are already running keep running.
#
# A running pitchfork supervisor with its proxy enabled can then start a registered HTTP daemon when a request reaches its hostname. See https://mise.jdx.dev/daemons/worktrees.html#register-for-on-demand-startup
@usage 'long_help #"""
[experimental] Register project daemons for on-demand startup

Installs missing tools, validates daemon definitions and dependencies, and registers the generated configuration with pitchfork without starting anything. Covers every project daemon, including imported dependencies and daemons outside the `default` group. Daemons that are already running keep running.

A running pitchfork supervisor with its proxy enabled can then start a registered HTTP daemon when a request reaches its hostname. See https://mise.jdx.dev/daemons/worktrees.html#register-for-on-demand-startup
"""#'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise daemons register" help="Register every project daemon"'
export def "mise daemons register" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise daemons register ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# [experimental] Stop project daemons
#
# With no names, stops every daemon the project has registered, including daemons a removed group started. Data is kept. Select daemons as `mise daemons start` does: by name, with `--group NAME`, or with `--all`. Other flags pass through to `pitchfork stop`.
@usage 'long_help #"""
[experimental] Stop project daemons

With no names, stops every daemon the project has registered, including daemons a removed group started. Data is kept. Select daemons as `mise daemons start` does: by name, with `--group NAME`, or with `--all`. Other flags pass through to `pitchfork stop`.
"""#'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[ARGS]…" help="Daemon names (short, such as `api`, or qualified, such as `shop/api`), `--group NAME`, and flags passed to pitchfork" required=#false double_dash=automatic var=#true'
@usage 'example "mise daemons stop postgres" help="Stop one daemon"'
export def "mise daemons stop" [
    ...args: string,                 # Daemon names (short, such as `api`, or qualified, such as `shop/api`), `--group NAME`, and flags passed to pitchfork
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise daemons stop ...(nus argv [...$args] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# [experimental] Restart project daemons
#
# Installs missing tools first and selects daemons as `mise daemons start` does: with no names, the `default` group when the project declares one, otherwise every project daemon. A changed daemon declaration takes effect on restart. Other flags pass through to `pitchfork restart`.
@usage 'long_help #"""
[experimental] Restart project daemons

Installs missing tools first and selects daemons as `mise daemons start` does: with no names, the `default` group when the project declares one, otherwise every project daemon. A changed daemon declaration takes effect on restart. Other flags pass through to `pitchfork restart`.
"""#'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[ARGS]…" help="Daemon names (short, such as `api`, or qualified, such as `shop/api`), `--group NAME`, and flags passed to pitchfork" required=#false double_dash=automatic var=#true'
@usage 'example "mise daemons restart api" help="Restart api with its current declaration"'
export def "mise daemons restart" [
    ...args: string,                 # Daemon names (short, such as `api`, or qualified, such as `shop/api`), `--group NAME`, and flags passed to pitchfork
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise daemons restart ...(nus argv [...$args] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# [experimental] List project daemons
#
# Shows each daemon's ID, status, and source without starting a supervisor or registering configuration.
@usage 'alias list'
@usage r#'long_help #"""
[experimental] List project daemons

Shows each daemon's ID, status, and source without starting a supervisor or registering configuration.
"""#'#
@usage 'flag --json help="Output in JSON format, including ports, URLs, and data directories"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise daemons ls --json" help="Include ports, URLs, and data directories"'
@usage 'output json framing=json select=--json'
export def "mise daemons ls" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
] {
    ^mise daemons ls --json ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    }) | from json
}

# [experimental] Show each daemon's URL and port
#
# Lists every project daemon with its proxy hostname URL, the port it binds, its proxy mode, and its status. A daemon's hostname does not change when its port does, so an HTTP service can be addressed by URL while concurrent checkouts keep separate ports. A daemon with no `port`, or with `proxy = false`, gets no hostname and is listed without a URL. Each project's table is followed by its project page URL and, in a linked Git worktree, its stack page URL.
#
# See https://mise.jdx.dev/daemons/worktrees.html#stable-urls-per-worktree
@usage r#'long_help #"""
[experimental] Show each daemon's URL and port

Lists every project daemon with its proxy hostname URL, the port it binds, its proxy mode, and its status. A daemon's hostname does not change when its port does, so an HTTP service can be addressed by URL while concurrent checkouts keep separate ports. A daemon with no `port`, or with `proxy = false`, gets no hostname and is listed without a URL. Each project's table is followed by its project page URL and, in a linked Git worktree, its stack page URL.

See https://mise.jdx.dev/daemons/worktrees.html#stable-urls-per-worktree
"""#'#
@usage 'flag --json help="Output in JSON format, including ports, URLs, and data directories"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise daemons urls" help="Show the URLs for this checkout"'
@usage 'output json framing=json select=--json'
export def "mise daemons urls" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
] {
    ^mise daemons urls --json ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    }) | from json
}

# [experimental] Show the output of project daemons
#
# Requires a running pitchfork supervisor. With no names, shows every daemon the project has registered. Flags such as `-n`, `--since`, and `--grep` pass through to `pitchfork logs`.
@usage 'long_help #"""
[experimental] Show the output of project daemons

Requires a running pitchfork supervisor. With no names, shows every daemon the project has registered. Flags such as `-n`, `--since`, and `--grep` pass through to `pitchfork logs`.
"""#'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[ARGS]…" help="Daemon names (short, such as `api`, or qualified, such as `shop/api`), `--group NAME`, and flags passed to pitchfork" required=#false double_dash=automatic var=#true'
@usage r#'example "mise daemons logs api -n 50" help="Show the last 50 lines of api's output"'#
@usage 'example "mise daemons logs --since 5min" help="Show the last five minutes of output"'
export def "mise daemons logs" [
    ...args: string,                 # Daemon names (short, such as `api`, or qualified, such as `shop/api`), `--group NAME`, and flags passed to pitchfork
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise daemons logs ...(nus argv [...$args] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# [experimental] Show the status of project daemons
#
# Prints pitchfork's status for each selected daemon. With no names, covers every daemon the project has registered.
@usage r#'long_help #"""
[experimental] Show the status of project daemons

Prints pitchfork's status for each selected daemon. With no names, covers every daemon the project has registered.
"""#'#
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[ARGS]…" help="Daemon names (short, such as `api`, or qualified, such as `shop/api`), `--group NAME`, and flags passed to pitchfork" required=#false double_dash=automatic var=#true'
@usage 'example "mise daemons status api" help="Show the status of api"'
export def "mise daemons status" [
    ...args: string,                 # Daemon names (short, such as `api`, or qualified, such as `shop/api`), `--group NAME`, and flags passed to pitchfork
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise daemons status ...(nus argv [...$args] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# [experimental] Open the pitchfork dashboard
#
# Requires a running pitchfork supervisor. Takes `pitchfork tui` flags, not daemon names.
@usage 'long_help #"""
[experimental] Open the pitchfork dashboard

Requires a running pitchfork supervisor. Takes `pitchfork tui` flags, not daemon names.
"""#'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[ARGS]…" help="Flags passed to `pitchfork tui`" required=#false double_dash=automatic var=#true'
export def "mise daemons tui" [
    ...args: string,                 # Flags passed to `pitchfork tui`
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise daemons tui ...(nus argv [...$args] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# [experimental] Remove daemon state left by deleted projects
#
# Scans `$MISE_STATE_DIR/daemons/` for state that belongs to deleted projects, including removed Git worktrees. For each one, stops its daemons, unregisters its configuration, and deletes its state and data. Existing projects are not touched.
#
# Use `--dry-run` to preview the paths and sizes. Removal cannot be undone and asks for confirmation. Pass the global `--yes` flag to prune without a prompt; entries that may belong to an unmounted volume or a deleted symlink are then skipped and need a separate interactive confirmation.
#
# pitchfork must be available. State is kept when mise cannot confirm that the daemons have stopped or cannot unregister their configuration.
@usage 'long_help #"""
[experimental] Remove daemon state left by deleted projects

Scans `$MISE_STATE_DIR/daemons/` for state that belongs to deleted projects, including removed Git worktrees. For each one, stops its daemons, unregisters its configuration, and deletes its state and data. Existing projects are not touched.

Use `--dry-run` to preview the paths and sizes. Removal cannot be undone and asks for confirmation. Pass the global `--yes` flag to prune without a prompt; entries that may belong to an unmounted volume or a deleted symlink are then skipped and need a separate interactive confirmation.

pitchfork must be available. State is kept when mise cannot confirm that the daemons have stopped or cannot unregister their configuration.
"""#'
@usage 'flag "-n --dry-run" help="Show what would be removed without deleting anything"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise daemons prune --dry-run" help="Preview what would be removed"'
@usage 'example "mise daemons prune" help="Review the list and confirm removal"'
export def "mise daemons prune" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                  # Show what would be removed without deleting anything
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise daemons prune ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Deploy, track, and sync dotfiles
#
# A `[dotfiles]` entry deploys a file (from a source with `symlink`, `symlink-each`, `copy`, or `template`, or from inline `content`), removes one (`mode = "absent"`), sets an existing path's `permissions`, edits part of a file, or tracks a live file where it is (`mode = "track"`). mise saves tracked files to a local Git history that you can browse and roll back, and syncs it with other machines through an origin repository. `mise dot` is a shorter alias.
#
# Deploy files with `add`, `apply`, `diff`, `status`, and `unapply`. Track and restore files with `track`, `save`, `history`, `rollback`, and `undo`. Sync them with `origin`, `sync`, and `pull`.
#
# See https://mise.jdx.dev/dotfiles.html and https://mise.jdx.dev/dotfiles/history.html
@usage 'alias dot'
@usage r#'long_help #"""
Deploy, track, and sync dotfiles

A `[dotfiles]` entry deploys a file (from a source with `symlink`, `symlink-each`, `copy`, or `template`, or from inline `content`), removes one (`mode = "absent"`), sets an existing path's `permissions`, edits part of a file, or tracks a live file where it is (`mode = "track"`). mise saves tracked files to a local Git history that you can browse and roll back, and syncs it with other machines through an origin repository. `mise dot` is a shorter alias.

Deploy files with `add`, `apply`, `diff`, `status`, and `unapply`. Track and restore files with `track`, `save`, `history`, `rollback`, and `undo`. Sync them with `origin`, `sync`, and `pull`.

See https://mise.jdx.dev/dotfiles.html and https://mise.jdx.dev/dotfiles/history.html
"""#'#
@usage r#'flag --local help="Work on this machine's local-only history (`mode = \"track-local\"`), which is never shared"'#
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise dot add ~/.zshrc" help="Start managing ~/.zshrc from your dotfiles directory"'
@usage 'example "mise dot apply" help="Deploy every [dotfiles] entry"'
@usage 'example "mise dot status" help="Show the state of your dotfiles and their history"'
@usage 'example "mise dot track ~/.config/nvim" help="Save the history of a directory in place"'
@usage 'example "mise dot history" help="List saved checkpoints"'
export def "mise dotfiles" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --local,                         # Work on this machine's local-only history (`mode = "track-local"`), which is never shared
]: nothing -> string {
    ^mise dotfiles ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --local: $local
    })
}

# Start deploying a file, or copy its edits back to the source
#
# For a target that is not managed yet, saves its contents as a source under `dotfiles.root` (or at the path given with `--source`), adds a `[dotfiles]` entry, and applies it unless you pass `--no-apply`. For a target that is already managed, updates its source from the live file. `--dry-run` previews the source and config changes without writing them.
#
# A target inside the tree of a dotfile group is captured into that group's source instead, without a new `[dotfiles]` entry: the deepest group whose target contains it, or the one named with `--group`.
@usage r#'long_help #"""
Start deploying a file, or copy its edits back to the source

For a target that is not managed yet, saves its contents as a source under `dotfiles.root` (or at the path given with `--source`), adds a `[dotfiles]` entry, and applies it unless you pass `--no-apply`. For a target that is already managed, updates its source from the live file. `--dry-run` previews the source and config changes without writing them.

A target inside the tree of a dotfile group is captured into that group's source instead, without a new `[dotfiles]` entry: the deepest group whose target contains it, or the one named with `--group`.
"""#'#
@usage 'flag --changed help="Update the sources of every changed file managed in copy mode"'
@usage 'flag "-f --force" help="Overwrite existing sources without prompting"'
@usage 'flag "-g --global" help="Write to the global config (the default)" {
            long_help #"""
Write to the global config (the default)

New entries go to the `write_targets.dotfiles` file when that setting is set.
"""#
            conflicts "--local" "--path"
        }'
@usage 'flag "-l --local" help="Write to the project config instead of the global config" {
            conflicts "--global" "--path"
        }'
@usage 'flag "-m --mode" help="Mode for a target that is not managed yet: symlink, symlink-each, copy, or template (default: the `dotfiles.default_mode` setting)" {
            long_help #"""
Mode for a target that is not managed yet: symlink, symlink-each, copy, or template (default: the `dotfiles.default_mode` setting)

A target that is already managed keeps its mode.
"""#
            arg <MODE>
        }'
@usage 'flag "-n --dry-run" help="Print the config and source changes without writing anything"'
@usage 'flag --no-apply help="Add the entry without applying it"'
@usage 'flag "-p --path" help="Write to this config file or directory" {
            conflicts "--global" "--local"
            arg <PATH>
        }'
@usage r#'flag "-s --source" help="Source path to use for a single target" {
            long_help #"""
Source path to use for a single target

A relative path starts from the current directory. The entry records it relative to the config file's directory when it lies inside it, and as an absolute path otherwise.
"""#
            arg <PATH>
        }'#
@usage 'flag "-y --yes" help="Skip the confirmation prompt"'
@usage 'flag --prompt-secrets help="Prompt for `[bootstrap.secrets]` values that templates need and the environment does not set"'
@usage 'flag --group help="Capture into the tree of this dotfile group" conflicts=--source {
            arg <NAME>
        }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[TARGET]…" help="Targets to add or update" required=#false var=#true'
@usage 'example "mise dot add ~/.zshrc" help="Start managing ~/.zshrc from your dotfiles directory"'
@usage 'example "mise dot add --mode copy ~/.config/starship.toml" help="Copy the file into place instead of symlinking it"'
@usage 'example "mise dot add --source dotfiles/gitconfig ~/.gitconfig" help="Choose where the source is stored"'
@usage r#'example "mise dot add --group home ~/.config/starship.toml" help="Capture the file into a dotfile group's tree"'#
@usage 'example "mise dot add --changed" help="Copy edits of every changed copy-mode file back to its source"'
export def "mise dotfiles add" [
    ...target: string,               # Targets to add or update
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --force (-f),                    # Overwrite existing sources without prompting
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                  # Print the config and source changes without writing anything
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --local (-l),                    # Write to the project config instead of the global config
    --changed,                       # Update the sources of every changed file managed in copy mode
    --global (-g),                   # Write to the global config (the default)
    --mode (-m): string,             # Mode for a target that is not managed yet: symlink, symlink-each, copy, or template (default: the `dotfiles.default_mode` setting)
    --no-apply,                      # Add the entry without applying it
    --path (-p): string,             # Write to this config file or directory
    --source (-s): string,           # Source path to use for a single target
    --prompt-secrets,                # Prompt for `[bootstrap.secrets]` values that templates need and the environment does not set
    --group: string,                 # Capture into the tree of this dotfile group
]: nothing -> string {
    ^mise dotfiles add ...(nus argv [...$target] {
        --cd: $cd
        --env: $env_
        --force: $force
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --local: $local
        --changed: $changed
        --global: $global
        --mode: $mode
        --no-apply: $no_apply
        --path: $path
        --source: $source
        --prompt-secrets: $prompt_secrets
        --group: $group
    })
}

# Link, copy, and render `[dotfiles]` entries into place
#
# Applies the whole-file entries and edits that are not in their desired state. Whole-file entries symlink, copy, render templates, write inline `content`, set `permissions`, or remove targets declared `mode = "absent"`. Edit entries manage a marker-delimited block, a single line, or merged keys in a file mise does not otherwise own.
#
# Entries that deploy mise's own configuration are applied first and the configuration is read again, so a rule the new file adds applies in the same run.
#
# `apply` works from the files on this machine. It never fetches or pulls: to bring in changes from other machines, run `mise dot sync`, `mise dot pull`, then `mise dot apply`.
#
# The `pre-dotfiles` and `post-dotfiles` bootstrap hooks run before and after the apply (with `--dry-run` they are printed, not run), and the matching `[history.reload]` commands run for the targets it wrote.
#
# With `--prune`, also removes files that dotfile groups deployed but no active entry deploys now: files of a group that is no longer selected or declared, and files a group stopped deploying because of a new `exclude` or a deleted source.
@usage r#'long_help #"""
Link, copy, and render `[dotfiles]` entries into place

Applies the whole-file entries and edits that are not in their desired state. Whole-file entries symlink, copy, render templates, write inline `content`, set `permissions`, or remove targets declared `mode = "absent"`. Edit entries manage a marker-delimited block, a single line, or merged keys in a file mise does not otherwise own.

Entries that deploy mise's own configuration are applied first and the configuration is read again, so a rule the new file adds applies in the same run.

`apply` works from the files on this machine. It never fetches or pulls: to bring in changes from other machines, run `mise dot sync`, `mise dot pull`, then `mise dot apply`.

The `pre-dotfiles` and `post-dotfiles` bootstrap hooks run before and after the apply (with `--dry-run` they are printed, not run), and the matching `[history.reload]` commands run for the targets it wrote.

With `--prune`, also removes files that dotfile groups deployed but no active entry deploys now: files of a group that is no longer selected or declared, and files a group stopped deploying because of a new `exclude` or a deleted source.
"""#'#
@usage 'flag "-f --force" help="Overwrite existing files that conflict with whole-file dotfile entries"'
@usage 'flag "-n --dry-run" help="Print the actions that would run without writing anything"'
@usage 'flag "-y --yes" help="Skip the confirmation prompt"'
@usage 'flag --prune help="Also remove files that dotfile groups deployed but no active entry deploys now"'
@usage 'flag --prompt-secrets help="Prompt for `[bootstrap.secrets]` values that templates need and the environment does not set"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[TARGET]…" help="Only apply these targets" required=#false var=#true'
@usage 'example "mise dot apply" help="Deploy every entry that is out of date"'
@usage 'example "mise dot apply --dry-run" help="Print what would change"'
@usage 'example "mise dot apply --prune" help="Also remove files left by dotfile groups"'
@usage 'example "mise dot apply --force --yes" help="Overwrite conflicting files without prompting"'
export def "mise dotfiles apply" [
    ...target: string,               # Only apply these targets
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --force (-f),                    # Overwrite existing files that conflict with whole-file dotfile entries
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                  # Print the actions that would run without writing anything
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --prune,                         # Also remove files that dotfile groups deployed but no active entry deploys now
    --prompt-secrets,                # Prompt for `[bootstrap.secrets]` values that templates need and the environment does not set
]: nothing -> string {
    ^mise dotfiles apply ...(nus argv [...$target] {
        --cd: $cd
        --env: $env_
        --force: $force
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --prune: $prune
        --prompt-secrets: $prompt_secrets
    })
}

# Run a command and save tracked files before and after it
#
# Runs the command with your terminal and environment and saves a checkpoint before and after it, even when the command fails or changes nothing, so `mise dot undo` can reverse what it did to your tracked files. Edits you make while it runs are part of the same operation. Packages, services, and other system changes are not recorded and cannot be undone. If saving fails, mise warns and still exits with the command's status.
@usage r#'long_help #"""
Run a command and save tracked files before and after it

Runs the command with your terminal and environment and saves a checkpoint before and after it, even when the command fails or changes nothing, so `mise dot undo` can reverse what it did to your tracked files. Edits you make while it runs are part of the same operation. Packages, services, and other system changes are not recorded and cannot be undone. If saving fails, mise warns and still exits with the command's status.
"""#'#
@usage 'flag --label help="Describe this operation in history" {
            arg <LABEL>
        }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "<-- COMMAND>…" help="Command and arguments to run, after --" var=#true'
@usage 'example "mise dot capture -- brew upgrade" help="Record what an upgrade changes"'
@usage 'example "mise dot capture --label \"theme switch\" -- ./switch-theme.sh" help="Label the operation in history"'
export def "mise dotfiles capture" [
    ...command: string,              # Command and arguments to run, after --
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --label: string,                 # Describe this operation in history
]: nothing -> string {
    ^mise dotfiles capture ...(nus argv [...$command] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --label: $label
    })
}

# Compare both sides of a sync conflict
#
# Prints a unified diff from this machine's saved version to the version fetched from the origin. `--difftool` opens the comparison in Git's configured diff tool; when `diff.tool` is unset, Git falls back to `merge.tool`. This command changes neither side. Resolve a conflict with `mise dot pull --take-remote` or `--keep-local`.
@usage r#'long_help #"""
Compare both sides of a sync conflict

Prints a unified diff from this machine's saved version to the version fetched from the origin. `--difftool` opens the comparison in Git's configured diff tool; when `diff.tool` is unset, Git falls back to `merge.tool`. This command changes neither side. Resolve a conflict with `mise dot pull --take-remote` or `--keep-local`.
"""#'#
@usage r#'flag --difftool help="Open the comparison in Git's configured diff or merge tool"'#
@usage 'flag --tool help="Use this Git diff tool instead of the configured default" requires=--difftool {
            arg <TOOL>
        }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[PATH]…" help="Only inspect these conflicted paths" required=#false var=#true'
@usage 'example "mise dot conflicts" help="Show every conflict"'
@usage 'example "mise dot conflicts ~/.zshrc" help="Show one conflicted file"'
@usage r#'example "mise dot conflicts --difftool ~/.zshrc" help="Open the comparison in Git's diff tool"'#
@usage 'example "mise dot conflicts --difftool --tool meld ~/.zshrc" help="Use a specific diff tool"'
export def "mise dotfiles conflicts" [
    ...path: string,                 # Only inspect these conflicted paths
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --tool: string@"nus complete",   # Use this Git diff tool instead of the configured default
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --difftool,                      # Open the comparison in Git's configured diff or merge tool
]: nothing -> string {
    ^mise dotfiles conflicts ...(nus argv [...$path] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --tool: $tool
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --difftool: $difftool
    })
}

# Show what `mise dot apply` would change
#
# Prints a unified diff for every whole-file entry and edit that `mise dot apply` would change. Templates are rendered first, so trusted template functions may run. Tracked entries have nothing to apply; use `mise dot history diff` to see their unsaved changes.
@usage 'long_help #"""
Show what `mise dot apply` would change

Prints a unified diff for every whole-file entry and edit that `mise dot apply` would change. Templates are rendered first, so trusted template functions may run. Tracked entries have nothing to apply; use `mise dot history diff` to see their unsaved changes.
"""#'
@usage 'flag --prompt-secrets help="Prompt for `[bootstrap.secrets]` values that templates need and the environment does not set"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[TARGET]…" help="Only show these targets" required=#false var=#true'
@usage 'example "mise dot diff" help="Show every pending change"'
@usage 'example "mise dot diff ~/.zshrc" help="Show the change for one target"'
export def "mise dotfiles diff" [
    ...target: string,               # Only show these targets
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --prompt-secrets,                # Prompt for `[bootstrap.secrets]` values that templates need and the environment does not set
]: nothing -> string {
    ^mise dotfiles diff ...(nus argv [...$target] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --prompt-secrets: $prompt_secrets
    })
}

# Open a dotfile's source in your editor
#
# Opens the file that defines TARGET in `$VISUAL` or `$EDITOR`: the source for symlink, copy, and template entries; the file itself for tracked and permissions-only entries; and the declaring config for inline `content`, `absent` entries, and edits without a source file.
#
# An unmanaged target is first added to the global `[dotfiles]`, as `mise dot add --no-apply` would add it, after a prompt that `--yes` skips. Without a terminal, an unmanaged target needs `--yes`. With `--apply`, applies the target after the editor exits.
@usage r#'long_help #"""
Open a dotfile's source in your editor

Opens the file that defines TARGET in `$VISUAL` or `$EDITOR`: the source for symlink, copy, and template entries; the file itself for tracked and permissions-only entries; and the declaring config for inline `content`, `absent` entries, and edits without a source file.

An unmanaged target is first added to the global `[dotfiles]`, as `mise dot add --no-apply` would add it, after a prompt that `--yes` skips. Without a terminal, an unmanaged target needs `--yes`. With `--apply`, applies the target after the editor exits.
"""#'#
@usage 'flag --apply help="Apply this target after the editor exits"'
@usage 'flag "-m --mode" help="Mode to use if the target is not managed yet: symlink, symlink-each, copy, or template (default: the `dotfiles.default_mode` setting)" {
            arg <MODE>
        }'
@usage 'flag "-s --source" help="Source path to use if the target is not yet managed" {
            arg <PATH>
        }'
@usage 'flag "-y --yes" help="Skip the confirmation prompt when adding an unmanaged target"'
@usage 'flag --group help="Dotfile group whose tree holds the target, when several groups deploy into its directory" conflicts=--source {
            arg <NAME>
        }'
@usage 'flag --prompt-secrets help="Prompt for `[bootstrap.secrets]` values that templates need and the environment does not set"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <TARGET> help="Target to edit"'
@usage 'example "mise dot edit ~/.zshrc" help="Edit the source of ~/.zshrc"'
@usage 'example "mise dot edit --apply ~/.config/starship.toml" help="Edit the source, then deploy it"'
export def "mise dotfiles edit" [
    target: string,                  # Target to edit
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --apply,                         # Apply this target after the editor exits
    --mode (-m): string,             # Mode to use if the target is not managed yet: symlink, symlink-each, copy, or template (default: the `dotfiles.default_mode` setting)
    --source (-s): string,           # Source path to use if the target is not yet managed
    --group: string,                 # Dotfile group whose tree holds the target, when several groups deploy into its directory
    --prompt-secrets,                # Prompt for `[bootstrap.secrets]` values that templates need and the environment does not set
]: nothing -> string {
    ^mise dotfiles edit ...(nus argv [$target] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --apply: $apply
        --mode: $mode
        --source: $source
        --group: $group
        --prompt-secrets: $prompt_secrets
    })
}

# Never save paths matching a glob
#
# Adds a glob to `[history] exclude` in the global config. The rule applies to every tracked path. Quote the glob so your shell does not expand it.
#
# Use exclusions for logs, caches, databases, and session state. For files you want to save only on demand, track them with `mise dot track --no-autosave` instead. To limit what one tracked directory saves, edit the `exclude` or `include` list of its `[dotfiles]` entry.
@usage 'long_help #"""
Never save paths matching a glob

Adds a glob to `[history] exclude` in the global config. The rule applies to every tracked path. Quote the glob so your shell does not expand it.

Use exclusions for logs, caches, databases, and session state. For files you want to save only on demand, track them with `mise dot track --no-autosave` instead. To limit what one tracked directory saves, edit the `exclude` or `include` list of its `[dotfiles]` entry.
"""#'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <GLOB> help="A glob such as `~/.config/hypr/plugins/**`"'
@usage r#'example "mise dot exclude '~/.codex/sessions/**'" help="Never save Codex session logs"'#
export def "mise dotfiles exclude" [
    glob: string,                    # A glob such as `~/.config/hypr/plugins/**`
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise dotfiles exclude ...(nus argv [$glob] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Browse saved versions of your tracked files
#
# A checkpoint is a saved version of every `[dotfiles]` entry with `mode = "track"`. `mise dot save`, the watcher, and every command that changes tracked files (such as `mise bootstrap`, `mise dot apply`, `rollback`, `pull`, and `undo`) record one. Checkpoints hold file contents only, not packages or services. Files deployed in other modes are saved only if you also track them. With no subcommand, lists checkpoints newest first.
#
# See https://mise.jdx.dev/dotfiles/history.html
@usage 'long_help #"""
Browse saved versions of your tracked files

A checkpoint is a saved version of every `[dotfiles]` entry with `mode = "track"`. `mise dot save`, the watcher, and every command that changes tracked files (such as `mise bootstrap`, `mise dot apply`, `rollback`, `pull`, and `undo`) record one. Checkpoints hold file contents only, not packages or services. Files deployed in other modes are saved only if you also track them. With no subcommand, lists checkpoints newest first.

See https://mise.jdx.dev/dotfiles/history.html
"""#'
@usage 'flag "-J --json" help="Output in JSON format"'
@usage 'flag "-n --limit" help="Show at most this many checkpoints (0 for all)" default="20" {
            arg <LIMIT>
        }'
@usage 'flag --path help="Only checkpoints where this path (or something under it) changed" {
            arg <PATH>
        }'
@usage 'flag --trigger help="Only checkpoints with this trigger, such as edit, save, agent, bootstrap, apply, rollback, or undo" {
            long_help #"""
Only checkpoints with this trigger, such as edit, save, agent, bootstrap, apply, rollback, or undo

`bootstrap` covers `mise bootstrap`, its `packages` commands, and `mise dot add`, `apply`, `edit`, and `unapply`. `apply` covers incoming changes written by `mise dot pull` or the watcher.
"""#
            arg <TRIGGER>
        }'
@usage 'flag --label help="Only checkpoints with this label" {
            arg <LABEL>
        }'
@usage 'flag --pending help="Only checkpoints recorded by operations that did not finish"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise dot history" help="List recent checkpoints"'
@usage 'example "mise dot history --path ~/.config/hypr/bindings.lua" help="List checkpoints that changed one file"'
@usage 'example "mise dot history --trigger bootstrap -n 5" help="List the last five checkpoints from mise bootstrap or mise dot apply"'
@usage 'example "mise dot history show latest" help="Show the newest checkpoint"'
@usage 'example "mise dot history diff" help="Show unsaved changes"'
@usage 'output json framing=json select=--json'
export def "mise dotfiles history" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --limit (-n): string,            # Show at most this many checkpoints (0 for all)
    --path: string,                  # Only checkpoints where this path (or something under it) changed
    --trigger: string,               # Only checkpoints with this trigger, such as edit, save, agent, bootstrap, apply, rollback, or undo
    --label: string,                 # Only checkpoints with this label
    --pending,                       # Only checkpoints recorded by operations that did not finish
] {
    ^mise dotfiles history --json ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --limit: $limit
        --path: $path
        --trigger: $trigger
        --label: $label
        --pending: $pending
    }) | from json
}

# Set the description of a checkpoint
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <REF> help="Numeric checkpoint ID, `latest`, `latest~N`, or `commit:<sha>`"'
@usage 'arg <TEXT> help="The new description"'
@usage 'example "mise dot history describe latest \"before the theme change\"" help="Describe the newest checkpoint"'
export def "mise dotfiles history describe" [
    ref: string,                     # Numeric checkpoint ID, `latest`, `latest~N`, or `commit:<sha>`
    text: string,                    # The new description
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise dotfiles history describe ...(nus argv [$ref $text] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Compare checkpoints, or your files against one
#
# Without arguments, shows unsaved changes: the files on disk against the latest checkpoint. With one reference, shows what that checkpoint changed since the one before it. With two, compares them.
@usage 'long_help #"""
Compare checkpoints, or your files against one

Without arguments, shows unsaved changes: the files on disk against the latest checkpoint. With one reference, shows what that checkpoint changed since the one before it. With two, compares them.
"""#'
@usage r#'flag --operation help="Compare an operation with the checkpoint it saved before it ran" {
                long_help #"""
Compare an operation with the checkpoint it saved before it ran

With no reference, uses the newest operation, ignoring later saves. With one reference, uses that operation. Fails if the operation's earlier checkpoint is unavailable instead of comparing an unrelated save.
"""#
            }'#
@usage 'flag "-p --patch" help="Print the full patch instead of a per-file summary"'
@usage 'flag --path help="Restrict to one path (a file or a directory)" {
                arg <PATH>
            }'
@usage 'flag --exit-code help="Exit 1 when the two sides differ"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[A]" help="Numeric checkpoint ID, `latest`, `latest~N`, or `commit:<sha>`" required=#false'
@usage 'arg "[B]" help="Compare `A` with this checkpoint instead of its predecessor" required=#false'
@usage 'example "mise dot history diff" help="Show unsaved changes"'
@usage 'example "mise dot history diff 12" help="Show what checkpoint 12 changed"'
@usage 'example "mise dot history diff 11 12 --patch" help="Print the full patch between two checkpoints"'
@usage 'example "mise dot history diff --operation" help="Show what the newest operation changed"'
export def "mise dotfiles history diff" [
    a?: string,                      # Numeric checkpoint ID, `latest`, `latest~N`, or `commit:<sha>`
    b?: string,                      # Compare `A` with this checkpoint instead of its predecessor
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --path: string,                  # Restrict to one path (a file or a directory)
    --operation,                     # Compare an operation with the checkpoint it saved before it ran
    --patch (-p),                    # Print the full patch instead of a per-file summary
    --exit-code,                     # Exit 1 when the two sides differ
]: nothing -> string {
    ^mise dotfiles history diff ...(nus argv [$a $b] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --path: $path
        --operation: $operation
        --patch: $patch
        --exit-code: $exit_code
    })
}

# List checkpoints, newest first
@usage 'alias list'
@usage 'flag "-J --json" help="Output in JSON format"'
@usage 'flag "-n --limit" help="Show at most this many checkpoints (0 for all)" default="20" {
                arg <LIMIT>
            }'
@usage 'flag --path help="Only checkpoints where this path (or something under it) changed" {
                arg <PATH>
            }'
@usage 'flag --trigger help="Only checkpoints with this trigger, such as edit, save, agent, bootstrap, apply, rollback, or undo" {
                long_help #"""
Only checkpoints with this trigger, such as edit, save, agent, bootstrap, apply, rollback, or undo

`bootstrap` covers `mise bootstrap`, its `packages` commands, and `mise dot add`, `apply`, `edit`, and `unapply`. `apply` covers incoming changes written by `mise dot pull` or the watcher.
"""#
                arg <TRIGGER>
            }'
@usage 'flag --label help="Only checkpoints with this label" {
                arg <LABEL>
            }'
@usage 'flag --pending help="Only checkpoints recorded by operations that did not finish"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise dot history ls -n 0" help="List every checkpoint"'
@usage 'example "mise dot history ls --pending" help="List operations that did not finish"'
@usage 'output json framing=json select=--json'
export def "mise dotfiles history ls" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --limit (-n): string,            # Show at most this many checkpoints (0 for all)
    --path: string,                  # Only checkpoints where this path (or something under it) changed
    --trigger: string,               # Only checkpoints with this trigger, such as edit, save, agent, bootstrap, apply, rollback, or undo
    --label: string,                 # Only checkpoints with this label
    --pending,                       # Only checkpoints recorded by operations that did not finish
] {
    ^mise dotfiles history ls --json ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --limit: $limit
        --path: $path
        --trigger: $trigger
        --label: $label
        --pending: $pending
    }) | from json
}

# Erase a path's saved versions from history
#
# Rewrites the history without the path, for a file you tracked by mistake that holds a secret. `untrack`, `rollback`, and `undo` only add checkpoints; they leave the old versions readable.
#
# Checkpoints that changed only this path are removed. The others stay, with their descriptions, dates, and IDs, minus the path. Without `--yes`, the command lists what would change and asks first.
#
# mise never rewrites history that is on the origin: if a saved version of the path was ever published, the command refuses. Rotate the secret, then see https://mise.jdx.dev/dotfiles/encryption.html#remove-plaintext-from-history.
#
# This does not stop tracking the path. If the file is still tracked, the next save records its current contents again, so run `mise dot untrack` first (or encrypt it). Stop the watcher service while this runs.
@usage r#'long_help #"""
Erase a path's saved versions from history

Rewrites the history without the path, for a file you tracked by mistake that holds a secret. `untrack`, `rollback`, and `undo` only add checkpoints; they leave the old versions readable.

Checkpoints that changed only this path are removed. The others stay, with their descriptions, dates, and IDs, minus the path. Without `--yes`, the command lists what would change and asks first.

mise never rewrites history that is on the origin: if a saved version of the path was ever published, the command refuses. Rotate the secret, then see https://mise.jdx.dev/dotfiles/encryption.html#remove-plaintext-from-history.

This does not stop tracking the path. If the file is still tracked, the next save records its current contents again, so run `mise dot untrack` first (or encrypt it). Stop the watcher service while this runs.
"""#'#
@usage 'flag "-n --dry-run" help="Show what would change without changing anything"'
@usage 'flag "-y --yes" help="Rewrite without prompting"'
@usage 'flag --backup help="Keep the replaced history in the repository under `refs/mise/purge-backup/`" {
                long_help #"""
Keep the replaced history in the repository under `refs/mise/purge-backup/`

The backup still holds the content you are erasing; delete it with `git update-ref -d` once you are sure.
"""#
            }'
@usage 'flag --keep-objects help="Leave the replaced objects on disk instead of deleting them"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <PATH>… help="Files or directories to erase from history" var=#true'
@usage 'example "mise dot history purge ~/.aws/credentials --dry-run" help="List the checkpoints that hold the file"'
@usage 'example "mise dot history purge ~/.aws/credentials --yes" help="Erase every saved version of the file"'
export def "mise dotfiles history purge" [
    ...path: string,                 # Files or directories to erase from history
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                  # Show what would change without changing anything
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --backup,                        # Keep the replaced history in the repository under `refs/mise/purge-backup/`
    --keep-objects,                  # Leave the replaced objects on disk instead of deleting them
]: nothing -> string {
    ^mise dotfiles history purge ...(nus argv [...$path] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --backup: $backup
        --keep-objects: $keep_objects
    })
}

# Show a checkpoint: its trigger, changes, and operation journal
#
# Prints the checkpoint's trigger, description, time, and machine, the files that changed since the previous checkpoint, and the tracked entries it covers. For a checkpoint that an operation recorded, also prints the operation's journal of the files it wrote.
@usage r#'long_help #"""
Show a checkpoint: its trigger, changes, and operation journal

Prints the checkpoint's trigger, description, time, and machine, the files that changed since the previous checkpoint, and the tracked entries it covers. For a checkpoint that an operation recorded, also prints the operation's journal of the files it wrote.
"""#'#
@usage 'flag "-J --json" help="Output in JSON format"'
@usage 'flag --files help="List every file in the snapshot"'
@usage 'flag --path help="Resolve `latest~N` among the checkpoints where this path changed" {
                arg <PATH>
            }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[REF]" help="Numeric checkpoint ID, `latest` (the default), `latest~N`, or `commit:<sha>`" required=#false'
@usage 'example "mise dot history show" help="Show the newest checkpoint"'
@usage 'example "mise dot history show latest~2 --files" help="List every file in an older checkpoint"'
@usage 'output json framing=json select=--json'
export def "mise dotfiles history show" [
    ref?: string,                    # Numeric checkpoint ID, `latest` (the default), `latest~N`, or `commit:<sha>`
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --path: string,                  # Resolve `latest~N` among the checkpoints where this path changed
    --files,                         # List every file in the snapshot
] {
    ^mise dotfiles history show --json ...(nus argv [$ref] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --path: $path
        --files: $files
    }) | from json
}

# Stop excluding paths matching a glob
#
# Removes a glob that `mise dot exclude` added to `[history] exclude` in the global config. Pass the pattern exactly as you excluded it. Other matching exclusion rules still apply. This command does not edit a tracked directory's `include` list; change that list in its `[dotfiles]` entry.
@usage r#'long_help #"""
Stop excluding paths matching a glob

Removes a glob that `mise dot exclude` added to `[history] exclude` in the global config. Pass the pattern exactly as you excluded it. Other matching exclusion rules still apply. This command does not edit a tracked directory's `include` list; change that list in its `[dotfiles]` entry.
"""#'#
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <GLOB> help="The glob as written by `mise dot exclude`"'
@usage r#'example "mise dot include '~/.codex/sessions/**'" help="Save Codex session logs again"'#
export def "mise dotfiles include" [
    glob: string,                    # The glob as written by `mise dot exclude`
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise dotfiles include ...(nus argv [$glob] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Send a test desktop notification
#
# Checks that `history.notify` can reach you. On macOS the first notification asks for permission, so run this once to be prompted now instead of at the first sync conflict. Fails with the reason when this build or machine cannot show notifications: a macOS build that is not mise's signed release (such as Homebrew's), a missing `notify-send` on Linux, denied permission, or `history.notify = false`.
#
# mise notifies you only when a sync conflict pauses syncing. Other problems, such as a watcher that cannot save, appear in `mise doctor` and `mise dot status`.
@usage r#'long_help #"""
Send a test desktop notification

Checks that `history.notify` can reach you. On macOS the first notification asks for permission, so run this once to be prompted now instead of at the first sync conflict. Fails with the reason when this build or machine cannot show notifications: a macOS build that is not mise's signed release (such as Homebrew's), a missing `notify-send` on Linux, denied permission, or `history.notify = false`.

mise notifies you only when a sync conflict pauses syncing. Other problems, such as a watcher that cannot save, appear in `mise doctor` and `mise dot status`.
"""#'#
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise dot notify" help="Send a test notification"'
export def "mise dotfiles notify" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise dotfiles notify ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Show, connect, or disconnect the origin repository
#
# The origin is a Git repository that shares the history of your tracked files with your other machines. With no subcommand, prints the connected URL, its branch, the config file that declares it, and the sync mode (the `history.sync` setting). `--remove` disconnects; local checkpoints and fetched history stay.
#
# See https://mise.jdx.dev/dotfiles/sync.html
@usage 'long_help #"""
Show, connect, or disconnect the origin repository

The origin is a Git repository that shares the history of your tracked files with your other machines. With no subcommand, prints the connected URL, its branch, the config file that declares it, and the sync mode (the `history.sync` setting). `--remove` disconnects; local checkpoints and fetched history stay.

See https://mise.jdx.dev/dotfiles/sync.html
"""#'
@usage 'flag --remove help="Disconnect the origin by removing `[history.origin]`; local checkpoints and fetched history stay" effect=destructive'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise dot origin" help="Show the connected repository"'
@usage 'example "mise dot origin set git@github.com:you/dotfiles.git" help="Connect a repository"'
@usage 'example "mise dot origin --remove" help="Disconnect the repository"'
export def "mise dotfiles origin" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --remove,                        # Disconnect the origin by removing `[history.origin]`; local checkpoints and fetched history stay
]: nothing -> string {
    ^mise dotfiles origin ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --remove: $remove
    })
}

# Connect an origin repository
#
# Use a private repository: every saved checkpoint is shared, including those saved before you connect. mise shows the sync mode and the tracked files before you confirm, then runs the first sync. It never replaces a repository that has unrelated history, and it refuses to push older plaintext versions of files you now encrypt. The connection is written to `[history.origin]` in `config.local.toml` next to your global config, so it stays on this machine.
#
# The origin holds tracked-file history, not a checkout of your global config: connect a repository of its own, or a separate branch (`--branch`) of the one you adopt as global config with `mise bootstrap --adopt`.
@usage 'long_help #"""
Connect an origin repository

Use a private repository: every saved checkpoint is shared, including those saved before you connect. mise shows the sync mode and the tracked files before you confirm, then runs the first sync. It never replaces a repository that has unrelated history, and it refuses to push older plaintext versions of files you now encrypt. The connection is written to `[history.origin]` in `config.local.toml` next to your global config, so it stays on this machine.

The origin holds tracked-file history, not a checkout of your global config: connect a repository of its own, or a separate branch (`--branch`) of the one you adopt as global config with `mise bootstrap --adopt`.
"""#'
@usage r#'flag --branch help="The branch to sync (default: the repository's default branch)" {
                long_help #"""
The branch to sync (default: the repository's default branch)

Reconnecting a repository this machine already follows keeps that connection's branch. A repository with no branches gets `main`, which the first push creates.
"""#
                arg <BRANCH>
            }'#
@usage 'flag --sync help="How to sync with the repository: sync, fetch-only, or manual" {
                long_help #"""
How to sync with the repository: sync, fetch-only, or manual

`sync` pushes saved checkpoints and applies incoming changes automatically. `fetch-only` fetches automatically and never pushes. `manual` makes no automatic network calls: `mise dot sync` pushes and fetches, and `mise dot pull` applies, only when you run them; local history is still saved automatically. When omitted, mise prompts; with `--yes`, it uses the `history.sync` setting.
"""#
                arg <MODE>
            }'
@usage 'flag "-y --yes" help="Skip the confirmation prompt"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <URL> help="The repository URL (any Git URL; use a private repository)"'
@usage 'example "mise dot origin set https://github.com/you/dotfiles.git" help="Connect and choose a sync mode at the prompt"'
@usage 'example "mise dot origin set git@github.com:you/dotfiles.git --sync manual" help="Connect without automatic network activity"'
export def "mise dotfiles origin set" [
    url: string,                     # The repository URL (any Git URL; use a private repository)
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --branch: string,                # The branch to sync (default: the repository's default branch)
    --sync: string,                  # How to sync with the repository: sync, fetch-only, or manual
]: nothing -> string {
    ^mise dotfiles origin set ...(nus argv [$url] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --branch: $branch
        --sync: $sync
    })
}

# List tracked paths and how they are saved
#
# Shows each tracked entry with the config file that declares it, whether it saves automatically, and how many files it covers. Entries mise cannot save are listed as invalid, omitted, or incomplete, so you can see what is not protected.
@usage 'long_help #"""
List tracked paths and how they are saved

Shows each tracked entry with the config file that declares it, whether it saves automatically, and how many files it covers. Entries mise cannot save are listed as invalid, omitted, or incomplete, so you can see what is not protected.
"""#'
@usage 'flag "-J --json" help="Output in JSON format"'
@usage 'flag --preview help="List the files that tracking this path would save, without tracking it" {
            arg <PATH>
        }'
@usage 'flag --noisy help="List the paths the watcher found changing constantly and saves less often"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise dot paths" help="List tracked paths"'
@usage 'example "mise dot paths --preview ~/.codex" help="List the files tracking ~/.codex would save"'
@usage 'example "mise dot paths --noisy" help="List files the watcher saves less often"'
@usage 'output json framing=json select=--json'
export def "mise dotfiles paths" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --preview: string,               # List the files that tracking this path would save, without tracking it
    --noisy,                         # List the paths the watcher found changing constantly and saves less often
] {
    ^mise dotfiles paths --json ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --preview: $preview
        --noisy: $noisy
    }) | from json
}

# Write fetched changes from other machines to tracked files
#
# Writes the changes that the last `mise dot sync` fetched from your other machines. (`mise dot apply` deploys your own `[dotfiles]` entries; `pull` writes what other machines pushed.) `pull` restores tracked paths, including tracked symlinks, but never deploys `copy`, `symlink`, or `template` entries: when a tracked file is the source of one, `pull` updates the source, and `mise dot apply` then writes the target your application reads. mise saves a checkpoint first, so `mise dot undo` reverses the whole pull, and runs the matching `[history.reload]` commands after writing.
#
# A pull applies every incoming change together, including config files and the files they reference; it does not take paths. Nothing is written if an incoming config file does not parse, a file has unsaved local edits, your own checkout has staged Git changes, or a file changed on both sides. A file that changed on both sides is a conflict: compare the two versions with `mise dot conflicts`, then resolve it with `--take-remote` or `--keep-local`, or resolve every conflict with `--take-remote-all` or `--keep-local-all`. While any conflict remains, pushing and applying stop for all tracked files; local history and fetching continue.
#
# In `sync` mode the watcher pulls on its own when there are no conflicts. When incoming config declares more tracked files, their versions from the origin are written in the same pull.
@usage 'long_help #"""
Write fetched changes from other machines to tracked files

Writes the changes that the last `mise dot sync` fetched from your other machines. (`mise dot apply` deploys your own `[dotfiles]` entries; `pull` writes what other machines pushed.) `pull` restores tracked paths, including tracked symlinks, but never deploys `copy`, `symlink`, or `template` entries: when a tracked file is the source of one, `pull` updates the source, and `mise dot apply` then writes the target your application reads. mise saves a checkpoint first, so `mise dot undo` reverses the whole pull, and runs the matching `[history.reload]` commands after writing.

A pull applies every incoming change together, including config files and the files they reference; it does not take paths. Nothing is written if an incoming config file does not parse, a file has unsaved local edits, your own checkout has staged Git changes, or a file changed on both sides. A file that changed on both sides is a conflict: compare the two versions with `mise dot conflicts`, then resolve it with `--take-remote` or `--keep-local`, or resolve every conflict with `--take-remote-all` or `--keep-local-all`. While any conflict remains, pushing and applying stop for all tracked files; local history and fetching continue.

In `sync` mode the watcher pulls on its own when there are no conflicts. When incoming config declares more tracked files, their versions from the origin are written in the same pull.
"""#'
@usage 'flag "-n --dry-run" help="Show the plan without changing anything"'
@usage 'flag "-y --yes" help="Accepted for compatibility; pull skips the apply confirmation"'
@usage r#'flag --take-remote help="Resolve a conflict with the origin's version" var=#true {
            arg <PATH>
        }'#
@usage r#'flag --keep-local help="Resolve a conflict by keeping this machine's version; the next sync pushes it" var=#true {
            arg <PATH>
        }'#
@usage r#'flag --take-remote-all help="Resolve every remaining conflict with the origin's version" conflicts=--keep-local-all {
            long_help #"""
Resolve every remaining conflict with the origin's version

Paths named by `--keep-local` keep this machine's version; every other conflict takes the origin's. Use it on a newly connected machine, where each existing file that differs is a separate conflict.
"""#
        }'#
@usage r#'flag --keep-local-all help="Resolve every remaining conflict by keeping this machine's version" conflicts=--take-remote-all {
            long_help #"""
Resolve every remaining conflict by keeping this machine's version

Paths named by `--take-remote` take the origin's version; every other conflict keeps this machine's. Each kept path must already be saved.
"""#
        }'#
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[PATH]…" help="Not supported; a pull always applies every incoming change" required=#false var=#true hide=#true'
@usage 'example "mise dot pull --dry-run" help="Show what would be written"'
@usage r#'example "mise dot pull --take-remote ~/.zshrc" help="Resolve a conflict with the origin's version"'#
@usage r#'example "mise dot pull --keep-local ~/.zshrc" help="Resolve a conflict by keeping this machine's version"'#
@usage r#'example "mise dot pull --take-remote-all --keep-local ~/.zshrc" help="Take the origin's version of every conflict except one"'#
export def "mise dotfiles pull" [
    ...path: string,                 # Not supported; a pull always applies every incoming change
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                  # Show the plan without changing anything
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --take-remote: list<string>,     # Resolve a conflict with the origin's version
    --keep-local: list<string>,      # Resolve a conflict by keeping this machine's version; the next sync pushes it
    --take-remote-all,               # Resolve every remaining conflict with the origin's version
    --keep-local-all,                # Resolve every remaining conflict by keeping this machine's version
]: nothing -> string {
    ^mise dotfiles pull ...(nus argv [...$path] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --take-remote: $take_remote
        --keep-local: $keep_local
        --take-remote-all: $take_remote_all
        --keep-local-all: $keep_local_all
    })
}

# Recover an interrupted dotfile operation
#
# Finishes recovering from an operation that was interrupted, for example by a crash or Ctrl-C. With no argument, recovers every interrupted operation. mise restores files from the operation's recovery copies unless you have edited them since. When it cannot tell which version is safe, it lists the files: check them, then rerun with `--keep-current` to keep what is on disk and discard the operation's recovery copies. When several operations were interrupted, `--keep-current` needs the ID of one. Git history is not changed.
@usage r#'long_help #"""
Recover an interrupted dotfile operation

Finishes recovering from an operation that was interrupted, for example by a crash or Ctrl-C. With no argument, recovers every interrupted operation. mise restores files from the operation's recovery copies unless you have edited them since. When it cannot tell which version is safe, it lists the files: check them, then rerun with `--keep-current` to keep what is on disk and discard the operation's recovery copies. When several operations were interrupted, `--keep-current` needs the ID of one. Git history is not changed.
"""#'#
@usage 'flag --keep-current help="Keep the files on disk instead of restoring the recovery copies"'
@usage r#'flag "-y --yes" help="Discard the operation's recovery copies without prompting"'#
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage r#'arg "[OPERATION]" help="The operation's checkpoint ID (see `mise dot history --pending`) or a unique prefix of its UUID" required=#false'#
@usage 'example "mise dot recover" help="Recover every interrupted operation"'
@usage 'example "mise dot recover 42 --keep-current --yes" help="Keep the files on disk for operation 42"'
export def "mise dotfiles recover" [
    operation?: string,              # The operation's checkpoint ID (see `mise dot history --pending`) or a unique prefix of its UUID
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --keep-current,                  # Keep the files on disk instead of restoring the recovery copies
]: nothing -> string {
    ^mise dotfiles recover ...(nus argv [$operation] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --keep-current: $keep_current
    })
}

# Return files to the version a checkpoint holds
#
# Without `--to`, each path returns to its most recent saved version that differs from what is on disk; other checkpoints do not affect the choice. With `--to REF`, the named checkpoint is the source, and `--all` restores everything it covers. mise saves the current state in a checkpoint first, so `mise dot undo` can reverse the rollback.
@usage 'long_help #"""
Return files to the version a checkpoint holds

Without `--to`, each path returns to its most recent saved version that differs from what is on disk; other checkpoints do not affect the choice. With `--to REF`, the named checkpoint is the source, and `--all` restores everything it covers. mise saves the current state in a checkpoint first, so `mise dot undo` can reverse the rollback.
"""#'
@usage 'flag --to help="The checkpoint to roll back to: numeric ID, `latest`, `latest~N`, or `commit:<sha>`" {
            arg <REF>
        }'
@usage 'flag --all help="With `--to`, restore everything the checkpoint covers"'
@usage 'flag "-n --dry-run" help="Show the plan without changing anything"'
@usage 'flag "-y --yes" help="Apply without prompting"'
@usage 'flag --force help="Replace a path whose type changed (file, symlink, directory)"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[PATH]…" help="Paths to roll back (files or directories)" required=#false var=#true'
@usage 'example "mise dot rollback ~/.config/hypr/bindings.lua" help="Restore the latest saved version that differs from the file"'
@usage 'example "mise dot rollback ~/.zshrc --to 42" help="Restore ~/.zshrc as checkpoint 42 holds it"'
@usage 'example "mise dot rollback --to latest~3 --all --dry-run" help="Preview restoring every file from three checkpoints ago"'
export def "mise dotfiles rollback" [
    ...path: string,                 # Paths to roll back (files or directories)
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --force,                         # Replace a path whose type changed (file, symlink, directory)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                  # Show the plan without changing anything
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --to: string,                    # The checkpoint to roll back to: numeric ID, `latest`, `latest~N`, or `commit:<sha>`
    --all,                           # With `--to`, restore everything the checkpoint covers
]: nothing -> string {
    ^mise dotfiles rollback ...(nus argv [...$path] {
        --cd: $cd
        --env: $env_
        --force: $force
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --to: $to
        --all: $all
    })
}

# Save a checkpoint of the tracked files now
#
# Exits non-zero when history cannot save or a named path is not tracked. With no changes since the latest checkpoint, nothing is saved unless you pass `--description`, `--label`, `--task`, or a `--trigger` other than `save`.
#
# `--best-effort` turns a failure to write the checkpoint, such as missing Git, into a warning for update scripts that run under `set -e`. A disabled history or an untracked path still fails.
#
# A save re-encrypts the files it captures to the current `[history.encryption] recipients`. `--re-encrypt` also re-encrypts the encrypted files it does not capture: files with `autosave = false` that it does not name, and variants for other platforms. It re-encrypts their saved versions and saves no unsaved edit. Run it after changing recipients so a machine added to the list can read every file. This machine must be able to unlock each one; otherwise nothing is saved and the error lists each file it cannot unlock.
@usage 'long_help #"""
Save a checkpoint of the tracked files now

Exits non-zero when history cannot save or a named path is not tracked. With no changes since the latest checkpoint, nothing is saved unless you pass `--description`, `--label`, `--task`, or a `--trigger` other than `save`.

`--best-effort` turns a failure to write the checkpoint, such as missing Git, into a warning for update scripts that run under `set -e`. A disabled history or an untracked path still fails.

A save re-encrypts the files it captures to the current `[history.encryption] recipients`. `--re-encrypt` also re-encrypts the encrypted files it does not capture: files with `autosave = false` that it does not name, and variants for other platforms. It re-encrypts their saved versions and saves no unsaved edit. Run it after changing recipients so a machine added to the list can read every file. This machine must be able to unlock each one; otherwise nothing is saved and the error lists each file it cannot unlock.
"""#'
@usage 'flag "-d --description" help="A description for the checkpoint" {
            arg <TEXT>
        }'
@usage 'flag --trigger help="Record the checkpoint as a save, agent, or update checkpoint" default=save {
            arg <TRIGGER>
        }'
@usage 'flag --task help="The ID of the task an agent is working on, recorded with the checkpoint" {
            arg <ID>
        }'
@usage 'flag --label help="A label to find the checkpoint by later" var=#true {
            arg <LABEL>
        }'
@usage 'flag --best-effort help="Warn instead of failing when the checkpoint cannot be written"'
@usage 'flag --re-encrypt help="Re-encrypt every saved encrypted file to the current recipients"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[PATH]…" help="Paths to save; every one must be tracked" required=#false var=#true'
@usage 'example "mise dot save" help="Save every tracked file that changed"'
@usage 'example "mise dot save ~/.zshrc -d \"before the theme change\"" help="Save one file with a description"'
@usage 'example "mise dot save --best-effort" help="Warn instead of failing in a script"'
@usage 'example "mise dot save --re-encrypt" help="Re-encrypt every encrypted file after changing recipients"'
export def "mise dotfiles save" [
    ...path: string,                 # Paths to save; every one must be tracked
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --description (-d): string,      # A description for the checkpoint
    --trigger: string,               # Record the checkpoint as a save, agent, or update checkpoint
    --task: string,                  # The ID of the task an agent is working on, recorded with the checkpoint
    --label: list<string>,           # A label to find the checkpoint by later
    --best-effort,                   # Warn instead of failing when the checkpoint cannot be written
    --re-encrypt,                    # Re-encrypt every saved encrypted file to the current recipients
]: nothing -> string {
    ^mise dotfiles save ...(nus argv [...$path] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --description: $description
        --trigger: $trigger
        --task: $task
        --label: $label
        --best-effort: $best_effort
        --re-encrypt: $re_encrypt
    })
}

# Show the state of your dotfiles and their history
#
# Lists the `[dotfiles]` entries that need attention, and counts the rest; `--verbose` lists every entry. Each has a state: `applied`, `missing`, `differs`, `source missing`, `tracked`, `would remove` for an `absent` entry whose target is still there, or `absent` for a removal that is done. A tracked entry whose variants all select other machines, such as one for an inactive profile, says `not on this machine`. Then shows the history state in sections: Tracking, Repository, Conflicts, Automatic capture, and Bootstrap, ending with the next steps.
#
# Files a dotfile group deployed that no active entry deploys now are listed as `orphaned`: the group was deselected or removed, or a new `exclude` or a deleted source dropped them. `mise dot apply --prune` removes them.
#
# Template entries are rendered to compare their output, so trusted template functions may run. `--json` prints `files`, `edits`, and `history`, with each entry's origin and a state of `applied`, `missing`, `differs`, `source_missing`, or `tracked`. Orphaned files appear in a separate `orphaned` array with the state `orphaned`, or `orphaned_changed` when the file was modified after it was deployed. See https://mise.jdx.dev/dotfiles/reference.html#status-states for every state.
@usage 'alias ls'
@usage r#'long_help #"""
Show the state of your dotfiles and their history

Lists the `[dotfiles]` entries that need attention, and counts the rest; `--verbose` lists every entry. Each has a state: `applied`, `missing`, `differs`, `source missing`, `tracked`, `would remove` for an `absent` entry whose target is still there, or `absent` for a removal that is done. A tracked entry whose variants all select other machines, such as one for an inactive profile, says `not on this machine`. Then shows the history state in sections: Tracking, Repository, Conflicts, Automatic capture, and Bootstrap, ending with the next steps.

Files a dotfile group deployed that no active entry deploys now are listed as `orphaned`: the group was deselected or removed, or a new `exclude` or a deleted source dropped them. `mise dot apply --prune` removes them.

Template entries are rendered to compare their output, so trusted template functions may run. `--json` prints `files`, `edits`, and `history`, with each entry's origin and a state of `applied`, `missing`, `differs`, `source_missing`, or `tracked`. Orphaned files appear in a separate `orphaned` array with the state `orphaned`, or `orphaned_changed` when the file was modified after it was deployed. See https://mise.jdx.dev/dotfiles/reference.html#status-states for every state.
"""#'#
@usage 'flag --truncate help="Truncate long terminal output to fit the available width" negate=--no-truncate default="true"'
@usage 'flag "-J --json" help="Output in JSON format"'
@usage 'flag --missing help="Exit with code 1 if any dotfile is not in its desired state (missing, source missing, or differs)"'
@usage 'flag "-v --verbose" help="List every entry, including those already applied or tracked" {
            long_help #"""
List every entry, including those already applied or tracked

By default the table lists only entries that need attention or have omitted files, with a one-line summary of the rest. Naming targets lists them regardless.
"""#
        }'
@usage 'flag --prompt-secrets help="Prompt for `[bootstrap.secrets]` values that templates need and the environment does not set"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[TARGET]…" help="Only show these targets" required=#false var=#true'
@usage 'example "mise dot status" help="Show what needs attention"'
@usage 'example "mise dot status --verbose" help="List every entry"'
@usage 'example "mise dot status ~/.zshrc" help="Show one target"'
@usage 'example "mise dot status --json" help="Print the state as JSON"'
@usage 'example "mise dot status --missing" help="Exit 1 if anything is out of date, for scripts and CI"'
@usage 'output json framing=json select=--json'
export def "mise dotfiles status" [
    ...target: string,               # Only show these targets
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --truncate,                      # Truncate long terminal output to fit the available width
    --no-truncate,                   # Turn off --truncate
    --missing,                       # Exit with code 1 if any dotfile is not in its desired state (missing, source missing, or differs)
    --prompt-secrets,                # Prompt for `[bootstrap.secrets]` values that templates need and the environment does not set
] {
    ^mise dotfiles status --json ...(nus argv [...$target] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --truncate: $truncate
        --no-truncate: $no_truncate
        --missing: $missing
        --prompt-secrets: $prompt_secrets
    }) | from json
}

# Push saved checkpoints and fetch incoming changes
#
# Fetches the origin branch and pushes your local history to it. If the push is rejected, mise fetches again and reconciles the two histories without rewriting either. Incoming changes and conflicts are recorded for `mise dot pull`; this command never changes your files. With `--fetch-only`, or in `fetch-only` mode, nothing is pushed.
#
# The watcher does this on its own in `sync` and `fetch-only` mode (the `history.sync` setting). See https://mise.jdx.dev/dotfiles/sync.html
@usage 'long_help #"""
Push saved checkpoints and fetch incoming changes

Fetches the origin branch and pushes your local history to it. If the push is rejected, mise fetches again and reconciles the two histories without rewriting either. Incoming changes and conflicts are recorded for `mise dot pull`; this command never changes your files. With `--fetch-only`, or in `fetch-only` mode, nothing is pushed.

The watcher does this on its own in `sync` and `fetch-only` mode (the `history.sync` setting). See https://mise.jdx.dev/dotfiles/sync.html
"""#'
@usage 'flag --fetch-only help="Fetch without pushing"'
@usage 'flag --allow-plaintext-history help="Allow pushing older unencrypted versions of files that are now encrypted, and versions that look like they contain secrets"'
@usage 'flag --best-effort help="Warn instead of failing when the origin is unreachable"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise dot sync" help="Push and fetch now"'
@usage 'example "mise dot sync --fetch-only" help="Fetch without pushing"'
export def "mise dotfiles sync" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --fetch-only,                    # Fetch without pushing
    --allow-plaintext-history,       # Allow pushing older unencrypted versions of files that are now encrypted, and versions that look like they contain secrets
    --best-effort,                   # Warn instead of failing when the origin is unreachable
]: nothing -> string {
    ^mise dotfiles sync ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --fetch-only: $fetch_only
        --allow-plaintext-history: $allow_plaintext_history
        --best-effort: $best_effort
    })
}

# Track a file or directory in place
#
# Adds a `[dotfiles]` entry with `mode = "track"` to your global config: the file stays where it is, nothing is copied or linked, and mise saves a checkpoint of it right away. While the watcher service runs, later edits are saved automatically; without it, `mise dot save` saves them. Use `--dry-run` to see what a large directory would add before tracking it.
#
# `--os` and `--profile` declare a variant: machines that match the platform or config environment keep their own version of the file, so a Mac and a Linux machine can have different contents at the same path. `--machine` gives every machine its own version instead, for files such as a monitor layout that should never be applied on another machine.
#
# See https://mise.jdx.dev/dotfiles/history.html
@usage 'long_help #"""
Track a file or directory in place

Adds a `[dotfiles]` entry with `mode = "track"` to your global config: the file stays where it is, nothing is copied or linked, and mise saves a checkpoint of it right away. While the watcher service runs, later edits are saved automatically; without it, `mise dot save` saves them. Use `--dry-run` to see what a large directory would add before tracking it.

`--os` and `--profile` declare a variant: machines that match the platform or config environment keep their own version of the file, so a Mac and a Linux machine can have different contents at the same path. `--machine` gives every machine its own version instead, for files such as a monitor layout that should never be applied on another machine.

See https://mise.jdx.dev/dotfiles/history.html
"""#'
@usage 'flag --os help="Declare a variant for this platform (macos, linux, linux/arm64, …)" {
            arg <OS>
        }'
@usage 'flag --profile help="Declare a variant for this config environment (`MISE_ENV` or `-E`)" {
            arg <PROFILE>
        }'
@usage r#'flag --local help="Keep this file's history on this machine only; it is never shared"'#
@usage 'flag --machine help="Keep a separate stream on every machine, never applied on another"'
@usage 'flag --no-autosave help="Save only on `mise dot save <path>`, never automatically"'
@usage 'flag --encrypt help="Encrypt contents before saving them to history (requires `[history.encryption] recipients`)"'
@usage 'flag --allow-plaintext help="Save an explicitly tracked credential-named file in plaintext"'
@usage 'flag "-y --yes" help="Accepted for compatibility; track no longer asks to confirm the paths"'
@usage 'flag "-n --dry-run" help="Show what each path expands to (files, size, what is left out) without tracking it"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <PATH>… help="Paths to track (absolute or starting with ~/)" var=#true'
@usage 'example "mise dot track ~/.zshrc ~/.config/hypr" help="Track a file and a directory"'
@usage 'example "mise dot track --dry-run ~/.codex" help="Show what tracking a directory would save"'
@usage 'example "mise dot track ~/.zshrc --os macos" help="Keep a separate version for macOS machines"'
@usage 'example "mise dot track ~/.config/hypr/monitors.lua --machine" help="Keep a separate version on every machine"'
@usage r#'example "mise dot track ~/.config/app/state.json --local" help="Keep the file's history on this machine only"'#
@usage 'example "mise dot track ~/.config/app/credentials --encrypt" help="Encrypt the file before saving it"'
@usage 'example "mise dot track ~/.config/app/state.json --no-autosave" help="Save the file only when you run mise dot save"'
export def "mise dotfiles track" [
    ...path: string,                 # Paths to track (absolute or starting with ~/)
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                  # Show what each path expands to (files, size, what is left out) without tracking it
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --local,                         # Keep this file's history on this machine only; it is never shared
    --os: string,                    # Declare a variant for this platform (macos, linux, linux/arm64, …)
    --machine,                       # Keep a separate stream on every machine, never applied on another
    --no-autosave,                   # Save only on `mise dot save <path>`, never automatically
    --encrypt,                       # Encrypt contents before saving them to history (requires `[history.encryption] recipients`)
    --allow-plaintext,               # Save an explicitly tracked credential-named file in plaintext
]: nothing -> string {
    ^mise dotfiles track ...(nus argv [...$path] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --local: $local
        --os: $os
        --machine: $machine
        --no-autosave: $no_autosave
        --encrypt: $encrypt
        --allow-plaintext: $allow_plaintext
    })
}

# Remove files that `mise dot apply` deployed
#
# Removes the targets of whole-file entries and the blocks and lines that edit entries added, but only what mise can identify as its own. Modified copies, modified templates, and plain-line edits need `--force`. Merged keys, `absent` entries, and permissions-only targets are left alone. Sources and config entries are kept, so run this before you delete a declaration, while mise can still identify its targets.
#
# With `--group`, removes only that dotfile group's files, using what mise recorded when it applied them, so it works even after the group is deselected or deleted from the config.
@usage r#'long_help #"""
Remove files that `mise dot apply` deployed

Removes the targets of whole-file entries and the blocks and lines that edit entries added, but only what mise can identify as its own. Modified copies, modified templates, and plain-line edits need `--force`. Merged keys, `absent` entries, and permissions-only targets are left alone. Sources and config entries are kept, so run this before you delete a declaration, while mise can still identify its targets.

With `--group`, removes only that dotfile group's files, using what mise recorded when it applied them, so it works even after the group is deselected or deleted from the config.
"""#'#
@usage 'flag "-f --force" help="Remove modified or otherwise ambiguous managed files and lines"'
@usage 'flag "-n --dry-run" help="Print the actions that would run without writing anything"'
@usage 'flag "-y --yes" help="Skip the confirmation prompt"'
@usage 'flag --group help="Only unapply the files of this dotfile group, even one that is no longer selected or declared" var=#true {
            arg <NAME>
        }'
@usage 'flag --prompt-secrets help="Prompt for `[bootstrap.secrets]` values that templates need and the environment does not set"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[TARGET]…" help="Only unapply these targets" required=#false var=#true'
@usage 'example "mise dot unapply" help="Remove every target mise can identify"'
@usage 'example "mise dot unapply ~/.zshrc" help="Remove one target"'
@usage r#'example "mise dot unapply --group work" help="Remove one dotfile group's files"'#
@usage 'example "mise dot unapply --dry-run" help="Preview what would be removed"'
@usage 'example "mise dot unapply --force --yes" help="Also remove modified targets, without prompting"'
export def "mise dotfiles unapply" [
    ...target: string,               # Only unapply these targets
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --force (-f),                    # Remove modified or otherwise ambiguous managed files and lines
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                  # Print the actions that would run without writing anything
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --group: list<string>,           # Only unapply the files of this dotfile group, even one that is no longer selected or declared
    --prompt-secrets,                # Prompt for `[bootstrap.secrets]` values that templates need and the environment does not set
]: nothing -> string {
    ^mise dotfiles unapply ...(nus argv [...$target] {
        --cd: $cd
        --env: $env_
        --force: $force
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --group: $group
        --prompt-secrets: $prompt_secrets
    })
}

# Reverse the tracked-file changes from an operation
#
# Restores exactly the paths that an operation changed from the checkpoint it saved first, and leaves everything else as it is now. Without a reference, reverses the newest operation that has not been undone.
#
# Works for operations that changed tracked files: `mise bootstrap`, `mise dot add`, `apply`, `edit`, `unapply`, `capture`, `rollback`, `pull` (including changes the watcher applied), and `undo` itself. Package installations, service state, and untracked files are not reversed.
@usage 'long_help #"""
Reverse the tracked-file changes from an operation

Restores exactly the paths that an operation changed from the checkpoint it saved first, and leaves everything else as it is now. Without a reference, reverses the newest operation that has not been undone.

Works for operations that changed tracked files: `mise bootstrap`, `mise dot add`, `apply`, `edit`, `unapply`, `capture`, `rollback`, `pull` (including changes the watcher applied), and `undo` itself. Package installations, service state, and untracked files are not reversed.
"""#'
@usage 'flag "-n --dry-run" help="Show the plan without changing anything"'
@usage 'flag "-y --yes" help="Apply without prompting"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage r#'arg "[REF]" help="The operation's checkpoint: numeric ID, `latest`, `latest~N`, or `commit:<sha>`" required=#false'#
@usage 'example "mise dot undo" help="Reverse the newest operation"'
@usage 'example "mise dot undo --dry-run" help="Show what would be restored"'
@usage 'example "mise dot undo 42" help="Reverse the operation recorded as checkpoint 42"'
export def "mise dotfiles undo" [
    ref?: string,                    # The operation's checkpoint: numeric ID, `latest`, `latest~N`, or `commit:<sha>`
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                  # Show the plan without changing anything
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise dotfiles undo ...(nus argv [$ref] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Stop tracking a file or directory
#
# Removes the path's `mode = "track"` entry from your global config. When a project or system config declares the entry, mise turns it off on this machine in `config.local.toml` next to your global config instead.
#
# A path inside a tracked directory has no entry of its own: mise adds a rule for it to `[history] exclude` in the global config, and `mise dot include <path>` removes that rule. The file itself and its existing checkpoints are not changed.
@usage r#'long_help #"""
Stop tracking a file or directory

Removes the path's `mode = "track"` entry from your global config. When a project or system config declares the entry, mise turns it off on this machine in `config.local.toml` next to your global config instead.

A path inside a tracked directory has no entry of its own: mise adds a rule for it to `[history] exclude` in the global config, and `mise dot include <path>` removes that rule. The file itself and its existing checkpoints are not changed.
"""#'#
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <PATH>… help="Paths to stop tracking" var=#true'
@usage 'example "mise dot untrack ~/.zshrc" help="Stop saving ~/.zshrc"'
@usage 'example "mise dot untrack ~/.config/hypr/plugins" help="Exclude one directory inside a tracked directory"'
export def "mise dotfiles untrack" [
    ...path: string,                 # Paths to stop tracking
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise dotfiles untrack ...(nus argv [...$path] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Save tracked files as they change
#
# Runs in the foreground and saves a checkpoint once a changed file has been quiet for `history.watch.debounce`. A file that keeps changing does not delay the others and is still saved every `history.watch.max_interval`. The watcher also rescans every tracked path at startup, every `history.watch.reconcile`, and when the configuration changes. Entries tracked with `--no-autosave` are not watched.
#
# With an origin connected, the watcher also syncs according to the `history.sync` setting. In `sync` mode it pushes within `history.sync_interval` of a save, fetches every `history.fetch_interval`, and applies incoming changes when there are no conflicts. In `fetch-only` mode it only fetches; in `manual` mode it does not use the network. A failed sync is retried with backoff while saving continues. `--once` runs one rescan and one sync, then exits.
#
# The built-in `history-watch` service runs this for you:
#
#     [bootstrap.services.mise-history]
#     builtin = "history-watch"
#
# Exits 0 when history is disabled or another watcher is already running, and 1 when Git is unusable, the store cannot be opened, or no watch can be installed. A failed save is retried with backoff and never drops the pending changes, and a save that would overlap another history operation is deferred. With `--once`, nothing is retried: a save that fails or is deferred, or a sync that fails, exits 1.
@usage 'long_help #"""
Save tracked files as they change

Runs in the foreground and saves a checkpoint once a changed file has been quiet for `history.watch.debounce`. A file that keeps changing does not delay the others and is still saved every `history.watch.max_interval`. The watcher also rescans every tracked path at startup, every `history.watch.reconcile`, and when the configuration changes. Entries tracked with `--no-autosave` are not watched.

With an origin connected, the watcher also syncs according to the `history.sync` setting. In `sync` mode it pushes within `history.sync_interval` of a save, fetches every `history.fetch_interval`, and applies incoming changes when there are no conflicts. In `fetch-only` mode it only fetches; in `manual` mode it does not use the network. A failed sync is retried with backoff while saving continues. `--once` runs one rescan and one sync, then exits.

The built-in `history-watch` service runs this for you:

    [bootstrap.services.mise-history]
    builtin = "history-watch"

Exits 0 when history is disabled or another watcher is already running, and 1 when Git is unusable, the store cannot be opened, or no watch can be installed. A failed save is retried with backoff and never drops the pending changes, and a save that would overlap another history operation is deferred. With `--once`, nothing is retried: a save that fails or is deferred, or a sync that fails, exits 1.
"""#'
@usage 'flag --once help="Rescan and sync once, then exit (for timers and cron)"'
@usage 'flag "-J --json" help="Print one JSON object per line instead of log lines"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise dot watch" help="Watch and save until stopped"'
@usage 'example "mise dot watch --once" help="Rescan and sync once, for a timer"'
@usage 'example "mise dot watch --json" help="Print JSON lines instead of log lines"'
@usage 'output json framing=json select=--json'
export def "mise dotfiles watch" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --once,                          # Rescan and sync once, then exit (for timers and cron)
] {
    ^mise dotfiles watch --json ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --once: $once
    }) | from json
}

# Check your mise setup for problems
#
# Prints mise's version, whether shell activation and shims are set up, its
# directories, the config files, tools, and environment in use, and its settings,
# then lists any problems and warnings with a suggested fix. Exits with status 1
# when it finds a problem. Include this output when you report a bug.
@usage 'alias dr'
@usage r#'long_help #"""
Check your mise setup for problems

Prints mise's version, whether shell activation and shims are set up, its
directories, the config files, tools, and environment in use, and its settings,
then lists any problems and warnings with a suggested fix. Exits with status 1
when it finds a problem. Include this output when you report a bug.
"""#'#
@usage 'flag "-J --json" help="Output in JSON format"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise doctor" help="Check the setup and list problems"'
@usage 'example "mise doctor --json" help="Print the report as JSON"'
@usage 'output json framing=json select=--json'
export def "mise doctor" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
] {
    ^mise doctor --json ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    }) | from json
}

# Print the directories mise adds to PATH
#
# Lists tool bin directories and `_.path` entries from [env]. --full prints the
# whole PATH mise would set. `mise bin-paths` lists tool bin directories only.
@usage 'alias paths'
@usage 'long_help #"""
Print the directories mise adds to PATH

Lists tool bin directories and `_.path` entries from [env]. --full prints the
whole PATH mise would set. `mise bin-paths` lists tool bin directories only.
"""#'
@usage 'flag "-f --full" help="Print every PATH entry, including those mise does not provide"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example #"""
mise doctor path
/home/user/.local/share/mise/installs/node/24.11.0/bin
/home/user/.local/share/mise/installs/python/3.13.1/bin
"""# help="Print the directories mise adds to PATH"'
@usage 'example "mise doctor path --full" help="Print the whole PATH mise would set"'
export def "mise doctor path" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --full (-f),                     # Print every PATH entry, including those mise does not provide
]: nothing -> string {
    ^mise doctor path ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --full: $full
    })
}

# Run the project's diagnostic checks
#
# Checks are declared in `[doctor.checks.<name>]` tables in mise.toml. Each command
# runs with the project's installed tools and environment. Checks should inspect
# state; mise does not sandbox them or run their suggested remedies. Exits with
# status 1 when a check fails. See
# https://mise.jdx.dev/configuration/project-diagnostics.html.
@usage r#'long_help #"""
Run the project's diagnostic checks

Checks are declared in `[doctor.checks.<name>]` tables in mise.toml. Each command
runs with the project's installed tools and environment. Checks should inspect
state; mise does not sandbox them or run their suggested remedies. Exits with
status 1 when a check fails. See
https://mise.jdx.dev/configuration/project-diagnostics.html.
"""#'#
@usage 'flag "-J --json" help="Output the complete report as JSON"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise doctor project" help="Run every check and report pass or fail"'
@usage 'example "mise doctor project --json" help="Print the report as JSON"'
@usage 'output "json" framing="json" select="--json" {
    schema "{\n  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",\n  \"title\": \"mise doctor project --json\",\n  \"type\": \"object\",\n  \"properties\": {\n    \"errors\": {\n      \"type\": \"array\",\n      \"items\": {\n        \"type\": \"string\"\n      }\n    },\n    \"checks\": {\n      \"type\": \"array\",\n      \"items\": {\n        \"type\": \"object\",\n        \"properties\": {\n          \"name\": {\n            \"type\": \"string\"\n          },\n          \"description\": {\n            \"type\": [\n              \"string\",\n              \"null\"\n            ]\n          },\n          \"source\": {\n            \"type\": [\n              \"string\",\n              \"null\"\n            ]\n          },\n          \"status\": {\n            \"enum\": [\n              \"pass\",\n              \"fail\",\n              \"error\",\n              \"skipped\",\n              \"blocked\"\n            ]\n          },\n          \"message\": {\n            \"type\": [\n              \"string\",\n              \"null\"\n            ]\n          },\n          \"hint\": {\n            \"type\": [\n              \"string\",\n              \"null\"\n            ]\n          }\n        },\n        \"required\": [\n          \"name\",\n          \"description\",\n          \"source\",\n          \"status\",\n          \"message\",\n          \"hint\"\n        ],\n        \"additionalProperties\": false\n      }\n    }\n  },\n  \"required\": [\n    \"errors\",\n    \"checks\"\n  ],\n  \"additionalProperties\": false\n}\n"
}'
export def "mise doctor project" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> record<errors: list<string>, checks: table<name: string, description: oneof<string, nothing>, source: oneof<string, nothing>, status: string, message: oneof<string, nothing>, hint: oneof<string, nothing>>> {
    let text = ^mise doctor project --json ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
    nus decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"title\":\"mise doctor project --json\",\"type\":\"object\",\"properties\":{\"errors\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}},\"checks\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"},\"description\":{\"type\":[\"string\",\"null\"]},\"source\":{\"type\":[\"string\",\"null\"]},\"status\":{\"enum\":[\"pass\",\"fail\",\"error\",\"skipped\",\"blocked\"]},\"message\":{\"type\":[\"string\",\"null\"]},\"hint\":{\"type\":[\"string\",\"null\"]}},\"required\":[\"name\",\"description\",\"source\",\"status\",\"message\",\"hint\"],\"additionalProperties\":false}}},\"required\":[\"errors\",\"checks\"],\"additionalProperties\":false}" { from json }
}

# Start a subshell with mise's tools and environment
#
# This is an alternative to `mise activate` for starting a mise session explicitly.
# The new shell has the tools and environment variables from the config loaded.
# Unlike an activated shell, changing directories does not update the environment.
# Type `exit` to leave it.
@usage r#'long_help #"""
Start a subshell with mise's tools and environment

This is an alternative to `mise activate` for starting a mise session explicitly.
The new shell has the tools and environment variables from the config loaded.
Unlike an activated shell, changing directories does not update the environment.
Type `exit` to leave it.
"""#'#
@usage 'flag "-s --shell" help="Shell to start; defaults to $SHELL" {
        arg <SHELL>
    }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[DIR]" help="Directory to start the shell in" required=#false default=.'
@usage r#'example "mise en" help="Start a shell with the project's tools and environment"'#
@usage 'example "mise en ~/work/api" help="Start the shell in another project"'
@usage 'example "mise en -s \"bash --norc\"" help="Skip loading .bashrc"'
@usage 'example "mise en -s \"zsh -f\"" help="Skip loading .zshrc"'
@usage 'complete dir type=dir'
export def "mise en" [
    dir?: path@"nus complete",       # Directory to start the shell in
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --shell (-s): string,            # Shell to start; defaults to $SHELL
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise en ...(nus argv [$dir] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --shell: $shell
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Print the environment for the current configuration
#
# Evaluate the shell output to load tools and variables once, without installing
# prompt hooks. Changing directories afterward does not recompute this environment.
# Use `mise exec -- command` to apply it to one child process instead.
#
# JSON, dotenv, and shell output contain actual variable values, including secrets.
# `--redacted` selects variables marked for redaction; it does not mask their values.
# Tools you pass as TOOL@VERSION arguments are installed first if they are missing;
# missing tools from the config are reported, not installed.
@usage 'alias e'
@usage 'long_help #"""
Print the environment for the current configuration

Evaluate the shell output to load tools and variables once, without installing
prompt hooks. Changing directories afterward does not recompute this environment.
Use `mise exec -- command` to apply it to one child process instead.

JSON, dotenv, and shell output contain actual variable values, including secrets.
`--redacted` selects variables marked for redaction; it does not mask their values.
Tools you pass as TOOL@VERSION arguments are installed first if they are missing;
missing tools from the config are reported, not installed.
"""#'
@usage 'flag "-D --dotenv" help="Output in dotenv format" overrides=--shell'
@usage 'flag "-J --json" help="Output in JSON format" overrides=--shell'
@usage 'flag "-s --shell" help="Shell type to generate environment variables for" overrides=--json {
        arg <SHELL> {
            choices {
                choice bash
                choice elvish
                choice fish
                choice nu
                choice xonsh
                choice zsh
                choice pwsh {
                    alias powershell
                }
            }
        }
    }'
@usage 'flag --json-extended help="Output in JSON format with additional information (source, tool)" overrides=--shell'
@usage 'flag --redacted help="Only include variables marked for redaction; their values are printed unmasked"'
@usage 'flag --values help="Only show values of environment variables"'
@usage 'flag --paths help="Print the PATH entries mise manages, in PATH order, one per line"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[TOOL@VERSION]…" help="Tools to include in addition to those in the config, such as `node@24`" required=#false var=#true'
@usage 'example "eval \"$(mise env -s bash)\"" help="Load the environment once into the current bash session"'
@usage 'example "eval \"$(mise env -s zsh)\"" help="Same, for zsh"'
@usage 'example "mise env -s fish | source" help="Same, for fish"'
@usage 'example "execx($(mise env -s xonsh))" help="Same, for xonsh"'
@usage 'example "mise env --json" help="Print the variables as JSON"'
@usage 'example "mise env --paths" help="List the PATH entries mise manages, such as tool bin directories"'
@usage 'example "mise env --dotenv > .env" help="Write a dotenv file; it contains secret values"'
@usage 'output "json" framing="json" select="--json" {
    schema "{\n  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",\n  \"type\": \"object\",\n  \"additionalProperties\": {\n    \"type\": \"string\"\n  }\n}\n"
}'
export def "mise env" [
    ...tool_version: string@"nus complete",                     # Tools to include in addition to those in the config, such as `node@24`
    --cd (-C): path@"nus complete",                             # Run as if mise were started in DIR
    --env_ (-E): list<string>,                                  # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                                        # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                                               # Suppress non-error messages
    --shell (-s): string@[bash elvish fish nu xonsh zsh pwsh],  # Shell type to generate environment variables for
    --verbose (-v): int,                                        # Show extra output (use -vv for even more)
    --yes (-y),                                                 # Answer yes to all confirmation prompts
    --raw,                                                      # Connect tasks and install commands directly to the terminal
    --locked,                                                   # Require download URLs from the lockfile when installing
    --silent,                                                   # Suppress all task output and mise non-error messages
    --dotenv (-D),                                              # Output in dotenv format
    --json-extended,                                            # Output in JSON format with additional information (source, tool)
    --redacted,                                                 # Only include variables marked for redaction; their values are printed unmasked
    --values,                                                   # Only show values of environment variables
    --paths,                                                    # Print the PATH entries mise manages, in PATH order, one per line
]: nothing -> record {
    let text = ^mise env --json ...(nus argv [...$tool_version] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --shell: $shell
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --dotenv: $dotenv
        --json-extended: $json_extended
        --redacted: $redacted
        --values: $values
        --paths: $paths
    })
    nus decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":\"object\",\"additionalProperties\":{\"type\":\"string\"}}" { from json }
}

# Run a command with mise's tools and environment
#
# Loads the tools and [env] from your config into one child process without
# changing the current shell. Use it in scripts and CI, or to run a tool that is
# not in the config.
#
# TOOL@VERSION arguments add tools or override the configured version of that
# tool only: with `node = "24"` in mise.toml, `mise exec python@3.13 -- python -V`
# still has node 24 on PATH.
#
# Put the command after `--`, or pass a shell command string with `-c`. Missing
# tools are installed first unless the `exec_auto_install` or `auto_install`
# setting is off; when you name tools, only those are installed. The --allow-* and
# --deny-* flags sandbox the command; see https://mise.jdx.dev/sandboxing.html.
@usage 'alias x'
@usage r#'long_help #"""
Run a command with mise's tools and environment

Loads the tools and [env] from your config into one child process without
changing the current shell. Use it in scripts and CI, or to run a tool that is
not in the config.

TOOL@VERSION arguments add tools or override the configured version of that
tool only: with `node = "24"` in mise.toml, `mise exec python@3.13 -- python -V`
still has node 24 on PATH.

Put the command after `--`, or pass a shell command string with `-c`. Missing
tools are installed first unless the `exec_auto_install` or `auto_install`
setting is off; when you name tools, only those are installed. The --allow-* and
--deny-* flags sandbox the command; see https://mise.jdx.dev/sandboxing.html.
"""#'#
@usage 'flag "-c --command" help="Command string to run through a shell (supports pipes and redirection)" conflicts=COMMAND {
        arg <COMMAND>
    }'
@usage 'flag "-j --jobs" help="How many tools to install in parallel; defaults to the `jobs` setting" env=MISE_JOBS {
        long_help #"""
How many tools to install in parallel; defaults to the `jobs` setting

Values below 1 are treated as 1.
"""#
        arg <JOBS>
    }'
@usage r#'flag --allow-env help="Pass only VAR through from the environment (implies --deny-env)" var=#true {
        long_help #"""
Pass only VAR through from the environment (implies --deny-env)

Supports wildcards, such as --allow-env='MYAPP_*'.
"""#
        arg <VAR>
    }'#
@usage 'flag --allow-net help="Allow network access only to HOST (not supported on any platform)" var=#true {
        long_help #"""
Allow network access only to HOST (not supported on any platform)

Per-host filtering does not work: Linux and macOS exit with an error,
and Windows runs the command without network restrictions. See
https://mise.jdx.dev/sandboxing.html#access-to-particular-hosts
"""#
        arg <HOST>
    }'
@usage 'flag --allow-read help="Allow reads from PATH (implies --deny-read for everything else)" var=#true {
        arg <PATH>
    }'
@usage 'flag --allow-write help="Allow writes to PATH (implies --deny-write for everything else)" var=#true {
        arg <PATH>
    }'
@usage 'flag --deny-all help="Block reads, writes, network, and env vars"'
@usage 'flag --deny-env help="Block env var inheritance except PATH, HOME, USER, SHELL, TERM, COLORTERM, LANG" {
        long_help #"""
Block env var inheritance except PATH, HOME, USER, SHELL, TERM, COLORTERM, LANG

On Windows it also keeps the variables programs need to start, such as
SystemRoot and TEMP.
"""#
    }'
@usage 'flag --deny-net help="Block all network access"'
@usage 'flag --deny-read help="Block filesystem reads (system libs and tool dirs still accessible)"'
@usage 'flag --deny-write help="Block filesystem writes except temporary and device paths (/tmp, /dev)"'
@usage 'flag --fresh-env help="Bypass the environment cache and recompute the environment"'
@usage 'flag --no-deps help="Skip automatic dependency preparation"'
@usage 'flag --raw help="Connect install commands directly to the terminal; implies --jobs=1" overrides=--jobs'
@usage 'flag --secrets help="[experimental] Give the command these secrets (comma-separated); by default it gets none" var=#true {
        arg <SECRET> delimiter=,
    }'
@usage 'flag --secrets-all help="[experimental] Give the command every secret the project can inject, except file secrets" conflicts=--secrets'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[TOOL@VERSION]…" help="Tools to add or override, such as `node@24 python@3.13`" required=#false var=#true'
@usage 'arg "[-- COMMAND]…" help="Executable and arguments to run directly, after `--`" required=#false var=#true conflicts=--command required_unless=--command'
@usage 'example "mise exec node@24 -- node ./app.js" help="Run app.js with node 24"'
@usage 'example "mise x node@24 python@3.13 -c \"node -v && python -V\"" help="Run a shell command string"'
@usage r#'example "mise x -C ~/work/api -- npm test" help="Run in another project's directory"'#
@usage 'example "mise x --deny-net -- npm run build" help="Run without network access"'
@usage r#'example "mise x --secrets GH_TOKEN -- gh release list" help="[experimental] Pass one secret from the project's secrets source"'#
@usage 'complete command type=command'
export def "mise exec" [
    ...tool_version: string@"nus complete",  # Tools to add or override, such as `node@24 python@3.13`
    --cd (-C): path@"nus complete",          # Run as if mise were started in DIR
    --env_ (-E): list<string>,               # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                     # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                            # Suppress non-error messages
    --verbose (-v): int,                     # Show extra output (use -vv for even more)
    --yes (-y),                              # Answer yes to all confirmation prompts
    --raw,                                   # Connect tasks and install commands directly to the terminal
    --locked,                                # Require download URLs from the lockfile when installing
    --silent,                                # Suppress all task output and mise non-error messages
    --command (-c): string@"nus complete",   # Command string to run through a shell (supports pipes and redirection)
    --allow-env: list<string>,               # Pass only VAR through from the environment (implies --deny-env)
    --allow-net: list<string>,               # Allow network access only to HOST (not supported on any platform)
    --allow-read: list<string>,              # Allow reads from PATH (implies --deny-read for everything else)
    --allow-write: list<string>,             # Allow writes to PATH (implies --deny-write for everything else)
    --deny-all,                              # Block reads, writes, network, and env vars
    --deny-env,                              # Block env var inheritance except PATH, HOME, USER, SHELL, TERM, COLORTERM, LANG
    --deny-net,                              # Block all network access
    --deny-read,                             # Block filesystem reads (system libs and tool dirs still accessible)
    --deny-write,                            # Block filesystem writes except temporary and device paths (/tmp, /dev)
    --fresh-env,                             # Bypass the environment cache and recompute the environment
    --no-deps,                               # Skip automatic dependency preparation
    --secrets: list<string>@"nus complete",  # [experimental] Give the command these secrets (comma-separated); by default it gets none
    --secrets-all,                           # [experimental] Give the command every secret the project can inject, except file secrets
]: nothing -> string {
    ^mise exec ...(nus argv [...$tool_version] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --command: $command
        --allow-env: $allow_env
        --allow-net: $allow_net
        --allow-read: $allow_read
        --allow-write: $allow_write
        --deny-all: $deny_all
        --deny-env: $deny_env
        --deny-net: $deny_net
        --deny-read: $deny_read
        --deny-write: $deny_write
        --fresh-env: $fresh_env
        --no-deps: $no_deps
        --secrets: $secrets
        --secrets-all: $secrets_all
    })
}

# Format mise TOML configuration
#
# Formats the config files in the current directory in place; --all formats every
# config file mise loads. Use --check in CI to fail when a file is not formatted,
# or --stdin to format a document from stdin to stdout.
#
# Formatting normalizes whitespace and writes TOML 1.1 syntax, including multiline
# inline tables. Top-level entries written as plain, dotted, or inline-table keys
# go in a standard order: min_version, env_file, env_path, _, env, vars, hooks,
# watch_files, tools, other keys, tasks, task_config, redactions, alias, plugins,
# settings. `[table]` sections and the keys inside any table keep the order they
# were written in.
#
# Lists whose order has no effect are sorted: task `sources` and `outputs`,
# `task_config.global_inputs` and `input_groups`, and `redactions`. File pattern
# lists put `@group:` references first, then globs, then literal paths. A list
# with a `!` exclusion or a comment is left as written.
@usage 'long_help #"""
Format mise TOML configuration

Formats the config files in the current directory in place; --all formats every
config file mise loads. Use --check in CI to fail when a file is not formatted,
or --stdin to format a document from stdin to stdout.

Formatting normalizes whitespace and writes TOML 1.1 syntax, including multiline
inline tables. Top-level entries written as plain, dotted, or inline-table keys
go in a standard order: min_version, env_file, env_path, _, env, vars, hooks,
watch_files, tools, other keys, tasks, task_config, redactions, alias, plugins,
settings. `[table]` sections and the keys inside any table keep the order they
were written in.

Lists whose order has no effect are sorted: task `sources` and `outputs`,
`task_config.global_inputs` and `input_groups`, and `redactions`. File pattern
lists put `@group:` references first, then globs, then literal paths. A list
with a `!` exclusion or a comment is left as written.
"""#'
@usage 'flag "-a --all" help="Format every config file mise loads, not only those in the current directory"'
@usage 'flag "-c --check" help="Check whether the configs are formatted without rewriting them; exits 1 if any are not"'
@usage 'flag "-s --stdin" help="Format TOML from stdin and print it to stdout, without touching any file"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise fmt" help="Format the config files in the current directory"'
@usage 'example "mise fmt --check" help="Exit 1 if any config file needs formatting"'
@usage 'example "mise fmt --stdin < mise.toml" help="Print a formatted copy without changing the file"'
export def "mise fmt" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --all (-a),                      # Format every config file mise loads, not only those in the current directory
    --check (-c),                    # Check whether the configs are formatted without rewriting them; exits 1 if any are not
    --stdin (-s),                    # Format TOML from stdin and print it to stdout, without touching any file
]: nothing -> string {
    ^mise fmt ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --all: $all
        --check: $check
        --stdin: $stdin
    })
}

# Generate project files such as CI workflows, git hooks, and scripts
@usage 'alias gen g'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise generate" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise generate ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Generate a mise.toml file
#
# Same as `mise edit`, which has the details. It opens the interactive editor, or
# without an interactive terminal (or with --yes) writes a commented starter
# template. If PATH already exists it stops with an error rather than replace
# the file; pass --force to replace it.
@usage 'long_help #"""
Generate a mise.toml file

Same as `mise edit`, which has the details. It opens the interactive editor, or
without an interactive terminal (or with --yes) writes a commented starter
template. If PATH already exists it stops with an error rather than replace
the file; pass --force to replace it.
"""#'
@usage 'flag "-g --global" help="Generate the global config file (~/.config/mise/config.toml)" conflicts=PATH'
@usage 'flag "-n --dry-run" help="Print the result instead of writing it to the file"'
@usage 'flag "-f --force" help="Replace an existing file with the starter template when not opening the editor"'
@usage 'flag "-t --tool-versions" help="Copy the tools from this .tool-versions file into the config, without opening the editor" {
            arg <FILE>
        }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[PATH]" help="Config file to edit or create; defaults to mise.toml" required=#false'
@usage 'example "mise generate config" help="Edit mise.toml in the current directory"'
@usage 'example "mise generate config -n" help="Print the result instead of writing it"'
@usage 'complete path type=path'
@usage 'complete file type=path'
export def "mise generate config" [
    path?: path@"nus complete",                 # Config file to edit or create; defaults to mise.toml
    --cd (-C): path@"nus complete",             # Run as if mise were started in DIR
    --env_ (-E): list<string>,                  # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --force (-f),                               # Replace an existing file with the starter template when not opening the editor
    --jobs (-j): string,                        # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                             # Print the result instead of writing it to the file
    --quiet (-q),                               # Suppress non-error messages
    --verbose (-v): int,                        # Show extra output (use -vv for even more)
    --yes (-y),                                 # Answer yes to all confirmation prompts
    --raw,                                      # Connect tasks and install commands directly to the terminal
    --locked,                                   # Require download URLs from the lockfile when installing
    --silent,                                   # Suppress all task output and mise non-error messages
    --global (-g),                              # Generate the global config file (~/.config/mise/config.toml)
    --tool-versions (-t): path@"nus complete",  # Copy the tools from this .tool-versions file into the config, without opening the editor
]: nothing -> string {
    ^mise generate config ...(nus argv [$path] {
        --cd: $cd
        --env: $env_
        --force: $force
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --global: $global
        --tool-versions: $tool_versions
    })
}

# Generate a devcontainer configuration that installs mise and the project's tools
#
# Prints JSON by default. `--write` saves .devcontainer/devcontainer.json in the
# repository root (or the current directory outside a git repository), replacing
# an existing file. Review the image, mounts, and setup commands before opening it.
@usage r#'long_help #"""
Generate a devcontainer configuration that installs mise and the project's tools

Prints JSON by default. `--write` saves .devcontainer/devcontainer.json in the
repository root (or the current directory outside a git repository), replacing
an existing file. Review the image, mounts, and setup commands before opening it.
"""#'#
@usage 'flag "-i --image" help="Base image; defaults to mcr.microsoft.com/devcontainers/base:ubuntu" {
            arg <IMAGE>
        }'
@usage 'flag "-m --mount-mise-data" help="Keep installed tools in a `mise-data-volume` Docker volume so they survive rebuilds" {
            long_help #"""
Keep installed tools in a `mise-data-volume` Docker volume so they survive rebuilds

Mounts the volume at /mnt/mise-data, sets MISE_DATA_DIR to it, and adds its
shims directory to PATH.
"""#
        }'
@usage 'flag "-n --name" help="Container name; defaults to mise" {
            arg <NAME>
        }'
@usage 'flag "-w --write" help="Write to .devcontainer/devcontainer.json instead of printing"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise generate devcontainer" help="Print the configuration"'
@usage 'example "mise generate devcontainer --mount-mise-data --write" help="Keep installed tools in a volume and save .devcontainer/devcontainer.json"'
export def "mise generate devcontainer" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --image (-i): string,            # Base image; defaults to mcr.microsoft.com/devcontainers/base:ubuntu
    --mount-mise-data (-m),          # Keep installed tools in a `mise-data-volume` Docker volume so they survive rebuilds
    --name (-n): string,             # Container name; defaults to mise
    --write (-w),                    # Write to .devcontainer/devcontainer.json instead of printing
]: nothing -> string {
    ^mise generate devcontainer ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --image: $image
        --mount-mise-data: $mount_mise_data
        --name: $name
        --write: $write
    })
}

# Generate a git hook that runs a mise task
#
# The hook runs `mise run <TASK>` (default `pre-commit`) with the staged file names
# in the STAGED environment variable. It prints the hook unless you pass --write,
# which saves it in the repository's hooks directory and makes it executable.
#
# For hooks that git gives a message file (commit-msg, prepare-commit-msg,
# applypatch-msg, sendemail-validate), the task gets that file as an argument.
# Other hook arguments, such as a pre-push hook's remote name and URL, are not
# passed on.
#
# For a full git hook manager, see hk: https://hk.jdx.dev
@usage 'alias pre-commit'
@usage r#'long_help #"""
Generate a git hook that runs a mise task

The hook runs `mise run <TASK>` (default `pre-commit`) with the staged file names
in the STAGED environment variable. It prints the hook unless you pass --write,
which saves it in the repository's hooks directory and makes it executable.

For hooks that git gives a message file (commit-msg, prepare-commit-msg,
applypatch-msg, sendemail-validate), the task gets that file as an argument.
Other hook arguments, such as a pre-push hook's remote name and URL, are not
passed on.

For a full git hook manager, see hk: https://hk.jdx.dev
"""#'#
@usage 'flag "-t --task" help="The task to run when the hook is triggered" default=pre-commit {
            arg <TASK>
        }'
@usage 'flag "-w --write" help="Write the hook to the hooks directory and make it executable" {
            long_help #"""
Write the hook to the hooks directory and make it executable

The hooks directory is `.git/hooks`, or `core.hooksPath` when it is set. An existing hook of the same name is moved to `<HOOK>.old`.
"""#
        }'
@usage 'flag --hook help="Which git hook to write, such as pre-push" default=pre-commit {
            arg <HOOK>
        }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[-- MISE_ARG]…" help="mise flags to embed in the generated hook, given after `--`" help_long=#"""
mise flags to embed in the generated hook, given after `--`

These are inserted between `mise` and `run`, so the hook carries the same context you
would pass on the command line. Useful when the config is not at the repository root,
since git runs hooks from the top level: `-- -C subdir` makes the hook find it.
"""# required=#false var=#true'
@usage 'example "mise generate git-pre-commit --write --task=pre-commit" help="Install the hook; each commit then runs `mise run pre-commit`"'
@usage 'example "mise generate git-pre-commit --write -- -C subdir" help="Use the config in subdir, since git runs hooks from the repository root"'
export def "mise generate git-pre-commit" [
    ...mise_arg: string,                 # mise flags to embed in the generated hook, given after `--`
    --cd (-C): path@"nus complete",      # Run as if mise were started in DIR
    --env_ (-E): list<string>,           # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                 # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                        # Suppress non-error messages
    --verbose (-v): int,                 # Show extra output (use -vv for even more)
    --yes (-y),                          # Answer yes to all confirmation prompts
    --raw,                               # Connect tasks and install commands directly to the terminal
    --locked,                            # Require download URLs from the lockfile when installing
    --silent,                            # Suppress all task output and mise non-error messages
    --task (-t): string@"nus complete",  # The task to run when the hook is triggered
    --write (-w),                        # Write the hook to the hooks directory and make it executable
    --hook: string,                      # Which git hook to write, such as pre-push
]: nothing -> string {
    ^mise generate git-pre-commit ...(nus argv [...$mise_arg] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --task: $task
        --write: $write
        --hook: $hook
    })
}

# Generate a GitHub Actions workflow that runs a mise task
#
# The workflow runs the task named by --task on pull requests, tags, manual
# dispatch, and pushes to the current branch. It prints YAML unless you pass
# --write, which saves `.github/workflows/<NAME>.yml` in the repository root and
# replaces an existing file. Define the task and review the triggers before
# committing the workflow.
@usage 'long_help #"""
Generate a GitHub Actions workflow that runs a mise task

The workflow runs the task named by --task on pull requests, tags, manual
dispatch, and pushes to the current branch. It prints YAML unless you pass
--write, which saves `.github/workflows/<NAME>.yml` in the repository root and
replaces an existing file. Define the task and review the triggers before
committing the workflow.
"""#'
@usage 'flag "-t --task" help="The task to run when the workflow is triggered" default=ci {
            arg <TASK>
        }'
@usage 'flag "-w --write" help="Write the workflow to `.github/workflows/<NAME>.yml` instead of printing it"'
@usage 'flag --name help="Name of the workflow and its file" default=ci {
            arg <NAME>
        }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise generate github-action" help="Print a workflow that runs the ci task"'
@usage 'example "mise generate github-action --write" help="Save it as .github/workflows/ci.yml"'
@usage 'example "mise generate github-action --task lint --name lint --write" help="Save a workflow that runs the lint task as .github/workflows/lint.yml"'
export def "mise generate github-action" [
    --cd (-C): path@"nus complete",      # Run as if mise were started in DIR
    --env_ (-E): list<string>,           # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                 # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                        # Suppress non-error messages
    --verbose (-v): int,                 # Show extra output (use -vv for even more)
    --yes (-y),                          # Answer yes to all confirmation prompts
    --raw,                               # Connect tasks and install commands directly to the terminal
    --locked,                            # Require download URLs from the lockfile when installing
    --silent,                            # Suppress all task output and mise non-error messages
    --task (-t): string@"nus complete",  # The task to run when the workflow is triggered
    --write (-w),                        # Write the workflow to `.github/workflows/<NAME>.yml` instead of printing it
    --name: string,                      # Name of the workflow and its file
]: nothing -> string {
    ^mise generate github-action ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --task: $task
        --write: $write
        --name: $name
    })
}

# Generate a script that downloads and runs a pinned mise
#
# Commit the script, for example as bin/mise, so contributors and CI can run
# `./bin/mise install` without installing mise first. On first run it downloads
# the pinned mise version into the mise data directory, or into the project with
# --localize, then runs it with the arguments it was given.
#
# `mise generate bootstrap` is a deprecated alias for this command and will be
# removed in mise 2027.9.0.
@usage 'long_help #"""
Generate a script that downloads and runs a pinned mise

Commit the script, for example as bin/mise, so contributors and CI can run
`./bin/mise install` without installing mise first. On first run it downloads
the pinned mise version into the mise data directory, or into the project with
--localize, then runs it with the arguments it was given.

`mise generate bootstrap` is a deprecated alias for this command and will be
removed in mise 2027.9.0.
"""#'
@usage 'flag "-l --localize" help="Keep mise data and cache in a project-local directory (`.mise` by default)" {
            long_help #"""
Keep mise data and cache in a project-local directory (`.mise` by default)

Use `--localized-dir` to choose its location. This isolates mise state;
it is not an OS sandbox for commands the generated script runs.
"""#
        }'
@usage 'flag "-V --version" help="mise version to pin; defaults to the release `mise self-update` would install" {
            arg <VERSION>
        }'
@usage 'flag "-w --write" help="Write the script to PATH (./bin/mise when no path is given) and make it executable, instead of printing it" value_optional=#true default_missing="./bin/mise" {
            arg "[PATH]" required=#false var_min=0 var_max=1
        }'
@usage 'flag --localized-dir help="Directory for mise data when using --localize, relative to the project" default=.mise {
            arg <DIR>
        }'
@usage 'flag --windows help="Also write a Windows launcher, `<PATH>.cmd`" requires=--write {
            long_help #"""
Also write a Windows launcher, `<PATH>.cmd`

Windows cannot run the bash script. Generate the launcher on any OS and commit
it for contributors on Windows. Requires --write.
"""#
        }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise generate install-script --write ./bin/mise" help="Write ./bin/mise; on first run it downloads the pinned mise, then runs it"'
@usage 'example "mise generate install-script --localize --write ./bin/mise" help="Keep mise and its tools in .mise inside the project"'
@usage 'example "mise generate install-script --write ./bin/mise --windows" help="Also write bin/mise.cmd for contributors on Windows"'
@usage 'complete dir type=dir'
export def "mise generate install-script" [
    --cd (-C): path@"nus complete",        # Run as if mise were started in DIR
    --env_ (-E): list<string>,             # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                   # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                          # Suppress non-error messages
    --verbose (-v): int,                   # Show extra output (use -vv for even more)
    --version (-V): string,                # mise version to pin; defaults to the release `mise self-update` would install
    --yes (-y),                            # Answer yes to all confirmation prompts
    --raw,                                 # Connect tasks and install commands directly to the terminal
    --locked,                              # Require download URLs from the lockfile when installing
    --silent,                              # Suppress all task output and mise non-error messages
    --localize (-l),                       # Keep mise data and cache in a project-local directory (`.mise` by default)
    --write (-w): string,                  # Write the script to PATH (./bin/mise when no path is given) and make it executable, instead of printing it
    --localized-dir: path@"nus complete",  # Directory for mise data when using --localize, relative to the project
    --windows,                             # Also write a Windows launcher, `<PATH>.cmd`
]: nothing -> string {
    ^mise generate install-script ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --version: $version
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --localize: $localize
        --write: $write
        --localized-dir: $localized_dir
        --windows: $windows
    })
}

# Generate Markdown documentation for project tasks
#
# Documents the tasks defined for the current directory. Prints to stdout by
# default. Use `--output` to write a file, `--inject` to replace a marked section,
# or `--multi` for one file per task.
@usage 'long_help #"""
Generate Markdown documentation for project tasks

Documents the tasks defined for the current directory. Prints to stdout by
default. Use `--output` to write a file, `--inject` to replace a marked section,
or `--multi` for one file per task.
"""#'
@usage 'flag "-i --inject" help="Replace the marked section of the --output file" {
            long_help #"""
Replace the marked section of the --output file

Replaces everything between `<!-- mise-tasks -->` and `<!-- /mise-tasks -->`
in the --output file, so you can rerun it to update the docs. The file must
already contain both markers; mise reports an error and leaves the file
unchanged if either is missing.
"""#
        }'
@usage 'flag "-I --index" help="Write only an index of tasks, intended for use with `--multi`"'
@usage 'flag "-m --multi" help="Render each task as a separate document; requires `--output` to be a directory"'
@usage 'flag "-o --output" help="Write the generated docs to a file or directory" {
            arg <PATH>
        }'
@usage 'flag "-r --root" help="Has no effect; tasks always come from the current directory" hide=#true {
            arg <ROOT>
        }'
@usage 'flag "-s --style" help="Has no effect; both styles produce the same output" hide=#true default=simple {
            arg <STYLE> {
                choices {
                    choice simple
                    choice detailed
                }
            }
        }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise generate task-docs" help="Print the task documentation"'
@usage 'example "mise generate task-docs --output TASKS.md" help="Write the task documentation to TASKS.md"'
@usage 'example "mise generate task-docs --inject --output README.md" help="Update the marked section of README.md"'
@usage 'complete root type=dir'
export def "mise generate task-docs" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --output (-o): string,           # Write the generated docs to a file or directory
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --inject (-i),                   # Replace the marked section of the --output file
    --index (-I),                    # Write only an index of tasks, intended for use with `--multi`
    --multi (-m),                    # Render each task as a separate document; requires `--output` to be a directory
]: nothing -> string {
    ^mise generate task-docs ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --output: $output
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --inject: $inject
        --index: $index
        --multi: $multi
    })
}

# Generate scripts that run mise tasks
#
# Writes one executable stub per task into a directory, such as `bin/test` for
# the `test` task, that runs the task with mise. Pair them with
# `mise generate install-script` so contributors can run tasks without installing
# mise. When a task has subtasks, the parent's stub is written to
# `<parent>/_default`.
#
# Hidden tasks and global tasks are skipped: the stubs are committed to the
# project, and global tasks come from each user's own config.
@usage r#'long_help #"""
Generate scripts that run mise tasks

Writes one executable stub per task into a directory, such as `bin/test` for
the `test` task, that runs the task with mise. Pair them with
`mise generate install-script` so contributors can run tasks without installing
mise. When a task has subtasks, the parent's stub is written to
`<parent>/_default`.

Hidden tasks and global tasks are skipped: the stubs are committed to the
project, and global tasks come from each user's own config.
"""#'#
@usage 'flag "-d --dir" help="Directory to create task stubs inside of" default=bin {
            arg <DIR>
        }'
@usage 'flag "-m --mise-bin" help="mise executable the stubs run; defaults to mise from PATH" default=mise {
            long_help #"""
mise executable the stubs run; defaults to mise from PATH

Use `--mise-bin ./bin/mise` with a script from `mise generate install-script`.
On Windows a path runs as written, so that script needs its `.cmd` launcher
beside it; generate it with
`mise generate install-script --write ./bin/mise --windows`. The default,
`mise`, is a bare name that resolves from PATH and needs nothing extra.
"""#
            arg <PATH>
        }'
@usage 'flag --windows-launcher help="What to write beside each stub for Windows to launch" default=cmd {
            long_help #"""
What to write beside each stub for Windows to launch

`cmd` writes `<task>.cmd`. cmd.exe re-parses the whole line before `%*` expands, so an
argument containing `& ^ | " %VAR%` does not reach the task intact when the launcher is
called from PowerShell.

`exe` writes a native `<task>.exe` instead, which receives its arguments unchanged from
every shell. It is a copy of the mise-shim.exe that ships with the Windows build, so it
can only be generated on Windows, and it adds ~220KB per task to a directory that is
normally committed.
"""#
            arg <KIND> {
                choices {
                    choice cmd
                    choice exe
                }
            }
        }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise generate task-stubs" help="Write a stub for each task into ./bin"'
@usage 'example "mise generate task-stubs --mise-bin ./bin/mise" help="Make the stubs run the mise that `mise generate install-script` wrote"'
@usage 'complete dir type=dir'
export def "mise generate task-stubs" [
    --cd (-C): path@"nus complete",        # Run as if mise were started in DIR
    --env_ (-E): list<string>,             # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                   # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                          # Suppress non-error messages
    --verbose (-v): int,                   # Show extra output (use -vv for even more)
    --yes (-y),                            # Answer yes to all confirmation prompts
    --raw,                                 # Connect tasks and install commands directly to the terminal
    --locked,                              # Require download URLs from the lockfile when installing
    --silent,                              # Suppress all task output and mise non-error messages
    --dir (-d): path@"nus complete",       # Directory to create task stubs inside of
    --mise-bin (-m): string,               # mise executable the stubs run; defaults to mise from PATH
    --windows-launcher: string@[cmd exe],  # What to write beside each stub for Windows to launch
]: nothing -> string {
    ^mise generate task-stubs ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --dir: $dir
        --mise-bin: $mise_bin
        --windows-launcher: $windows_launcher
    })
}

# Generate or update a tool stub
#
# A tool stub is an executable file that names a tool and where to get it;
# running it installs the tool if needed and runs it. See
# https://mise.jdx.dev/dev-tools/tool-stubs.html.
#
# Pass --url or --platform-url to create or extend a stub. mise downloads each
# artifact to record its checksum, size, and binary path unless you pass
# --skip-download. On an existing stub, new platforms are added and URLs you pass
# again are replaced. --fetch fills in missing checksums and sizes, and --lock
# records lock data for an existing stub, including one that uses a registry tool.
@usage 'long_help #"""
Generate or update a tool stub

A tool stub is an executable file that names a tool and where to get it;
running it installs the tool if needed and runs it. See
https://mise.jdx.dev/dev-tools/tool-stubs.html.

Pass --url or --platform-url to create or extend a stub. mise downloads each
artifact to record its checksum, size, and binary path unless you pass
--skip-download. On an existing stub, new platforms are added and URLs you pass
again are replaced. --fetch fills in missing checksums and sizes, and --lock
records lock data for an existing stub, including one that uses a registry tool.
"""#'
@usage 'flag "-b --bin" help="Binary path within the extracted archive" {
            long_help #"""
Binary path within the extracted archive

If not specified and the archive is downloaded, mise detects the most likely binary.
"""#
            arg <BIN>
        }'
@usage 'flag --bootstrap help="Make the stub install mise when it is missing" {
            long_help #"""
Make the stub install mise when it is missing

The stub becomes a bash script that:
1. Uses mise from PATH, or ~/.local/bin/mise
2. Otherwise installs mise to ~/.local/bin with the embedded installer
3. Runs the tool stub with mise
"""#
        }'
@usage 'flag --bootstrap-version help="mise version the --bootstrap script installs; defaults to the latest release" requires=--bootstrap {
            long_help #"""
mise version the --bootstrap script installs; defaults to the latest release

Pin a version such as `2026.10.0` to keep the installer reproducible.
"""#
            arg <BOOTSTRAP_VERSION>
        }'
@usage 'flag --checksum-algorithm help="Checksum algorithm for downloaded artifacts" default=blake3 {
            long_help #"""
Checksum algorithm for downloaded artifacts

Not available with --lock or --skip-download, which do not compute checksums.
"""#
            conflicts "--lock" "--skip-download"
            arg <ALGORITHM> {
                choices {
                    choice blake3
                    choice sha256
                }
            }
        }'
@usage 'flag --fetch help="Fetch checksums and sizes for an existing tool stub file" {
            long_help #"""
Fetch checksums and sizes for an existing tool stub file

Reads an existing stub file and fills in missing checksum and size fields by downloading the files. URLs must already be present in the stub.
"""#
            conflicts "--url" "--platform-url" "--version" "--bin" "--platform-bin" "--skip-download" "--lock"
        }'
@usage 'flag --http help="Has no effect; kept so existing scripts that pass it keep working" hide=#true default=http {
            arg <HTTP>
        }'
@usage 'flag --lock help="Resolve and record lock data (exact version, platform URLs and checksums) for an existing stub" {
            long_help #"""
Resolve and record lock data (exact version, platform URLs and checksums) for an existing stub

The data goes into the `mise.lock` of the nearest project config above the
stub, and the stub keeps its version request. It is an error when no project
config is found.
"""#
            conflicts "--url" "--platform-url" "--bin" "--platform-bin" "--fetch" "--skip-download"
        }'
@usage 'flag --platform-bin help="Binary path inside the archive for one platform, such as `linux-x64:bin/tool`; repeatable" var=#true {
            arg <PLATFORM_BIN>
        }'
@usage 'flag --platform-url help="Download URL for one platform, as `PLATFORM:URL` or a bare URL; repeatable" var=#true {
            long_help #"""
Download URL for one platform, as `PLATFORM:URL` or a bare URL; repeatable

With a bare URL, mise detects the platform from the file name, such as `--platform-url https://nodejs.org/dist/v24.11.0/node-v24.11.0-darwin-arm64.tar.gz`. When the output file already exists, new platforms are added to its platforms table, and a platform you pass again gets the new URL.
"""#
            arg <PLATFORM_URL>
        }'
@usage 'flag --skip-download help="Do not download artifacts, so checksums, sizes, and the detected binary path are left out"'
@usage 'flag "-u --url" help="URL to download the tool from" {
            arg <URL>
        }'
@usage 'flag --version help="Version of the tool" default=latest {
            arg <VERSION>
        }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <OUTPUT> help="Output file path for the tool stub"'
@usage 'example "mise generate tool-stub ./bin/node --platform-url https://nodejs.org/dist/v24.11.0/node-v24.11.0-darwin-arm64.tar.gz" help="Download and inspect a real archive to detect its binary and checksum"'
@usage 'example "mise generate tool-stub ./bin/node --platform-url linux-x64:https://nodejs.org/dist/v24.11.0/node-v24.11.0-linux-x64.tar.gz" help="Add a Linux artifact to the same stub"'
@usage 'example "mise generate tool-stub ./bin/my-tool --url https://example.com/my-tool.tar.gz --skip-download" help="Draft a stub without downloading; replace the placeholder URL before running it"'
@usage 'example "mise generate tool-stub ./bin/node --fetch" help="Fill missing checksums and sizes in an existing stub"'
@usage 'example "mise generate tool-stub ./bin/registry-node --lock --version 24" help="Resolve and record the version and platform lock data of an existing registry-backed stub"'
@usage 'complete output type=path'
export def "mise generate tool-stub" [
    output: path@"nus complete",                       # Output file path for the tool stub
    --cd (-C): path@"nus complete",                    # Run as if mise were started in DIR
    --env_ (-E): list<string>,                         # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                               # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                                      # Suppress non-error messages
    --verbose (-v): int,                               # Show extra output (use -vv for even more)
    --version: string,                                 # Version of the tool
    --yes (-y),                                        # Answer yes to all confirmation prompts
    --raw,                                             # Connect tasks and install commands directly to the terminal
    --locked,                                          # Require download URLs from the lockfile when installing
    --silent,                                          # Suppress all task output and mise non-error messages
    --bin (-b): string,                                # Binary path within the extracted archive
    --bootstrap,                                       # Make the stub install mise when it is missing
    --bootstrap-version: string,                       # mise version the --bootstrap script installs; defaults to the latest release
    --checksum-algorithm: string@["blake3" "sha256"],  # Checksum algorithm for downloaded artifacts
    --fetch,                                           # Fetch checksums and sizes for an existing tool stub file
    --lock,                                            # Resolve and record lock data (exact version, platform URLs and checksums) for an existing stub
    --platform-bin: list<string>,                      # Binary path inside the archive for one platform, such as `linux-x64:bin/tool`; repeatable
    --platform-url: list<string>,                      # Download URL for one platform, as `PLATFORM:URL` or a bare URL; repeatable
    --skip-download,                                   # Do not download artifacts, so checksums, sizes, and the detected binary path are left out
    --url (-u): string,                                # URL to download the tool from
]: nothing -> string {
    ^mise generate tool-stub ...(nus argv [$output] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --version: $version
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --bin: $bin
        --bootstrap: $bootstrap
        --bootstrap-version: $bootstrap_version
        --checksum-algorithm: $checksum_algorithm
        --fetch: $fetch
        --lock: $lock
        --platform-bin: $platform_bin
        --platform-url: $platform_url
        --skip-download: $skip_download
        --url: $url
    })
}

# Remove the mise CLI and all related data
#
# Deletes the mise executable and the data (including installed tools), state,
# and cache directories. It also deletes the system-wide shared directory used by
# `mise install --system` (MISE_SYSTEM_DATA_DIR, default /usr/local/share/mise),
# which other users on the machine may rely on. It asks before each removal;
# --yes skips the prompts. The config directory stays unless you pass --config.
#
# If a package manager such as Homebrew or apt installed mise, uninstall it with
# that package manager instead. Remove the `mise activate` line from your shell
# startup file yourself. See
# https://mise.jdx.dev/installing-mise.html#uninstalling.
@usage 'long_help #"""
Remove the mise CLI and all related data

Deletes the mise executable and the data (including installed tools), state,
and cache directories. It also deletes the system-wide shared directory used by
`mise install --system` (MISE_SYSTEM_DATA_DIR, default /usr/local/share/mise),
which other users on the machine may rely on. It asks before each removal;
--yes skips the prompts. The config directory stays unless you pass --config.

If a package manager such as Homebrew or apt installed mise, uninstall it with
that package manager instead. Remove the `mise activate` line from your shell
startup file yourself. See
https://mise.jdx.dev/installing-mise.html#uninstalling.
"""#'
@usage 'flag "-n --dry-run" help="Print what would be removed, without removing anything"'
@usage 'flag --config help="Also remove the config directory"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise implode --dry-run" help="List what would be removed"'
export def "mise implode" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                  # Print what would be removed, without removing anything
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --config,                        # Also remove the config directory
]: nothing -> string {
    ^mise implode ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --config: $config
    })
}

# Edit mise.toml interactively
#
# Opens a terminal editor for PATH (default: mise.toml in the current directory)
# where you can add tools from the registry, pick versions, and set environment
# variables, tasks, and settings. It pre-fills tools it detects from files in the
# current directory, such as `.node-version`.
#
# Without an interactive terminal, or with --yes, it writes a commented starter
# template instead. If PATH already exists it stops with an error rather than
# replace the file; pass --force to replace it. Use --dry-run to print the result
# without writing it.
@usage 'long_help #"""
Edit mise.toml interactively

Opens a terminal editor for PATH (default: mise.toml in the current directory)
where you can add tools from the registry, pick versions, and set environment
variables, tasks, and settings. It pre-fills tools it detects from files in the
current directory, such as `.node-version`.

Without an interactive terminal, or with --yes, it writes a commented starter
template instead. If PATH already exists it stops with an error rather than
replace the file; pass --force to replace it. Use --dry-run to print the result
without writing it.
"""#'
@usage 'flag "-g --global" help="Edit the global config file (~/.config/mise/config.toml)" conflicts=PATH'
@usage 'flag "-n --dry-run" help="Print the result instead of writing it to the file"'
@usage 'flag "-f --force" help="Replace an existing file with the starter template when not opening the editor"'
@usage 'flag "-t --tool-versions" help="Copy the tools from this .tool-versions file into the config, without opening the editor" {
        arg <FILE>
    }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[PATH]" help="Config file to edit or create; defaults to mise.toml" required=#false'
@usage 'example "mise edit" help="Edit mise.toml in the current directory"'
@usage 'example "mise edit mise.local.toml" help="Edit another config file"'
@usage 'example "mise edit -g" help="Edit the global config"'
@usage 'example "mise edit -t .tool-versions" help="Copy the tools from .tool-versions into mise.toml"'
@usage 'example "mise edit -n" help="Print the result instead of writing it"'
@usage 'example "mise edit -y new.toml" help="Write a commented starter config to a new file without opening the editor"'
@usage 'example "mise edit -y --force" help="Replace an existing mise.toml with the starter config"'
@usage 'complete path type=path'
@usage 'complete file type=path'
export def "mise edit" [
    path?: path@"nus complete",                 # Config file to edit or create; defaults to mise.toml
    --cd (-C): path@"nus complete",             # Run as if mise were started in DIR
    --env_ (-E): list<string>,                  # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --force (-f),                               # Replace an existing file with the starter template when not opening the editor
    --jobs (-j): string,                        # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                             # Print the result instead of writing it to the file
    --quiet (-q),                               # Suppress non-error messages
    --verbose (-v): int,                        # Show extra output (use -vv for even more)
    --yes (-y),                                 # Answer yes to all confirmation prompts
    --raw,                                      # Connect tasks and install commands directly to the terminal
    --locked,                                   # Require download URLs from the lockfile when installing
    --silent,                                   # Suppress all task output and mise non-error messages
    --global (-g),                              # Edit the global config file (~/.config/mise/config.toml)
    --tool-versions (-t): path@"nus complete",  # Copy the tools from this .tool-versions file into the config, without opening the editor
]: nothing -> string {
    ^mise edit ...(nus argv [$path] {
        --cd: $cd
        --env: $env_
        --force: $force
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --global: $global
        --tool-versions: $tool_versions
    })
}

# Install the tools in your config, or specific tool versions
#
# With no arguments, installs every tool version your config requests that is not
# installed yet. With TOOL@VERSION arguments, installs those versions; a bare tool
# name installs the version your config requests for it.
#
# Installing does not add a tool to your config, so a tool you have not configured
# is not on PATH. Use `mise use` to install a tool and add it to mise.toml, or
# `mise exec <TOOL>@<VERSION> -- <COMMAND>` to run it once.
#
# Versions install in parallel (see --jobs) under the mise data directory, by
# default `~/.local/share/mise/installs/<TOOL>/<VERSION>`.
@usage 'alias i'
@usage 'long_help #"""
Install the tools in your config, or specific tool versions

With no arguments, installs every tool version your config requests that is not
installed yet. With TOOL@VERSION arguments, installs those versions; a bare tool
name installs the version your config requests for it.

Installing does not add a tool to your config, so a tool you have not configured
is not on PATH. Use `mise use` to install a tool and add it to mise.toml, or
`mise exec <TOOL>@<VERSION> -- <COMMAND>` to run it once.

Versions install in parallel (see --jobs) under the mise data directory, by
default `~/.local/share/mise/installs/<TOOL>/<VERSION>`.
"""#'
@usage 'flag "-f --force" help="Reinstall even if already installed" {
        long_help #"""
Reinstall even if already installed

With no TOOL arguments, reinstalls every configured tool.
"""#
    }'
@usage 'flag "-j --jobs" help="How many tools to install in parallel; defaults to the `jobs` setting" env=MISE_JOBS {
        long_help #"""
How many tools to install in parallel; defaults to the `jobs` setting

Values below 1 are treated as 1.
"""#
        arg <JOBS>
    }'
@usage 'flag "-n --dry-run" help="Show what would be installed, without installing anything"'
@usage r#'flag "-v --verbose" help="Show installer output" var=#true count=#true {
        long_help #"""
Show installer output

Prints each backend's download, configure, and compile output.
"""#
    }'#
@usage 'flag --dry-run-code help="Like --dry-run, but exit with status 1 when anything needs installing" {
        long_help #"""
Like --dry-run, but exit with status 1 when anything needs installing

Use it in scripts to check whether `mise install` has work to do.
"""#
    }'
@usage 'flag --include-task-tools help="Also install tools required by tasks in the current scope" {
        long_help #"""
Also install tools required by tasks in the current scope

This prepares task tools without running task commands or dependencies.
Combine with --monorepo to include tasks from every configured root.
"""#
    }'
@usage 'flag --include-lazy help="Also install tools configured with `lazy = true`" {
        long_help #"""
Also install tools configured with `lazy = true`

By default, a bare `mise install` leaves lazy tools to be installed the first
time you run one of their commands.
"""#
    }'
@usage 'flag --minimum-release-age help="Only install versions released before a date or at least a duration ago" {
        alias "--before" hide=#true
        long_help #"""
Only install versions released before a date or at least a duration ago

Takes a date such as `2024-06-01` or a duration such as `90d` or `1y`.
Overrides the `minimum_release_age` setting and tool option.
"""#
        arg <AGE>
    }'
@usage r#'flag --monorepo help="Also install tools from every config root in `[monorepo].config_roots`" env=MISE_MONOREPO {
        long_help #"""
Also install tools from every config root in `[monorepo].config_roots`

Requires `monorepo_root = true` and an explicit `config_roots` list in the
monorepo root's config. Uses the active MISE_ENV.
"""#
    }'#
@usage 'flag --raw help="Connect install commands directly to the terminal; implies --jobs=1" overrides=--jobs'
@usage 'flag --shared help="Install into DIR instead of the mise data directory" conflicts=--system {
        long_help #"""
Install into DIR instead of the mise data directory

May require elevated permissions, depending on the path.
"""#
        arg <DIR>
    }'
@usage 'flag --system help="Install into the system-wide shared directory" conflicts=--shared {
        long_help #"""
Install into the system-wide shared directory

Installs to /usr/local/share/mise/installs (or MISE_SYSTEM_DATA_DIR/installs).
On Unix, binary-download backends invoke sudo to publish into protected
system directories unless system_packages.sudo is disabled. Run mise as
your user, without sudo.
"""#
    }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[TOOL@VERSION]…" help="Tools to install, such as `node@24`; defaults to every tool in the config" required=#false var=#true'
@usage 'example "mise install" help="Install every tool the config requests"'
@usage 'example "mise install node" help="Install the node version the config requests"'
@usage 'example "mise install node@24" help="Install the latest node 24.x release"'
@usage 'example "mise install node@24.11.0" help="Install an exact version"'
@usage 'example "mise install --include-lazy" help="Also install tools marked lazy = true"'
@usage 'example "mise install --include-task-tools" help="Also install the tools your tasks need"'
@usage 'complete dir type=dir'
export def "mise install" [
    ...tool_version: string@"nus complete",  # Tools to install, such as `node@24`; defaults to every tool in the config
    --cd (-C): path@"nus complete",          # Run as if mise were started in DIR
    --env_ (-E): list<string>,               # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --force (-f),                            # Reinstall even if already installed
    --jobs (-j): string,                     # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                          # Show what would be installed, without installing anything
    --quiet (-q),                            # Suppress non-error messages
    --verbose (-v): int,                     # Show extra output (use -vv for even more)
    --yes (-y),                              # Answer yes to all confirmation prompts
    --raw,                                   # Connect tasks and install commands directly to the terminal
    --locked,                                # Require download URLs from the lockfile when installing
    --silent,                                # Suppress all task output and mise non-error messages
    --dry-run-code,                          # Like --dry-run, but exit with status 1 when anything needs installing
    --include-task-tools,                    # Also install tools required by tasks in the current scope
    --include-lazy,                          # Also install tools configured with `lazy = true`
    --minimum-release-age: string,           # Only install versions released before a date or at least a duration ago
    --monorepo,                              # Also install tools from every config root in `[monorepo].config_roots`
    --shared: path@"nus complete",           # Install into DIR instead of the mise data directory
    --system,                                # Install into the system-wide shared directory
]: nothing -> string {
    ^mise install ...(nus argv [...$tool_version] {
        --cd: $cd
        --env: $env_
        --force: $force
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --dry-run-code: $dry_run_code
        --include-task-tools: $include_task_tools
        --include-lazy: $include_lazy
        --minimum-release-age: $minimum_release_age
        --monorepo: $monorepo
        --shared: $shared
        --system: $system
    })
}

# Install a tool version into a directory outside mise
#
# Downloads or builds TOOL@VERSION into PATH for use without mise. mise does not
# track the result, so it does not appear in `mise ls`.
#
# If PATH is not empty, mise asks before deleting its contents; --yes deletes
# them without asking.
@usage 'long_help #"""
Install a tool version into a directory outside mise

Downloads or builds TOOL@VERSION into PATH for use without mise. mise does not
track the result, so it does not appear in `mise ls`.

If PATH is not empty, mise asks before deleting its contents; --yes deletes
them without asking.
"""#'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <TOOL@VERSION> help="Tool and version to install, such as `node@24`"'
@usage 'arg <PATH> help="Directory to install into; its existing contents are deleted"'
@usage 'example #"""
mise install-into node@24 ./mynode && ./mynode/bin/node -v
v24.11.0
"""# help="Install node 24 into ./mynode and run it"'
@usage 'complete path type=dir'
export def "mise install-into" [
    tool_version: string@"nus complete",  # Tool and version to install, such as `node@24`
    path: path@"nus complete",            # Directory to install into; its existing contents are deleted
    --cd (-C): path@"nus complete",       # Run as if mise were started in DIR
    --env_ (-E): list<string>,            # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                  # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                         # Suppress non-error messages
    --verbose (-v): int,                  # Show extra output (use -vv for even more)
    --yes (-y),                           # Answer yes to all confirmation prompts
    --raw,                                # Connect tasks and install commands directly to the terminal
    --locked,                             # Require download URLs from the lockfile when installing
    --silent,                             # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise install-into ...(nus argv [$tool_version $path] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# [experimental] Inspect and choose identity-layout installations
#
# With `install_layout = "identity"`, each installation lives in its own
# `<label>-<hash>` directory, and several installations of one version can
# exist side by side (different options, platforms, pinned artifacts, or a
# refreshed copy). These commands list them, choose which one mise uses when
# no lockfile pins one, and move installations made before you turned the
# layout on into it. With no subcommand, runs `mise installs ls`. See
# https://mise.jdx.dev/dev-tools/install-layout.html.
@usage 'long_help #"""
[experimental] Inspect and choose identity-layout installations

With `install_layout = "identity"`, each installation lives in its own
`<label>-<hash>` directory, and several installations of one version can
exist side by side (different options, platforms, pinned artifacts, or a
refreshed copy). These commands list them, choose which one mise uses when
no lockfile pins one, and move installations made before you turned the
layout on into it. With no subcommand, runs `mise installs ls`. See
https://mise.jdx.dev/dev-tools/install-layout.html.
"""#'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise installs" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise installs ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# List the installations of the identity install layout
#
# Every installation is listed separately, so variants of one version (made
# with different options, or pinned to different artifacts by lockfiles) can
# be told apart. The Status column marks the installation mise uses when no
# lockfile pins one (`selected`), installations a lockfile pins (`pinned`), and
# installations in a read-only shared installs directory (`shared`).
@usage 'alias list'
@usage 'long_help #"""
List the installations of the identity install layout

Every installation is listed separately, so variants of one version (made
with different options, or pinned to different artifacts by lockfiles) can
be told apart. The Status column marks the installation mise uses when no
lockfile pins one (`selected`), installations a lockfile pins (`pinned`), and
installations in a read-only shared installs directory (`shared`).
"""#'
@usage 'flag "-J --json" help="Output in JSON format"'
@usage 'flag --no-header help="Do not print the table header"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[TOOL]…" help="Only show the installations of these tools" required=#false var=#true'
@usage 'example "mise installs ls" help="List every installation in the identity layout"'
@usage 'example "mise installs ls node --json" help="List the installations of node as JSON"'
@usage 'output "json" framing="json" select="--json" {
    schema "{\n  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",\n  \"title\": \"mise installs ls --json\",\n  \"type\": \"array\",\n  \"items\": {\n    \"type\": \"object\",\n    \"properties\": {\n      \"name\": {\n        \"type\": \"string\"\n      },\n      \"dir\": {\n        \"type\": \"string\"\n      },\n      \"backend\": {\n        \"type\": \"string\"\n      },\n      \"version\": {\n        \"type\": \"string\"\n      },\n      \"platform\": {\n        \"type\": \"string\"\n      },\n      \"mode\": {\n        \"enum\": [\n          \"fallback\",\n          \"resolved\"\n        ]\n      },\n      \"options\": {\n        \"type\": \"object\",\n        \"additionalProperties\": {\n          \"type\": \"string\"\n        }\n      },\n      \"requested_as\": {\n        \"type\": [\n          \"string\",\n          \"null\"\n        ]\n      },\n      \"checksum\": {\n        \"type\": [\n          \"string\",\n          \"null\"\n        ]\n      },\n      \"pinned\": {\n        \"type\": \"boolean\"\n      },\n      \"selected\": {\n        \"type\": \"boolean\"\n      },\n      \"shared\": {\n        \"type\": \"boolean\"\n      }\n    },\n    \"required\": [\n      \"name\",\n      \"dir\",\n      \"backend\",\n      \"version\",\n      \"platform\",\n      \"mode\",\n      \"options\",\n      \"requested_as\",\n      \"checksum\",\n      \"pinned\",\n      \"selected\",\n      \"shared\"\n    ],\n    \"additionalProperties\": false\n  }\n}\n"
}'
export def "mise installs ls" [
    ...tool: string@"nus complete",  # Only show the installations of these tools
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --no-header,                     # Do not print the table header
]: nothing -> table<name: string, dir: string, backend: string, version: string, platform: string, mode: string, options: record, requested_as: oneof<string, nothing>, checksum: oneof<string, nothing>, pinned: bool, selected: bool, shared: bool> {
    let text = ^mise installs ls --json ...(nus argv [...$tool] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --no-header: $no_header
    })
    nus decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"title\":\"mise installs ls --json\",\"type\":\"array\",\"items\":{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"},\"dir\":{\"type\":\"string\"},\"backend\":{\"type\":\"string\"},\"version\":{\"type\":\"string\"},\"platform\":{\"type\":\"string\"},\"mode\":{\"enum\":[\"fallback\",\"resolved\"]},\"options\":{\"type\":\"object\",\"additionalProperties\":{\"type\":\"string\"}},\"requested_as\":{\"type\":[\"string\",\"null\"]},\"checksum\":{\"type\":[\"string\",\"null\"]},\"pinned\":{\"type\":\"boolean\"},\"selected\":{\"type\":\"boolean\"},\"shared\":{\"type\":\"boolean\"}},\"required\":[\"name\",\"dir\",\"backend\",\"version\",\"platform\",\"mode\",\"options\",\"requested_as\",\"checksum\",\"pinned\",\"selected\",\"shared\"],\"additionalProperties\":false}}" { from json }
}

# Reinstall legacy installations into the identity install layout
#
# Installations made before `install_layout = "identity"` was turned on stay in
# `installs/<tool>/<version>` and keep working; mise never moves them on its own,
# because tools record their own path in shebangs, virtual environments and
# package-manager files. This reinstalls each one into its own `<label>-<hash>`
# directory, then removes the old directory and puts the version link in its
# place, so a path that pointed into the old directory still resolves.
#
# Each version is reinstalled from its backend, not copied, so the files are
# written for their new path. Run it while nothing is using the tools: the old
# directory is moved aside while its replacement installs, and put back if that
# fails. Versions whose recorded backend is not the one their tool resolves to
# now are left alone, as are tools that keep the legacy layout (`http:`,
# `rust`, `dotnet`).
#
# A version that cannot be reinstalled (its release was withdrawn or is signed
# by someone else now, or the network is unavailable) is not an error: its
# directory is moved as it is into the identity layout, behind the same version
# link. Only a version that cannot be moved either keeps its old directory,
# reported as kept in the legacy layout. The command ends with a count of what
# was migrated, relocated, kept and failed, and fails only when a migration
# itself broke.
@usage 'long_help #"""
Reinstall legacy installations into the identity install layout

Installations made before `install_layout = "identity"` was turned on stay in
`installs/<tool>/<version>` and keep working; mise never moves them on its own,
because tools record their own path in shebangs, virtual environments and
package-manager files. This reinstalls each one into its own `<label>-<hash>`
directory, then removes the old directory and puts the version link in its
place, so a path that pointed into the old directory still resolves.

Each version is reinstalled from its backend, not copied, so the files are
written for their new path. Run it while nothing is using the tools: the old
directory is moved aside while its replacement installs, and put back if that
fails. Versions whose recorded backend is not the one their tool resolves to
now are left alone, as are tools that keep the legacy layout (`http:`,
`rust`, `dotnet`).

A version that cannot be reinstalled (its release was withdrawn or is signed
by someone else now, or the network is unavailable) is not an error: its
directory is moved as it is into the identity layout, behind the same version
link. Only a version that cannot be moved either keeps its old directory,
reported as kept in the legacy layout. The command ends with a count of what
was migrated, relocated, kept and failed, and fails only when a migration
itself broke.
"""#'
@usage 'flag "-n --dry-run" help="Show what would move without changing anything"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[TOOL@VERSION]…" help="Only migrate these tools, or these versions of them" help_long=#"""
Only migrate these tools, or these versions of them

Defaults to every legacy installation.
"""# required=#false var=#true'
@usage 'example "mise installs migrate --dry-run" help="List the legacy installations that would move"'
@usage 'example "mise installs migrate node python@3.12.1" help="Move every installed node and one python version"'
export def "mise installs migrate" [
    ...tool_version: string@"nus complete",  # Only migrate these tools, or these versions of them
    --cd (-C): path@"nus complete",          # Run as if mise were started in DIR
    --env_ (-E): list<string>,               # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                     # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                          # Show what would move without changing anything
    --quiet (-q),                            # Suppress non-error messages
    --verbose (-v): int,                     # Show extra output (use -vv for even more)
    --yes (-y),                              # Answer yes to all confirmation prompts
    --raw,                                   # Connect tasks and install commands directly to the terminal
    --locked,                                # Require download URLs from the lockfile when installing
    --silent,                                # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise installs migrate ...(nus argv [...$tool_version] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Choose which installation mise uses when no lockfile pins one
#
# Several installations can match the same request, such as a refreshed copy next
# to one a lockfile pinned, or installations made for different lockfiles. For a
# request with no lockfile entry, mise uses the installation selected for that
# tool, version, platform, and options. If none is selected and several match,
# mise stops and tells you to run this command.
#
# The selection is shared by every project on this machine that makes the same
# request without a lockfile. Projects whose lockfile pins an artifact keep the
# installation of that artifact. The version link (`installs/<tool>/<version>`)
# is pointed at the selected installation.
@usage 'long_help #"""
Choose which installation mise uses when no lockfile pins one

Several installations can match the same request, such as a refreshed copy next
to one a lockfile pinned, or installations made for different lockfiles. For a
request with no lockfile entry, mise uses the installation selected for that
tool, version, platform, and options. If none is selected and several match,
mise stops and tells you to run this command.

The selection is shared by every project on this machine that makes the same
request without a lockfile. Projects whose lockfile pins an artifact keep the
installation of that artifact. The version link (`installs/<tool>/<version>`)
is pointed at the selected installation.
"""#'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <INSTALLATION> help="The installation to select: its directory name, or its path"'
@usage r#'example "mise installs ls jq" help="Find jq's installations"'#
@usage 'example "mise installs select jq-hm3qa4vb" help="Use this one for requests with no lockfile entry"'
export def "mise installs select" [
    installation: string,            # The installation to select: its directory name, or its path
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise installs select ...(nus argv [$installation] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Print the latest version that matches a version request
#
# `mise latest node` prints the latest release, and `mise latest node@22` the
# latest 22.x release. Each backend decides what "latest" means, for example
# whether prereleases count and how channels and refs resolve. Nothing is
# installed and no config changes.
@usage 'long_help #"""
Print the latest version that matches a version request

`mise latest node` prints the latest release, and `mise latest node@22` the
latest 22.x release. Each backend decides what "latest" means, for example
whether prereleases count and how channels and refs resolve. Nothing is
installed and no config changes.
"""#'
@usage 'flag "-i --installed" help="Print the latest installed version instead of the latest available one"'
@usage 'flag --minimum-release-age help="Only consider versions released before a date or at least a duration ago" conflicts=--installed {
        alias "--before" hide=#true
        long_help #"""
Only consider versions released before a date or at least a duration ago

Takes a date such as `2024-06-01` or a duration such as `90d` or `1y`.
Overrides the `minimum_release_age` setting and tool option.
"""#
        arg <AGE>
    }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <TOOL@VERSION> help="Tool, optionally with a version prefix, such as `node` or `node@22`"'
@usage 'arg "[ASDF_VERSION]" help="The version prefix to use when querying the latest version same as the first argument after the \"@\" used for asdf compatibility" required=#false hide=#true'
@usage 'example "mise latest node" help="Print the latest node release"'
@usage 'example "mise latest node@22" help="Print the latest node 22.x release"'
@usage 'example "mise latest node@22 --installed" help="Print the latest installed node 22.x version"'
@usage 'example "mise latest node --minimum-release-age 30d" help="Skip releases from the last 30 days"'
export def "mise latest" [
    tool_version: string@"nus complete",  # Tool, optionally with a version prefix, such as `node` or `node@22`
    asdf_version?: string,                # The version prefix to use when querying the latest version same as the first argument after the "@" used for asdf compatibility
    --cd (-C): path@"nus complete",       # Run as if mise were started in DIR
    --env_ (-E): list<string>,            # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                  # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                         # Suppress non-error messages
    --verbose (-v): int,                  # Show extra output (use -vv for even more)
    --yes (-y),                           # Answer yes to all confirmation prompts
    --raw,                                # Connect tasks and install commands directly to the terminal
    --locked,                             # Require download URLs from the lockfile when installing
    --silent,                             # Suppress all task output and mise non-error messages
    --installed (-i),                     # Print the latest installed version instead of the latest available one
    --minimum-release-age: string,        # Only consider versions released before a date or at least a duration ago
]: nothing -> string {
    ^mise latest ...(nus argv [$tool_version $asdf_version] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --installed: $installed
        --minimum-release-age: $minimum_release_age
    })
}

# Symlink a tool version into mise
#
# Use this to register an install that was compiled by hand or built with another
# tool. mise uses the version exactly as written, such as `node@24.11.0` or a name
# of your own like `node@brew`; `latest`, aliases, and channels are rejected.
@usage 'alias ln'
@usage 'long_help #"""
Symlink a tool version into mise

Use this to register an install that was compiled by hand or built with another
tool. mise uses the version exactly as written, such as `node@24.11.0` or a name
of your own like `node@brew`; `latest`, aliases, and channels are rejected.
"""#'
@usage 'flag "-f --force" help="Replace an existing installation of this version"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <TOOL@VERSION> help="Tool and version to create a symlink for"'
@usage 'arg <PATH> help="Directory of the existing installation, such as `~/.nvm/versions/node/v24.11.0`"'
@usage 'example "mise link node@24.11.0 ~/.nodes/24.11.0" help="Link a node that node-build built into ~/.nodes/24.11.0"'
@usage r#'example "mise link node@brew \"$(brew --prefix node)\"" help="Register Homebrew's node as node@brew; then run `mise use node@brew`"'#
@usage 'complete path type=dir'
export def "mise link" [
    tool_version: string@"nus complete",  # Tool and version to create a symlink for
    path: path@"nus complete",            # Directory of the existing installation, such as `~/.nvm/versions/node/v24.11.0`
    --cd (-C): path@"nus complete",       # Run as if mise were started in DIR
    --env_ (-E): list<string>,            # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --force (-f),                         # Replace an existing installation of this version
    --jobs (-j): string,                  # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                         # Suppress non-error messages
    --verbose (-v): int,                  # Show extra output (use -vv for even more)
    --yes (-y),                           # Answer yes to all confirmation prompts
    --raw,                                # Connect tasks and install commands directly to the terminal
    --locked,                             # Require download URLs from the lockfile when installing
    --silent,                             # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise link ...(nus argv [$tool_version $path] {
        --cd: $cd
        --env: $env_
        --force: $force
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Create or refresh lockfile versions, checksums, and download URLs
#
# Operates on the current config root, including tools declared by tasks.
# Existing matching locked versions are preserved unless `--bump` re-resolves
# their requests. This command does not install tools; `--dry-run` previews
# changes.
#
# `mise lock TOOL@VERSION` locks that exact version. When the version falls
# outside the configured request, such as `tiny@3.0.1` with `tiny = "2"`, mise
# also updates the request in mise.toml to match.
@usage 'long_help #"""
Create or refresh lockfile versions, checksums, and download URLs

Operates on the current config root, including tools declared by tasks.
Existing matching locked versions are preserved unless `--bump` re-resolves
their requests. This command does not install tools; `--dry-run` previews
changes.

`mise lock TOOL@VERSION` locks that exact version. When the version falls
outside the configured request, such as `tiny@3.0.1` with `tiny = "2"`, mise
also updates the request in mise.toml to match.
"""#'
@usage r#'flag "-g --global" help="Lock only the global and system config lockfiles" {
        long_help #"""
Lock only the global and system config lockfiles

These are ~/.config/mise/mise.lock and the system config's lockfile. By
default, only the current project's config root is locked.
"""#
    }'#
@usage 'flag "-j --jobs" help="How many jobs to run in parallel; defaults to the `jobs` setting" env=MISE_JOBS {
        long_help #"""
How many jobs to run in parallel; defaults to the `jobs` setting

Values below 1 are treated as 1.
"""#
        arg <JOBS>
    }'
@usage 'flag "-n --dry-run" help="Show what would change, without writing anything"'
@usage 'flag "-p --platform" help="Platforms to lock, comma-separated, such as `linux-x64,macos-arm64`" var=#true {
        long_help #"""
Platforms to lock, comma-separated, such as `linux-x64,macos-arm64`

Defaults to the `lockfile_platforms` setting plus the current platform when
that setting is configured, else the platforms already in the lockfile, else
a common set for a new lockfile.
"""#
        arg <PLATFORM> delimiter=,
    }'
@usage 'flag --bump help="Re-resolve version requests against the latest available versions" {
        long_help #"""
Re-resolve version requests against the latest available versions

By default, `mise lock` refreshes metadata for the currently locked versions.
With this flag, requests such as "latest", "lts", or prefixes such as "24" are
re-resolved against the latest matching remote versions, so the lockfile
advances without installing anything. `--bump` never modifies config files:
exact versions resolve to themselves and stay unchanged (use
`mise upgrade --bump` to rewrite pins in mise.toml). If the remote versions
cannot be fetched, it fails rather than keep the locked version.
"""#
    }'
@usage 'flag --json help="Output version changes as JSON" {
        long_help #"""
Output version changes as JSON

Prints an array of objects describing lockfile version changes:
name, backend, lockfile, old_versions, new_versions.
Version lists keep config/lockfile order; they are not sorted.
Only version-level changes are reported: checksum and URL refreshes for
unchanged versions produce no entries, so `mise lock --json` prints `[]`
when no version changed, even though it still updates the lockfile.
Suppresses the human-readable output. Combine with `--dry-run` to
detect available updates without writing the lockfile.
"""#
    }'
@usage 'flag --local help="Update mise.local.lock, for tools in mise.local.toml, instead of mise.lock"'
@usage 'flag --minimum-release-age help="Only lock versions released before a date or at least a duration ago" {
        alias "--before" hide=#true
        long_help #"""
Only lock versions released before a date or at least a duration ago

Takes a date such as `2024-06-01` or a duration such as `90d` or `1y`.
Overrides the `minimum_release_age` setting and tool option. It filters only
requests that are not exact, such as "24" or "latest"; exact versions such
as "24.11.0" are not filtered. Existing matching lockfile entries are kept;
this flag alone does not downgrade them.
"""#
        arg <AGE>
    }'
@usage 'flag --upgrade help="Upgrade lockfiles to the latest format" {
        long_help #"""
Upgrade lockfiles to the latest format

mise keeps an existing lockfile at its format version during normal updates,
so collaborators on an older mise can still read it. This flag rewrites it in
the newest format, which adds request bindings, dependency-graph sidecars,
and packslip repository IDs. It processes every configured tool and cannot be
combined with tool arguments. See
https://mise.jdx.dev/dev-tools/mise-lock-reference.html#format-versions.
"""#
    }'
@usage r#'flag --sidecars help="List native dependency sidecars instead of updating lockfiles" {
        long_help #"""
List native dependency sidecars instead of updating lockfiles

Backends such as npm and pypi keep a tool's locked dependency graph in a
sidecar directory next to mise.lock; see
https://mise.jdx.dev/dev-tools/mise-lock-reference.html#native-dependency-sidecars.
For each existing lockfile in scope, prints the sidecar directory mise keeps
its dependency graphs in and every sidecar directory the lockfile references.
Nothing is resolved, installed, or written.
Paths are relative to the current directory when they are inside it,
and absolute otherwise, such as the sidecars of a symlinked lockfile.
Combine with `--json` for machine-readable output, or with `--local`
and `--global` to choose the lockfiles.
"""#
    }'#
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[TOOL]…" help="Tools to lock, such as `node python`; defaults to every configured tool and every tool a task needs" help_long=#"""
Tools to lock, such as `node python`; defaults to every configured tool and every tool a task needs

Use `tool@version` to lock an exact version. If it falls outside the configured
request, mise.toml is updated to match.
"""# required=#false var=#true'
@usage 'example "mise lock" help="Create or refresh the project lockfile"'
@usage 'example "mise lock node python" help="Refresh only node and python"'
@usage 'example "mise lock node@24.11.0" help="Lock an exact version; mise.toml keeps a request such as \"24\""'
@usage 'example "mise lock --platform linux-x64" help="Lock only the linux-x64 platform"'
@usage 'example "mise lock --dry-run" help="Show what would change"'
@usage 'example "mise lock --bump" help="Re-resolve requests such as \"latest\" or \"24\" to the latest matching versions"'
@usage 'example "mise lock --bump --dry-run --json" help="List available updates as JSON without writing"'
@usage 'example "mise lock --minimum-release-age 2024-01-01" help="Lock versions released before 2024-01-01 for requests that are not exact"'
@usage 'example "mise lock --local" help="Update mise.local.lock"'
@usage 'example "mise lock --global" help="Update only the global lockfiles"'
@usage 'output json framing=json select=--json'
export def "mise lock" [
    ...tool: string@"nus complete",  # Tools to lock, such as `node python`; defaults to every configured tool and every tool a task needs
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                  # Show what would change, without writing anything
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --global (-g),                   # Lock only the global and system config lockfiles
    --platform (-p): list<string>,   # Platforms to lock, comma-separated, such as `linux-x64,macos-arm64`
    --bump,                          # Re-resolve version requests against the latest available versions
    --local,                         # Update mise.local.lock, for tools in mise.local.toml, instead of mise.lock
    --minimum-release-age: string,   # Only lock versions released before a date or at least a duration ago
    --upgrade,                       # Upgrade lockfiles to the latest format
    --sidecars,                      # List native dependency sidecars instead of updating lockfiles
] {
    ^mise lock --json ...(nus argv [...$tool] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --global: $global
        --platform: $platform
        --bump: $bump
        --local: $local
        --minimum-release-age: $minimum_release_age
        --upgrade: $upgrade
        --sidecars: $sidecars
    }) | from json
}

# List installed and active tool versions
#
# Lists the tools mise knows about: versions that are installed, and versions
# requested by a config file (active) whether or not they are installed. Each row
# shows the tool, the version (marked `(missing)` when it is not installed), the
# config file that requests it, and the request as written.
@usage 'alias list'
@usage 'long_help #"""
List installed and active tool versions

Lists the tools mise knows about: versions that are installed, and versions
requested by a config file (active) whether or not they are installed. Each row
shows the tool, the version (marked `(missing)` when it is not installed), the
config file that requests it, and the request as written.
"""#'
@usage 'flag --truncate help="Truncate long terminal output to fit the available width" negate=--no-truncate default="true"'
@usage 'flag "-b --backend" help="Only show tools from this backend, such as aqua, cargo, core, or go" var=#true {
        long_help #"""
Only show tools from this backend, such as aqua, cargo, core, or go

Registry shorthands count as the backend they resolve to, so `jq` is listed
under aqua. Repeat the flag to show several backends.
"""#
        arg <BACKEND>
    }'
@usage 'flag "-c --current" help="Only show versions the loaded config files request"'
@usage 'flag "-g --global" help="Only show versions the global config requests" conflicts=--local'
@usage 'flag "-i --installed" help="Only show installed versions" {
        long_help #"""
Only show installed versions

Hides requested versions that are not installed.
"""#
    }'
@usage 'flag --grouped help="List tools in a separate section for each backend" conflicts=--json {
        long_help #"""
List tools in a separate section for each backend

Cannot be combined with --json; use --backend to filter JSON output.
"""#
    }'
@usage 'flag "-J --json" help="Output in JSON format"'
@usage 'flag "-l --local" help="Only show versions the local config requests" conflicts=--global'
@usage 'flag "-m --missing" help="Only show requested versions that are not installed" conflicts=--installed'
@usage r#'flag "-o --offline" help="Don't fetch information such as outdated versions" hide=#true'#
@usage 'flag "-p --plugin" hide=#true {
        arg <PLUGIN>
    }'
@usage 'flag --all-sources help="Show requests from every config file mise has seen, not only loaded ones" {
        long_help #"""
Show requests from every config file mise has seen, not only loaded ones

mise tracks the config files it loads so `mise prune` keeps the versions they use.
"""#
        conflicts "--current" "--global" "--local" "--prunable"
    }'
@usage r#'flag --monorepo help="Also list tools from every config root in `[monorepo].config_roots`" env=MISE_MONOREPO {
        long_help #"""
Also list tools from every config root in `[monorepo].config_roots`

Requires `monorepo_root = true` and an explicit `config_roots` list in the
monorepo root's config. Uses the active MISE_ENV.
"""#
        conflicts "--all-sources" "--prunable"
    }'#
@usage 'flag --no-header help="Do not print the header row" conflicts=--json {
        alias "--no-headers" hide=#true
    }'
@usage 'flag --outdated help="Show whether each version is outdated"'
@usage 'flag --prefix help="Only show versions starting with PREFIX (requires a tool argument)" requires=INSTALLED_TOOL {
        arg <PREFIX>
    }'
@usage 'flag --prunable help="List only tools that can be pruned with `mise prune`"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[INSTALLED_TOOL]…" help="Only show these tools" required=#false var=#true conflicts=--plugin'
@usage 'example "mise ls" help="Show installed versions and the requests from the loaded config files"'
@usage 'example "mise ls --current" help="Show only versions the loaded config files request"'
@usage 'example "mise ls --missing" help="Find requested versions that are not installed"'
@usage 'example "mise ls --json" help="Machine-readable output: an object keyed by tool name"'
@usage 'example "mise ls node --json" help="With a tool argument, JSON output is an array of its version records"'
@usage 'example "mise ls --all-sources" help="Include requests from every config file mise has seen"'
@usage 'example "mise ls --backend go --backend cargo" help="Show only tools from the go or cargo backends"'
@usage 'example "mise ls --grouped" help="List tools in a separate section for each backend"'
@usage 'output "json" framing="json" select="--json" {
    schema "{\n  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",\n  \"$defs\": {\n    \"source\": {\n      \"oneOf\": [\n        {\n          \"type\": \"object\",\n          \"properties\": {\n            \"type\": {\n              \"enum\": [\n                \".tool-versions\",\n                \"mise.toml\",\n                \"mise.toml-daemon\",\n                \"idiomatic-version-file\",\n                \"tool-stub\"\n              ]\n            },\n            \"path\": {\n              \"type\": \"string\"\n            }\n          },\n          \"required\": [\n            \"type\",\n            \"path\"\n          ],\n          \"additionalProperties\": false\n        },\n        {\n          \"type\": \"object\",\n          \"properties\": {\n            \"type\": {\n              \"enum\": [\n                \"argument\",\n                \"unknown\"\n              ]\n            }\n          },\n          \"required\": [\n            \"type\"\n          ],\n          \"additionalProperties\": false\n        },\n        {\n          \"type\": \"object\",\n          \"properties\": {\n            \"type\": {\n              \"const\": \"environment\"\n            },\n            \"key\": {\n              \"type\": \"string\"\n            },\n            \"value\": {\n              \"type\": \"string\"\n            }\n          },\n          \"required\": [\n            \"type\",\n            \"key\",\n            \"value\"\n          ],\n          \"additionalProperties\": false\n        }\n      ]\n    },\n    \"sourceWithRequest\": {\n      \"oneOf\": [\n        {\n          \"type\": \"object\",\n          \"properties\": {\n            \"type\": {\n              \"enum\": [\n                \".tool-versions\",\n                \"mise.toml\",\n                \"mise.toml-daemon\",\n                \"idiomatic-version-file\",\n                \"tool-stub\"\n              ]\n            },\n            \"path\": {\n              \"type\": \"string\"\n            },\n            \"requested_version\": {\n              \"type\": \"string\"\n            }\n          },\n          \"required\": [\n            \"type\",\n            \"path\"\n          ],\n          \"additionalProperties\": false\n        },\n        {\n          \"type\": \"object\",\n          \"properties\": {\n            \"type\": {\n              \"enum\": [\n                \"argument\",\n                \"unknown\"\n              ]\n            },\n            \"requested_version\": {\n              \"type\": \"string\"\n            }\n          },\n          \"required\": [\n            \"type\"\n          ],\n          \"additionalProperties\": false\n        },\n        {\n          \"type\": \"object\",\n          \"properties\": {\n            \"type\": {\n              \"const\": \"environment\"\n            },\n            \"key\": {\n              \"type\": \"string\"\n            },\n            \"value\": {\n              \"type\": \"string\"\n            },\n            \"requested_version\": {\n              \"type\": \"string\"\n            }\n          },\n          \"required\": [\n            \"type\",\n            \"key\",\n            \"value\"\n          ],\n          \"additionalProperties\": false\n        }\n      ]\n    },\n    \"version\": {\n      \"type\": \"object\",\n      \"properties\": {\n        \"version\": {\n          \"type\": \"string\"\n        },\n        \"requested_version\": {\n          \"type\": \"string\"\n        },\n        \"install_path\": {\n          \"type\": \"string\"\n        },\n        \"source\": {\n          \"$ref\": \"#/$defs/source\"\n        },\n        \"sources\": {\n          \"type\": \"array\",\n          \"items\": {\n            \"$ref\": \"#/$defs/sourceWithRequest\"\n          }\n        },\n        \"symlinked_to\": {\n          \"type\": \"string\"\n        },\n        \"broken\": {\n          \"const\": true\n        },\n        \"scheduled_for_pruning\": {\n          \"const\": true\n        },\n        \"prune_after\": {\n          \"type\": \"string\"\n        },\n        \"installed\": {\n          \"type\": \"boolean\"\n        },\n        \"active\": {\n          \"type\": \"boolean\"\n        }\n      },\n      \"required\": [\n        \"version\",\n        \"install_path\",\n        \"installed\",\n        \"active\"\n      ],\n      \"additionalProperties\": false\n    },\n    \"filtered\": {\n      \"type\": \"array\",\n      \"items\": {\n        \"$ref\": \"#/$defs/version\"\n      }\n    },\n    \"all\": {\n      \"type\": \"object\",\n      \"additionalProperties\": {\n        \"$ref\": \"#/$defs/filtered\"\n      }\n    }\n  },\n  \"oneOf\": [\n    {\n      \"$ref\": \"#/$defs/all\"\n    },\n    {\n      \"$ref\": \"#/$defs/filtered\"\n    }\n  ]\n}\n"
}'
export def "mise ls" [
    ...installed_tool: string@"nus complete",     # Only show these tools
    --cd (-C): path@"nus complete",               # Run as if mise were started in DIR
    --env_ (-E): list<string>,                    # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                          # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                                 # Suppress non-error messages
    --verbose (-v): int,                          # Show extra output (use -vv for even more)
    --yes (-y),                                   # Answer yes to all confirmation prompts
    --raw,                                        # Connect tasks and install commands directly to the terminal
    --locked,                                     # Require download URLs from the lockfile when installing
    --silent,                                     # Suppress all task output and mise non-error messages
    --truncate,                                   # Truncate long terminal output to fit the available width
    --no-truncate,                                # Turn off --truncate
    --backend (-b): list<string>@"nus complete",  # Only show tools from this backend, such as aqua, cargo, core, or go
    --current (-c),                               # Only show versions the loaded config files request
    --global (-g),                                # Only show versions the global config requests
    --installed (-i),                             # Only show installed versions
    --grouped,                                    # List tools in a separate section for each backend
    --local (-l),                                 # Only show versions the local config requests
    --missing (-m),                               # Only show requested versions that are not installed
    --all-sources,                                # Show requests from every config file mise has seen, not only loaded ones
    --monorepo,                                   # Also list tools from every config root in `[monorepo].config_roots`
    --no-header,                                  # Do not print the header row
    --outdated,                                   # Show whether each version is outdated
    --prefix: string@"nus complete",              # Only show versions starting with PREFIX (requires a tool argument)
    --prunable,                                   # List only tools that can be pruned with `mise prune`
]: nothing -> oneof<record, table<version: string, install_path: string, installed: bool, active: bool>> {
    let text = ^mise ls --json ...(nus argv [...$installed_tool] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --truncate: $truncate
        --no-truncate: $no_truncate
        --backend: $backend
        --current: $current
        --global: $global
        --installed: $installed
        --grouped: $grouped
        --local: $local
        --missing: $missing
        --all-sources: $all_sources
        --monorepo: $monorepo
        --no-header: $no_header
        --outdated: $outdated
        --prefix: $prefix
        --prunable: $prunable
    })
    nus decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"$defs\":{\"source\":{\"oneOf\":[{\"type\":\"object\",\"properties\":{\"type\":{\"enum\":[\".tool-versions\",\"mise.toml\",\"mise.toml-daemon\",\"idiomatic-version-file\",\"tool-stub\"]},\"path\":{\"type\":\"string\"}},\"required\":[\"type\",\"path\"],\"additionalProperties\":false},{\"type\":\"object\",\"properties\":{\"type\":{\"enum\":[\"argument\",\"unknown\"]}},\"required\":[\"type\"],\"additionalProperties\":false},{\"type\":\"object\",\"properties\":{\"type\":{\"const\":\"environment\"},\"key\":{\"type\":\"string\"},\"value\":{\"type\":\"string\"}},\"required\":[\"type\",\"key\",\"value\"],\"additionalProperties\":false}]},\"sourceWithRequest\":{\"oneOf\":[{\"type\":\"object\",\"properties\":{\"type\":{\"enum\":[\".tool-versions\",\"mise.toml\",\"mise.toml-daemon\",\"idiomatic-version-file\",\"tool-stub\"]},\"path\":{\"type\":\"string\"},\"requested_version\":{\"type\":\"string\"}},\"required\":[\"type\",\"path\"],\"additionalProperties\":false},{\"type\":\"object\",\"properties\":{\"type\":{\"enum\":[\"argument\",\"unknown\"]},\"requested_version\":{\"type\":\"string\"}},\"required\":[\"type\"],\"additionalProperties\":false},{\"type\":\"object\",\"properties\":{\"type\":{\"const\":\"environment\"},\"key\":{\"type\":\"string\"},\"value\":{\"type\":\"string\"},\"requested_version\":{\"type\":\"string\"}},\"required\":[\"type\",\"key\",\"value\"],\"additionalProperties\":false}]},\"version\":{\"type\":\"object\",\"properties\":{\"version\":{\"type\":\"string\"},\"requested_version\":{\"type\":\"string\"},\"install_path\":{\"type\":\"string\"},\"source\":{\"$ref\":\"#/$defs/source\"},\"sources\":{\"type\":\"array\",\"items\":{\"$ref\":\"#/$defs/sourceWithRequest\"}},\"symlinked_to\":{\"type\":\"string\"},\"broken\":{\"const\":true},\"scheduled_for_pruning\":{\"const\":true},\"prune_after\":{\"type\":\"string\"},\"installed\":{\"type\":\"boolean\"},\"active\":{\"type\":\"boolean\"}},\"required\":[\"version\",\"install_path\",\"installed\",\"active\"],\"additionalProperties\":false},\"filtered\":{\"type\":\"array\",\"items\":{\"$ref\":\"#/$defs/version\"}},\"all\":{\"type\":\"object\",\"additionalProperties\":{\"$ref\":\"#/$defs/filtered\"}}},\"oneOf\":[{\"$ref\":\"#/$defs/all\"},{\"$ref\":\"#/$defs/filtered\"}]}" { from json }
}

# List tool versions available to install
#
# Results may be cached; run `mise cache clear TOOL` to refresh one tool
# before querying it again. Version formats and ordering are backend-specific.
@usage 'alias list-all list-remote'
@usage 'long_help #"""
List tool versions available to install

Results may be cached; run `mise cache clear TOOL` to refresh one tool
before querying it again. Version formats and ordering are backend-specific.
"""#'
@usage 'flag --all help="List available versions for every tool mise currently knows about" {
        conflicts TOOL@VERSION PREFIX
    }'
@usage 'flag --minimum-release-age help="Only show versions released before a date or at least a duration ago" {
        alias "--before" hide=#true
        long_help #"""
Only show versions released before a date or at least a duration ago

Takes a date such as `2024-06-01` or a duration such as `90d` or `1y`.
Overrides the `minimum_release_age` setting and tool option.
"""#
        arg <AGE>
    }'
@usage 'flag "-J --json" help="Output in JSON format, with metadata such as `created_at` when available"'
@usage r#'flag --no-versions-host help="Fetch versions from the tool's upstream instead of mise's version mirror" {
        long_help #"""
Fetch versions from the tool's upstream instead of mise's version mirror

Same as `use_versions_host = false` for this command.
"""#
    }'#
@usage 'flag --prerelease help="Include prerelease versions" {
        long_help #"""
Include prerelease versions

Works for backends that report prerelease metadata or detect prereleases by
pattern. Same as MISE_PRERELEASES=1 or the `prereleases` setting, for this
command only.
"""#
    }'
@usage 'flag --strict-metadata help="Exit with an error when release metadata cannot be fetched" {
        long_help #"""
Exit with an error when release metadata cannot be fetched

Without it, backends such as aqua and ruby fall back to a version list
without release dates, or an empty one. Requires --json and
--no-versions-host.
"""#
        requires "--json" "--no-versions-host"
    }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[TOOL@VERSION]" help="Tool to get versions for" required=#false required_unless=--all'
@usage 'arg "[PREFIX]" help="Version prefix to filter by; same as `TOOL@PREFIX`" required=#false'
@usage 'example "mise ls-remote node" help="List every node version"'
@usage 'example "mise ls-remote node@24" help="List node 24.x versions"'
@usage 'example "mise ls-remote node --minimum-release-age 30d" help="Skip versions released in the last 30 days"'
@usage 'example "mise ls-remote github:cli/cli --json" help="Include release dates, as JSON"'
@usage 'output "json" framing="json" select="--json" {
    schema "{\n  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",\n  \"title\": \"mise ls-remote --json\",\n  \"$comment\": \"The --all mode omits release_url/rolling/checksum and always includes nullable prerelease. anyOf allows an empty list in either mode.\",\n  \"$defs\": {\n    \"single\": {\n      \"type\": \"object\",\n      \"properties\": {\n        \"version\": {\n          \"type\": \"string\"\n        },\n        \"created_at\": {\n          \"type\": \"string\"\n        },\n        \"release_url\": {\n          \"type\": \"string\"\n        },\n        \"rolling\": {\n          \"const\": true\n        },\n        \"checksum\": {\n          \"type\": \"string\"\n        },\n        \"prerelease\": {\n          \"type\": \"boolean\"\n        }\n      },\n      \"required\": [\n        \"version\"\n      ],\n      \"additionalProperties\": false\n    },\n    \"all\": {\n      \"type\": \"object\",\n      \"properties\": {\n        \"tool\": {\n          \"type\": \"string\"\n        },\n        \"version\": {\n          \"type\": \"string\"\n        },\n        \"created_at\": {\n          \"type\": \"string\"\n        },\n        \"prerelease\": {\n          \"type\": [\n            \"boolean\",\n            \"null\"\n          ]\n        }\n      },\n      \"required\": [\n        \"tool\",\n        \"version\",\n        \"prerelease\"\n      ],\n      \"additionalProperties\": false\n    }\n  },\n  \"anyOf\": [\n    {\n      \"type\": \"array\",\n      \"items\": {\n        \"$ref\": \"#/$defs/single\"\n      }\n    },\n    {\n      \"type\": \"array\",\n      \"items\": {\n        \"$ref\": \"#/$defs/all\"\n      }\n    }\n  ]\n}\n"
}'
export def "mise ls-remote" [
    tool_version?: string@"nus complete",  # Tool to get versions for
    prefix?: string@"nus complete",        # Version prefix to filter by; same as `TOOL@PREFIX`
    --cd (-C): path@"nus complete",        # Run as if mise were started in DIR
    --env_ (-E): list<string>,             # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                   # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                          # Suppress non-error messages
    --verbose (-v): int,                   # Show extra output (use -vv for even more)
    --yes (-y),                            # Answer yes to all confirmation prompts
    --raw,                                 # Connect tasks and install commands directly to the terminal
    --locked,                              # Require download URLs from the lockfile when installing
    --silent,                              # Suppress all task output and mise non-error messages
    --all,                                 # List available versions for every tool mise currently knows about
    --minimum-release-age: string,         # Only show versions released before a date or at least a duration ago
    --no-versions-host,                    # Fetch versions from the tool's upstream instead of mise's version mirror
    --prerelease,                          # Include prerelease versions
    --strict-metadata,                     # Exit with an error when release metadata cannot be fetched
]: nothing -> oneof<table<version: string>, table<tool: string, version: string, prerelease: oneof<bool, nothing>>> {
    let text = ^mise ls-remote --json ...(nus argv [$tool_version $prefix] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --all: $all
        --minimum-release-age: $minimum_release_age
        --no-versions-host: $no_versions_host
        --prerelease: $prerelease
        --strict-metadata: $strict_metadata
    })
    nus decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"title\":\"mise ls-remote --json\",\"$comment\":\"The --all mode omits release_url/rolling/checksum and always includes nullable prerelease. anyOf allows an empty list in either mode.\",\"$defs\":{\"single\":{\"type\":\"object\",\"properties\":{\"version\":{\"type\":\"string\"},\"created_at\":{\"type\":\"string\"},\"release_url\":{\"type\":\"string\"},\"rolling\":{\"const\":true},\"checksum\":{\"type\":\"string\"},\"prerelease\":{\"type\":\"boolean\"}},\"required\":[\"version\"],\"additionalProperties\":false},\"all\":{\"type\":\"object\",\"properties\":{\"tool\":{\"type\":\"string\"},\"version\":{\"type\":\"string\"},\"created_at\":{\"type\":\"string\"},\"prerelease\":{\"type\":[\"boolean\",\"null\"]}},\"required\":[\"tool\",\"version\",\"prerelease\"],\"additionalProperties\":false}},\"anyOf\":[{\"type\":\"array\",\"items\":{\"$ref\":\"#/$defs/single\"}},{\"type\":\"array\",\"items\":{\"$ref\":\"#/$defs/all\"}}]}" { from json }
}

# Run the language server for mise config files over stdin/stdout
#
# Editors start this command and exchange Language Server Protocol messages with it.
#
# It serves `mise.toml` and the other config files mise loads (`.mise.toml`, `mise.<env>.toml`, `mise.local.toml`, `mise/config.toml`, and the files of a `conf.d`). It ignores every other file, including files that `[task_config] includes` lists, so it can be attached to the TOML language without touching `Cargo.toml` or `pyproject.toml`.
#
# It offers:
# - diagnostics: TOML syntax errors, unknown keys with a suggestion, values of the wrong type, deprecated keys, task names no task defines (`unknown-task`), and dependency cycles (`task-cycle`)
# - completion of keys, including inside inline tables, and of values that have a fixed set
# - hover documentation for keys
# - for tools: completion of tool names under `[tools]` from the registry, and hover with the tool's description and backends
# - quick fixes that replace an unknown key or task name with the suggested one, and rewrite a deprecated key to its replacement when the schema names one
# - formatting, as `mise fmt` does
# - semantic tokens, which color task, tool and env var names, env directives, deprecated keys and the `{{ }}` and `{% %}` of templates
# - for tasks: completion of task names in `depends`, `depends_post`, `wait_for` and `run = [{ task = "..." }]` (and of templates in `extends`), hover with the task's description and command, go to definition, find references, and rename together with every reference in the file
#
# Tasks come from the open file, the configs in the directories above it and the TOML files their `[task_config] includes` name.
#
# A client that runs another TOML server beside this one can switch features off with `initializationOptions`: `{"formatting": false, "hover": false, "completion": false, "definition": false, "references": false, "rename": false, "semanticTokens": false}`.
#
# The server only parses a config. It never renders templates or runs anything, so opening an untrusted file is safe.
#
# A mise that predates this command runs a task named `lsp` instead, so a client that needs to know whether the command exists can check that `mise help lsp` prints `Usage: mise lsp`.
#
# See https://mise.jdx.dev/ide-integration.html for editor configuration.
@usage r#'long_help #"""
Run the language server for mise config files over stdin/stdout

Editors start this command and exchange Language Server Protocol messages with it.

It serves `mise.toml` and the other config files mise loads (`.mise.toml`, `mise.<env>.toml`, `mise.local.toml`, `mise/config.toml`, and the files of a `conf.d`). It ignores every other file, including files that `[task_config] includes` lists, so it can be attached to the TOML language without touching `Cargo.toml` or `pyproject.toml`.

It offers:
- diagnostics: TOML syntax errors, unknown keys with a suggestion, values of the wrong type, deprecated keys, task names no task defines (`unknown-task`), and dependency cycles (`task-cycle`)
- completion of keys, including inside inline tables, and of values that have a fixed set
- hover documentation for keys
- for tools: completion of tool names under `[tools]` from the registry, and hover with the tool's description and backends
- quick fixes that replace an unknown key or task name with the suggested one, and rewrite a deprecated key to its replacement when the schema names one
- formatting, as `mise fmt` does
- semantic tokens, which color task, tool and env var names, env directives, deprecated keys and the `{{ }}` and `{% %}` of templates
- for tasks: completion of task names in `depends`, `depends_post`, `wait_for` and `run = [{ task = "..." }]` (and of templates in `extends`), hover with the task's description and command, go to definition, find references, and rename together with every reference in the file

Tasks come from the open file, the configs in the directories above it and the TOML files their `[task_config] includes` name.

A client that runs another TOML server beside this one can switch features off with `initializationOptions`: `{"formatting": false, "hover": false, "completion": false, "definition": false, "references": false, "rename": false, "semanticTokens": false}`.

The server only parses a config. It never renders templates or runs anything, so opening an untrusted file is safe.

A mise that predates this command runs a task named `lsp` instead, so a client that needs to know whether the command exists can check that `mise help lsp` prints `Usage: mise lsp`.

See https://mise.jdx.dev/ide-integration.html for editor configuration.
"""#'#
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage r#'example "mise lsp" help="Start the server; an editor's LSP configuration runs this command"'#
export def "mise lsp" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise lsp ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Run the Model Context Protocol server over stdin/stdout
#
# Exposes project tools, tasks, environment, and configuration to an MCP client.
# The client, such as an AI coding assistant, starts this command and exchanges
# messages with it. Start it in the project directory or pass `--cd`: the
# resources describe that project.
#
# Resources (JSON):
# - mise://tools: active tool versions (?include_inactive=true adds the rest)
# - mise://tasks: task definitions, including monorepo subproject tasks
# - mise://env: environment variables
# - mise://config: loaded config files and the project root
#
# Environment resources contain real values, including secrets.
#
# Tools:
# - list_commands: every mise command and its declared effect
# - run_task: run a task with your permissions; it can change files and call
#   external services
# - install_tool: install a tool version, as `mise install` does
#
# run_task and install_tool refuse a project whose config files are not
# trusted; run `mise trust` there after reviewing them.
#
# See https://mise.jdx.dev/mcp.html for client configuration and access controls.
@usage 'long_help #"""
Run the Model Context Protocol server over stdin/stdout

Exposes project tools, tasks, environment, and configuration to an MCP client.
The client, such as an AI coding assistant, starts this command and exchanges
messages with it. Start it in the project directory or pass `--cd`: the
resources describe that project.

Resources (JSON):
- mise://tools: active tool versions (?include_inactive=true adds the rest)
- mise://tasks: task definitions, including monorepo subproject tasks
- mise://env: environment variables
- mise://config: loaded config files and the project root

Environment resources contain real values, including secrets.

Tools:
- list_commands: every mise command and its declared effect
- run_task: run a task with your permissions; it can change files and call
  external services
- install_tool: install a tool version, as `mise install` does

run_task and install_tool refuse a project whose config files are not
trusted; run `mise trust` there after reviewing them.

See https://mise.jdx.dev/mcp.html for client configuration and access controls.
"""#'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise --cd /path/to/project mcp" help="Serve a project from another directory, as an MCP client config does"'
export def "mise mcp" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise mcp ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# [experimental] Build, push, and run OCI images of a project's tools
#
# Each tool version becomes its own image layer, so changing one tool version
# rebuilds that tool's layer instead of the whole image.
#
# Requires `mise settings experimental=true` (or `MISE_EXPERIMENTAL=1`).
# Behavior, flags, and output layout may change in future releases.
# See https://mise.jdx.dev/dev-tools/mise-oci.html
@usage r#'long_help #"""
[experimental] Build, push, and run OCI images of a project's tools

Each tool version becomes its own image layer, so changing one tool version
rebuilds that tool's layer instead of the whole image.

Requires `mise settings experimental=true` (or `MISE_EXPERIMENTAL=1`).
Behavior, flags, and output layout may change in future releases.
See https://mise.jdx.dev/dev-tools/mise-oci.html
"""#'#
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise oci" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise oci ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# [experimental] Build an OCI image from the current mise.toml
#
# Each tool version becomes its own content-addressable OCI layer. Bumping a
# tool version invalidates that tool's layer (a Python bump also invalidates
# pypi tool layers, which are relocated against it); other tool layers and the
# base image layers are reused, while the generated /etc/mise/config.toml
# layer, image config, and manifest are regenerated. The output directory
# follows the OCI image-layout spec.
#
# Only tools from project config files are packaged, including a monorepo
# root's config. The global and system configs and a config directly in your
# home directory, such as ~/mise.toml, are left out unless you pass
# `--include-global`.
#
# Build on a Linux host with the image's architecture. Tools are packaged as
# installed on the host, and so is the running mise binary, at
# /usr/local/bin/mise, unless you pass `--no-mise`. asdf plugins are not
# supported; use a vfox plugin or any other backend for each tool. vfox
# plugins are copied into the image next to the tools they install.
#
# Requires `mise settings experimental=true` (or `MISE_EXPERIMENTAL=1`).
@usage r#'long_help #"""
[experimental] Build an OCI image from the current mise.toml

Each tool version becomes its own content-addressable OCI layer. Bumping a
tool version invalidates that tool's layer (a Python bump also invalidates
pypi tool layers, which are relocated against it); other tool layers and the
base image layers are reused, while the generated /etc/mise/config.toml
layer, image config, and manifest are regenerated. The output directory
follows the OCI image-layout spec.

Only tools from project config files are packaged, including a monorepo
root's config. The global and system configs and a config directly in your
home directory, such as ~/mise.toml, are left out unless you pass
`--include-global`.

Build on a Linux host with the image's architecture. Tools are packaged as
installed on the host, and so is the running mise binary, at
/usr/local/bin/mise, unless you pass `--no-mise`. asdf plugins are not
supported; use a vfox plugin or any other backend for each tool. vfox
plugins are copied into the image next to the tools they install.

Requires `mise settings experimental=true` (or `MISE_EXPERIMENTAL=1`).
"""#'#
@usage 'flag --copy help="Copy a host file, directory, or symlink into the image (repeatable, HOST:IMAGE)" var=#true {
            arg <HOST_PATH:IMAGE_PATH>
        }'
@usage 'flag "-o --output" help="Output directory for the OCI image layout" default="./mise-oci" {
            arg <OUTPUT>
        }'
@usage 'flag --from help="Base image reference (overrides [oci].from and the oci.default_from setting)" {
            arg <FROM>
        }'
@usage r#'flag --include-global help="Also package tools from the global and system configs" {
            long_help #"""
Also package tools from the global and system configs

By default `mise oci build` packages only project config files, including a monorepo root's config. With this flag it also includes the tools, `[oci]`, `[bootstrap.packages]`, and `[dotfiles]` of the global and system configs and of a config directly in your home directory, so personal tools from ~/.config/mise/config.toml end up in the image.
"""#
        }'#
@usage 'flag "-t --tag" help="Tag to record in the image index (the org.opencontainers.image.ref.name annotation)" {
            arg <TAG>
        }'
@usage 'flag --mount-point help="Where tools install inside the image" {
            long_help #"""
Where tools install inside the image

Overrides [oci].mount_point and the oci.default_mount_point setting.
"""#
            arg <MOUNT_POINT>
        }'
@usage 'flag --no-mise help="Do not embed the currently-running mise binary at /usr/local/bin/mise"'
@usage 'flag --no-cache help="Rebuild tool layers without reading or writing the local layer cache"'
@usage 'flag --owner help="UID[:GID] to assign to every tar entry in generated layers" {
            long_help #"""
UID[:GID] to assign to every tar entry in generated layers

Overrides [oci].user_id and [oci].group_id. Defaults to 0:0. If GID is omitted, it defaults to UID. This affects file ownership only; [oci].user controls the image USER directive.
"""#
            arg "<UID[:GID]>"
        }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage r#'example "mise oci build" help="Build the project's image into ./mise-oci"'#
@usage 'example "mise oci build --from ubuntu:24.04 --tag myorg/dev:latest -o ./img" help="Use another base image and record a tag"'
@usage 'example "skopeo inspect oci:./img" help="Inspect the result"'
@usage 'example "mise oci run --image-dir ./img -- /bin/sh" help="Open a shell in it"'
@usage 'complete output type=dir'
export def "mise oci build" [
    --cd (-C): path@"nus complete",      # Run as if mise were started in DIR
    --env_ (-E): list<string>,           # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                 # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                        # Suppress non-error messages
    --verbose (-v): int,                 # Show extra output (use -vv for even more)
    --yes (-y),                          # Answer yes to all confirmation prompts
    --output (-o): path@"nus complete",  # Output directory for the OCI image layout
    --raw,                               # Connect tasks and install commands directly to the terminal
    --locked,                            # Require download URLs from the lockfile when installing
    --silent,                            # Suppress all task output and mise non-error messages
    --copy: list<string>,                # Copy a host file, directory, or symlink into the image (repeatable, HOST:IMAGE)
    --from: string,                      # Base image reference (overrides [oci].from and the oci.default_from setting)
    --include-global,                    # Also package tools from the global and system configs
    --tag (-t): string,                  # Tag to record in the image index (the org.opencontainers.image.ref.name annotation)
    --mount-point: string,               # Where tools install inside the image
    --no-mise,                           # Do not embed the currently-running mise binary at /usr/local/bin/mise
    --no-cache,                          # Rebuild tool layers without reading or writing the local layer cache
    --owner: string,                     # UID[:GID] to assign to every tar entry in generated layers
]: nothing -> string {
    ^mise oci build ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --output: $output
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --copy: $copy
        --from: $from
        --include-global: $include_global
        --tag: $tag
        --mount-point: $mount_point
        --no-mise: $no_mise
        --no-cache: $no_cache
        --owner: $owner
    })
}

# [experimental] Build an OCI image and push it to a registry
#
# Builds from the project's config, as `mise oci build` does, unless
# `--image-dir` names an image layout built earlier. Then uploads only the
# blobs the registry does not already have. mise pushes with its own registry
# client, so skopeo, crane, and docker are not needed.
#
# Tool layers whose tool, version, mount point, and file owner match the
# previously pushed image (or `--cache-from`) are reused without being
# rebuilt, so those tools need not be installed locally. Pass `--no-cache` to
# rebuild every tool layer.
#
# Credentials come from the files docker and podman use: `$REGISTRY_AUTH_FILE`,
# `$XDG_RUNTIME_DIR/containers/auth.json`, `~/.config/containers/auth.json`,
# then `~/.docker/config.json`, including inline auths and credential helpers.
# Log in with `docker login` or `podman login`.
#
# Requires `mise settings experimental=true` (or `MISE_EXPERIMENTAL=1`).
@usage r#'long_help #"""
[experimental] Build an OCI image and push it to a registry

Builds from the project's config, as `mise oci build` does, unless
`--image-dir` names an image layout built earlier. Then uploads only the
blobs the registry does not already have. mise pushes with its own registry
client, so skopeo, crane, and docker are not needed.

Tool layers whose tool, version, mount point, and file owner match the
previously pushed image (or `--cache-from`) are reused without being
rebuilt, so those tools need not be installed locally. Pass `--no-cache` to
rebuild every tool layer.

Credentials come from the files docker and podman use: `$REGISTRY_AUTH_FILE`,
`$XDG_RUNTIME_DIR/containers/auth.json`, `~/.config/containers/auth.json`,
then `~/.docker/config.json`, including inline auths and credential helpers.
Log in with `docker login` or `podman login`.

Requires `mise settings experimental=true` (or `MISE_EXPERIMENTAL=1`).
"""#'#
@usage r#'flag --cache-from help="Reuse unchanged tool layers from this image instead of the destination's current tag" {
            long_help #"""
Reuse unchanged tool layers from this image instead of the destination's current tag

Must be in the same repository as the destination. Useful when every push gets a new tag, as with per-commit tags in CI: `mise oci push --cache-from ghcr.io/me/dev:latest ghcr.io/me/dev:$SHA`. Cannot be combined with --no-cache.
"""#
            conflicts "--no-cache" "--image-dir"
            arg <REF>
        }'#
@usage 'flag --from help="Base image for the build" {
            long_help #"""
Base image for the build

Overrides [oci].from and the oci.default_from setting.
"""#
            arg <FROM>
        }'
@usage 'flag --image-dir help="Push an existing OCI image layout instead of building one" {
            long_help #"""
Push an existing OCI image layout instead of building one

Cannot be combined with --cache-from, --from, --include-global, --mount-point, --no-mise, or --owner.
"""#
            conflicts "--from" "--mount-point" "--no-mise" "--owner" "--include-global"
            arg <IMAGE_DIR>
        }'
@usage 'flag --include-global help="Also package tools from the global and system configs" {
            long_help #"""
Also package tools from the global and system configs

See `mise oci build --help` for details.
"""#
        }'
@usage 'flag --mount-point help="Where tools install inside the image" {
            long_help #"""
Where tools install inside the image

Overrides [oci].mount_point and the oci.default_mount_point setting.
"""#
            arg <MOUNT_POINT>
        }'
@usage 'flag --no-cache help="Rebuild tool layers without using the remote or local layer cache"'
@usage 'flag --no-mise help="Do not embed the running mise binary at /usr/local/bin/mise"'
@usage 'flag --owner help="UID[:GID] to assign to every tar entry when building" {
            long_help #"""
UID[:GID] to assign to every tar entry when building

Overrides [oci].user_id and [oci].group_id. Defaults to 0:0. If GID is omitted, it defaults to UID. This affects file ownership only; [oci].user controls the image USER directive.
"""#
            arg "<UID[:GID]>"
        }'
@usage r#'flag --update-index help="Maintain the tag as a multi-arch image index" {
            long_help #"""
Maintain the tag as a multi-arch image index

Pushes this build's manifest by digest and points the tag at an OCI image index containing one entry per platform, preserving entries other architectures pushed. Run `mise oci push --update-index` from one runner per platform to assemble a multi-arch tag.
"""#
        }'#
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <REF> help="Destination registry reference (e.g. `ghcr.io/me/devenv:latest`)"'
@usage 'example "mise oci push ghcr.io/me/devenv:latest" help="Build and push to GHCR"'
@usage 'example #"""
mise oci build -o ./img
mise oci push --image-dir ./img ghcr.io/me/devenv:v1
"""# help="Push an image built earlier"'
@usage 'complete image_dir type=dir'
export def "mise oci push" [
    ref: string,                       # Destination registry reference (e.g. `ghcr.io/me/devenv:latest`)
    --cd (-C): path@"nus complete",    # Run as if mise were started in DIR
    --env_ (-E): list<string>,         # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,               # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                      # Suppress non-error messages
    --verbose (-v): int,               # Show extra output (use -vv for even more)
    --yes (-y),                        # Answer yes to all confirmation prompts
    --raw,                             # Connect tasks and install commands directly to the terminal
    --locked,                          # Require download URLs from the lockfile when installing
    --silent,                          # Suppress all task output and mise non-error messages
    --cache-from: string,              # Reuse unchanged tool layers from this image instead of the destination's current tag
    --from: string,                    # Base image for the build
    --image-dir: path@"nus complete",  # Push an existing OCI image layout instead of building one
    --include-global,                  # Also package tools from the global and system configs
    --mount-point: string,             # Where tools install inside the image
    --no-cache,                        # Rebuild tool layers without using the remote or local layer cache
    --no-mise,                         # Do not embed the running mise binary at /usr/local/bin/mise
    --owner: string,                   # UID[:GID] to assign to every tar entry when building
    --update-index,                    # Maintain the tag as a multi-arch image index
]: nothing -> string {
    ^mise oci push ...(nus argv [$ref] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --cache-from: $cache_from
        --from: $from
        --image-dir: $image_dir
        --include-global: $include_global
        --mount-point: $mount_point
        --no-cache: $no_cache
        --no-mise: $no_mise
        --owner: $owner
        --update-index: $update_index
    })
}

# [experimental] Build the project's image and run a command in it
#
# Builds the image as `mise oci build` does, unless `--image-dir` names an
# existing layout, then loads it into podman or docker and runs the command in
# a container with stdin, stdout, and stderr attached. podman reads the OCI
# layout directly; docker receives it through `docker load`.
#
# Requires `mise settings experimental=true` (or `MISE_EXPERIMENTAL=1`) and
# podman or docker.
@usage r#'long_help #"""
[experimental] Build the project's image and run a command in it

Builds the image as `mise oci build` does, unless `--image-dir` names an
existing layout, then loads it into podman or docker and runs the command in
a container with stdin, stdout, and stderr attached. podman reads the OCI
layout directly; docker receives it through `docker load`.

Requires `mise settings experimental=true` (or `MISE_EXPERIMENTAL=1`) and
podman or docker.
"""#'#
@usage 'flag --engine help="Container engine to use; `auto` prefers podman and falls back to docker" default=auto {
            arg <ENGINE> {
                choices {
                    choice auto
                    choice podman
                    choice docker
                }
            }
        }'
@usage 'flag --from help="Base image for the build" {
            long_help #"""
Base image for the build

Overrides [oci].from and the oci.default_from setting.
"""#
            arg <FROM>
        }'
@usage 'flag --image-dir help="Use an existing OCI image layout instead of building one" {
            long_help #"""
Use an existing OCI image layout instead of building one

Cannot be combined with --from, --include-global, --mount-point, --no-mise, or --owner.
"""#
            conflicts "--from" "--mount-point" "--no-mise" "--owner" "--include-global"
            arg <IMAGE_DIR>
        }'
@usage 'flag --include-global help="Also package tools from the global and system configs" {
            long_help #"""
Also package tools from the global and system configs

See `mise oci build --help` for details.
"""#
        }'
@usage r#'flag --keep help="Keep the loaded image in the engine's storage after the run" {
            long_help #"""
Keep the loaded image in the engine's storage after the run

By default, both the container (`--rm`) and the loaded image are removed when the command exits, so repeated `mise oci run` calls do not fill podman or docker storage. With `--keep`, the image stays under the tag mise used (`mise-oci:run-*` for docker, the pulled image ID for podman).
"""#
        }'#
@usage 'flag --mount-point help="Where tools install inside the image" {
            long_help #"""
Where tools install inside the image

Overrides [oci].mount_point and the oci.default_mount_point setting.
"""#
            arg <MOUNT_POINT>
        }'
@usage 'flag --no-mise help="Do not embed the running mise binary at /usr/local/bin/mise"'
@usage 'flag --owner help="UID[:GID] to assign to every tar entry when building" {
            long_help #"""
UID[:GID] to assign to every tar entry when building

Overrides [oci].user_id and [oci].group_id. Defaults to 0:0. If GID is omitted, it defaults to UID. This affects file ownership only; [oci].user controls the image USER directive.
"""#
            arg "<UID[:GID]>"
        }'
@usage 'flag --volume help="Bind-mount a host path (repeatable, `HOST:CONTAINER[:MODE]`)" var=#true {
            alias "--mount" hide=#true
            long_help #"""
Bind-mount a host path (repeatable, `HOST:CONTAINER[:MODE]`)

Unlike `docker run`, there is no `-v` short form because mise uses `-v` for --verbose. Use `--volume` or `--mount`.
"""#
            arg <HOST:CONTAINER>
        }'
@usage 'flag "-e --env" help="Set environment variable in the container (repeatable, `KEY=VAL`)" var=#true {
            arg "<KEY=VAL>"
        }'
@usage 'flag "-i --interactive" help="Run interactively (pass `-i` to the engine)"'
@usage 'flag "-t --tty" help="Allocate a TTY (pass `-t` to the engine)"'
@usage 'flag "-w --workdir" help="Working directory inside the container" {
            arg <WORKDIR>
        }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[-- CMD]…" help="Command and arguments to run inside the container (after `--`)" required=#false var=#true'
@usage r#'example "mise oci run -it -- bash" help="Build the project's image and open bash in it"'#
@usage 'example "mise oci run -e DEBUG=1 --volume \"$PWD:/work\" -w /work -- npm test" help="Run a one-shot command with an environment variable and a mounted directory"'
@usage r#'example "mise oci build -o ./img && mise oci run --image-dir ./img -- node -e 'console.log(process.version)'" help="Reuse a layout built earlier instead of building again"'#
@usage 'complete image_dir type=dir'
export def "mise oci run" [
    ...cmd: string,                         # Command and arguments to run inside the container (after `--`)
    --cd (-C): path@"nus complete",         # Run as if mise were started in DIR
    --env_ (-E): list<string>,              # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                    # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                           # Suppress non-error messages
    --verbose (-v): int,                    # Show extra output (use -vv for even more)
    --yes (-y),                             # Answer yes to all confirmation prompts
    --raw,                                  # Connect tasks and install commands directly to the terminal
    --locked,                               # Require download URLs from the lockfile when installing
    --silent,                               # Suppress all task output and mise non-error messages
    --engine: string@[auto podman docker],  # Container engine to use; `auto` prefers podman and falls back to docker
    --from: string,                         # Base image for the build
    --image-dir: path@"nus complete",       # Use an existing OCI image layout instead of building one
    --include-global,                       # Also package tools from the global and system configs
    --keep,                                 # Keep the loaded image in the engine's storage after the run
    --mount-point: string,                  # Where tools install inside the image
    --no-mise,                              # Do not embed the running mise binary at /usr/local/bin/mise
    --owner: string,                        # UID[:GID] to assign to every tar entry when building
    --volume: list<string>,                 # Bind-mount a host path (repeatable, `HOST:CONTAINER[:MODE]`)
    --interactive (-i),                     # Run interactively (pass `-i` to the engine)
    --tty (-t),                             # Allocate a TTY (pass `-t` to the engine)
    --workdir (-w): string,                 # Working directory inside the container
]: nothing -> string {
    ^mise oci run ...(nus argv [...$cmd] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --engine: $engine
        --from: $from
        --image-dir: $image_dir
        --include-global: $include_global
        --keep: $keep
        --mount-point: $mount_point
        --no-mise: $no_mise
        --owner: $owner
        --volume: $volume
        --interactive: $interactive
        --tty: $tty
        --workdir: $workdir
    })
}

# Inspect and reset the signers mise has pinned for packslip tools
#
# mise verifies a tool installed with the `packslip:` backend against the
# identity its project name implies, then remembers the signer it accepted,
# the way SSH remembers host keys. A later release from another signer, a
# weaker signing scheme, a repackager where the vendor signed before, or one
# that drops build provenance is refused. After you confirm the change with
# the publisher, run `mise packslip forget <PROJECT>`, and update mise.lock if
# it records the old signer.
#
# With no subcommand, lists the pins (same as `mise packslip pins`).
# See https://mise.jdx.dev/dev-tools/backends/packslip.html#pinned-signers
@usage 'long_help #"""
Inspect and reset the signers mise has pinned for packslip tools

mise verifies a tool installed with the `packslip:` backend against the
identity its project name implies, then remembers the signer it accepted,
the way SSH remembers host keys. A later release from another signer, a
weaker signing scheme, a repackager where the vendor signed before, or one
that drops build provenance is refused. After you confirm the change with
the publisher, run `mise packslip forget <PROJECT>`, and update mise.lock if
it records the old signer.

With no subcommand, lists the pins (same as `mise packslip pins`).
See https://mise.jdx.dev/dev-tools/backends/packslip.html#pinned-signers
"""#'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise packslip" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise packslip ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Forget a project's pinned signer so the next accepted release sets it
#
# Do this after the vendor announces a new signing identity or key. Name the
# project as in its tool identifier: `github.com/owner/repo`, `owner/repo`, or
# a domain such as `tool.example.com`, with or without `packslip:`. This also
# resets the project's remembered release-list state.
#
# It does not change `mise.lock`. If the lockfile records the old signer,
# delete the tool's entries and run `mise lock`.
@usage r#'long_help #"""
Forget a project's pinned signer so the next accepted release sets it

Do this after the vendor announces a new signing identity or key. Name the
project as in its tool identifier: `github.com/owner/repo`, `owner/repo`, or
a domain such as `tool.example.com`, with or without `packslip:`. This also
resets the project's remembered release-list state.

It does not change `mise.lock`. If the lockfile records the old signer,
delete the tool's entries and run `mise lock`.
"""#'#
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <PROJECT> help="The project whose pin to drop"'
@usage 'example "mise packslip forget github.com/jdx/hk" help="Accept whichever signer the next hk release uses"'
export def "mise packslip forget" [
    project: string,                 # The project whose pin to drop
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise packslip forget ...(nus argv [$project] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# List the signer mise has pinned for each packslip project
#
# Each row is a project and the signer mise pinned the first time it accepted
# a release: the signing scheme, the signer identity, whether the vendor or a
# repackager attested it, and whether build provenance links were present. A
# later release that does not match is refused.
@usage 'alias list'
@usage 'long_help #"""
List the signer mise has pinned for each packslip project

Each row is a project and the signer mise pinned the first time it accepted
a release: the signing scheme, the signer identity, whether the vendor or a
repackager attested it, and whether build provenance links were present. A
later release that does not match is refused.
"""#'
@usage 'flag "-J --json" help="Output in JSON format"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example #"""
mise packslip pins
Project            Scheme         Signer                                                   Attested by  Provenance
github.com/jdx/hk  sigstore-oidc  https://github.com/jdx/hk/.github/workflows/release.yml  vendor       yes
"""# help="List every pinned signer"'
@usage 'example "mise packslip pins --json" help="Include the issuer, pin time, and forge repository ID"'
@usage 'output json framing=json select=--json'
export def "mise packslip pins" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
] {
    ^mise packslip pins --json ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    }) | from json
}

# Show outdated tool versions
#
# Lists tools whose installed version is older than the newest version their
# config request allows. For `node = "20"`, that is the newest 20.x release;
# pass `--bump` to compare against the newest release overall instead. Run
# `mise upgrade` to install the newer versions.
@usage 'long_help #"""
Show outdated tool versions

Lists tools whose installed version is older than the newest version their
config request allows. For `node = "20"`, that is the newest 20.x release;
pass `--bump` to compare against the newest release overall instead. Run
`mise upgrade` to install the newer versions.
"""#'
@usage 'after_long_help "\u{1b}[1m\u{1b}[4mDeprecation:\u{1b}[22m\u{1b}[24m\n\nThe `-l` shorthand for `--bump` is deprecated and will be removed in mise 2027.8.5.\nAfter removal, `-l` will become shorthand for `--local`. Use `-b` or `--bump` instead."'
@usage 'flag "-b --bump" help="Compare against the newest release overall, not only the configured range" {
        long_help #"""
Compare against the newest release overall, not only the configured range

With `node = "20"` in your config, `mise outdated` reports the newest 20.x release. With this flag the `latest` column shows the newest release overall, such as 24.1.0, and a `bump` column shows the request `mise upgrade --bump` would write, such as `24`.
"""#
    }'
@usage 'flag "-J --json" help="Output in JSON format"'
@usage 'flag -l help="Deprecated shorthand for --bump" hide=#true'
@usage 'flag --inactive help="Also check installed tools that the current config does not request" conflicts=--local {
        long_help #"""
Also check installed tools that the current config does not request

By default, `mise outdated` checks only tools that come from the current config.
"""#
    }'
@usage 'flag --global help="Only check tools defined in the global config" {
        long_help #"""
Only check tools defined in the global config

Reports the requests in the global and system config (~/.config/mise/config.toml, /etc/mise/config.toml), even where a project config or a `MISE_<TOOL>_VERSION` environment variable sets its own version of the tool: what `mise upgrade --global` would install.
"""#
        conflicts "--local" "--inactive"
    }'
@usage 'flag --local help="Only check tools defined in project config files" {
        long_help #"""
Only check tools defined in project config files

Skips tools defined in the global config (~/.config/mise/config.toml) and tools set through `MISE_<TOOL>_VERSION` environment variables.
"""#
    }'
@usage 'flag --monorepo help="Placeholder for future monorepo outdated checks; `mise outdated --monorepo` is not implemented yet." hide=#true'
@usage 'flag --no-header help="Do not print the table header"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[TOOL@VERSION]…" help="Tools to check, such as `node@20 python@3.10`" help_long=#"""
Tools to check, such as `node@20 python@3.10`

Checks every tool in the global and project configs when omitted.
"""# required=#false var=#true'
@usage 'example #"""
mise outdated
name    requested  current  latest  source
node    20         20.0.0   20.1.0  ~/src/app/mise.toml
python  3.11       3.11.0   3.11.1  ~/src/app/mise.toml
"""# help="Show tools with a newer version inside their configured range"'
@usage 'example #"""
mise outdated --bump
name  requested  current  bump  latest  source
node  20         20.0.0   24    24.1.0  ~/src/app/mise.toml
"""# help="Compare against the newest release overall and show the request for it"'
@usage 'example #"""
mise outdated --json
{
  "node": {
    "name": "node",
    "requested": "20",
    "current": "20.0.0",
    "bump": null,
    "latest": "20.1.0",
    "source": {
      "type": "mise.toml",
      "path": "/home/me/src/app/mise.toml"
    }
  }
}
"""# help="Print the same information as JSON"'
@usage 'example "mise outdated --local" help="Skip tools that only the global config requests"'
@usage r#'example "mise outdated --global claude --json" help="Check the global config's request for claude, even inside a project that sets its own"'#
@usage 'output "json" framing="json" select="--json" {
    schema "{\n  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",\n  \"title\": \"mise outdated --json\",\n  \"$defs\": {\n    \"source\": {\n      \"oneOf\": [\n        {\n          \"type\": \"object\",\n          \"properties\": {\n            \"type\": {\n              \"enum\": [\n                \".tool-versions\",\n                \"mise.toml\",\n                \"mise.toml-daemon\",\n                \"idiomatic-version-file\",\n                \"tool-stub\"\n              ]\n            },\n            \"path\": {\n              \"type\": \"string\"\n            }\n          },\n          \"required\": [\n            \"type\",\n            \"path\"\n          ],\n          \"additionalProperties\": false\n        },\n        {\n          \"type\": \"object\",\n          \"properties\": {\n            \"type\": {\n              \"enum\": [\n                \"argument\",\n                \"unknown\"\n              ]\n            }\n          },\n          \"required\": [\n            \"type\"\n          ],\n          \"additionalProperties\": false\n        },\n        {\n          \"type\": \"object\",\n          \"properties\": {\n            \"type\": {\n              \"const\": \"environment\"\n            },\n            \"key\": {\n              \"type\": \"string\"\n            },\n            \"value\": {\n              \"type\": \"string\"\n            }\n          },\n          \"required\": [\n            \"type\",\n            \"key\",\n            \"value\"\n          ],\n          \"additionalProperties\": false\n        }\n      ]\n    }\n  },\n  \"type\": \"object\",\n  \"additionalProperties\": {\n    \"type\": \"object\",\n    \"properties\": {\n      \"name\": {\n        \"type\": \"string\"\n      },\n      \"requested\": {\n        \"type\": \"string\"\n      },\n      \"current\": {\n        \"type\": [\n          \"string\",\n          \"null\"\n        ]\n      },\n      \"bump\": {\n        \"type\": [\n          \"string\",\n          \"null\"\n        ]\n      },\n      \"latest\": {\n        \"type\": \"string\"\n      },\n      \"release_url\": {\n        \"type\": \"string\"\n      },\n      \"source\": {\n        \"$ref\": \"#/$defs/source\"\n      }\n    },\n    \"required\": [\n      \"name\",\n      \"requested\",\n      \"current\",\n      \"bump\",\n      \"latest\",\n      \"source\"\n    ],\n    \"additionalProperties\": false\n  }\n}\n"
}'
export def "mise outdated" [
    ...tool_version: string@"nus complete",  # Tools to check, such as `node@20 python@3.10`
    --cd (-C): path@"nus complete",          # Run as if mise were started in DIR
    --env_ (-E): list<string>,               # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                     # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                            # Suppress non-error messages
    --verbose (-v): int,                     # Show extra output (use -vv for even more)
    --yes (-y),                              # Answer yes to all confirmation prompts
    --raw,                                   # Connect tasks and install commands directly to the terminal
    --locked,                                # Require download URLs from the lockfile when installing
    --silent,                                # Suppress all task output and mise non-error messages
    --bump (-b),                             # Compare against the newest release overall, not only the configured range
    --inactive,                              # Also check installed tools that the current config does not request
    --global,                                # Only check tools defined in the global config
    --local,                                 # Only check tools defined in project config files
    --no-header,                             # Do not print the table header
]: nothing -> record {
    let text = ^mise outdated --json ...(nus argv [...$tool_version] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --bump: $bump
        --inactive: $inactive
        --global: $global
        --local: $local
        --no-header: $no_header
    })
    nus decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"title\":\"mise outdated --json\",\"$defs\":{\"source\":{\"oneOf\":[{\"type\":\"object\",\"properties\":{\"type\":{\"enum\":[\".tool-versions\",\"mise.toml\",\"mise.toml-daemon\",\"idiomatic-version-file\",\"tool-stub\"]},\"path\":{\"type\":\"string\"}},\"required\":[\"type\",\"path\"],\"additionalProperties\":false},{\"type\":\"object\",\"properties\":{\"type\":{\"enum\":[\"argument\",\"unknown\"]}},\"required\":[\"type\"],\"additionalProperties\":false},{\"type\":\"object\",\"properties\":{\"type\":{\"const\":\"environment\"},\"key\":{\"type\":\"string\"},\"value\":{\"type\":\"string\"}},\"required\":[\"type\",\"key\",\"value\"],\"additionalProperties\":false}]}},\"type\":\"object\",\"additionalProperties\":{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"},\"requested\":{\"type\":\"string\"},\"current\":{\"type\":[\"string\",\"null\"]},\"bump\":{\"type\":[\"string\",\"null\"]},\"latest\":{\"type\":\"string\"},\"release_url\":{\"type\":\"string\"},\"source\":{\"$ref\":\"#/$defs/source\"}},\"required\":[\"name\",\"requested\",\"current\",\"bump\",\"latest\",\"source\"],\"additionalProperties\":false}}" { from json }
}

# Show the individuals supporting mise as Patron-tier members
#
# Fetches the list from https://jdx.dev/patrons.json and caches it for a day;
# pass `--refresh` to fetch it now. If the fetch fails, the cached list is used.
# Terminals that support OSC 8 hyperlinks show each name as a link.
#
# To appear here, become a patron at https://jdx.dev/sponsors.html.
@usage 'long_help #"""
Show the individuals supporting mise as Patron-tier members

Fetches the list from https://jdx.dev/patrons.json and caches it for a day;
pass `--refresh` to fetch it now. If the fetch fails, the cached list is used.
Terminals that support OSC 8 hyperlinks show each name as a link.

To appear here, become a patron at https://jdx.dev/sponsors.html.
"""#'
@usage 'flag "-J --json" help="Output in JSON format"'
@usage 'flag --refresh help="Fetch the list now instead of using the cached copy"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise patrons" help="List the patrons"'
@usage 'example "mise patrons --refresh -J" help="Fetch the list now and print it as JSON"'
@usage 'output json framing=json select=--json'
export def "mise patrons" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --refresh,                       # Fetch the list now instead of using the cached copy
] {
    ^mise patrons --json ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --refresh: $refresh
    }) | from json
}

# Manage plugins
#
# Plugins add tools, backends, environment directives, or bootstrap package
# managers to mise. Most tools need no plugin because most registry tools use
# built-in backends, and mise installs a missing plugin when a configured tool
# needs it.
#
# With no subcommand, lists installed plugins (same as `mise plugins ls`; the
# flags below are passed to it). See https://mise.jdx.dev/plugins.html
@usage 'alias p plugin plugin-list'
@usage 'long_help #"""
Manage plugins

Plugins add tools, backends, environment directives, or bootstrap package
managers to mise. Most tools need no plugin because most registry tools use
built-in backends, and mise installs a missing plugin when a configured tool
needs it.

With no subcommand, lists installed plugins (same as `mise plugins ls`; the
flags below are passed to it). See https://mise.jdx.dev/plugins.html
"""#'
@usage 'flag "-a --all" help="List all available remote plugins (same as `mise plugins ls-remote`)" hide=#true'
@usage 'flag "-c --core" help="List the core tools built into mise instead of installed plugins" conflicts=--all'
@usage r#'flag "-u --urls" help="Show each plugin's Git URL, ref, and commit" {
        alias "--url" hide=#true
    }'#
@usage r#'flag --refs help="Show each plugin's Git ref and commit, such as `main 1234abc`" hide=#true'#
@usage 'flag --user help="List installed plugins" conflicts=--all {
        long_help #"""
List installed plugins

This is the default behavior but can be used with --core
to show core and user plugins
"""#
    }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise plugins" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --core (-c),                     # List the core tools built into mise instead of installed plugins
    --urls (-u),                     # Show each plugin's Git URL, ref, and commit
    --user,                          # List installed plugins
]: nothing -> string {
    ^mise plugins ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --core: $core
        --urls: $urls
        --user: $user
    })
}

# Install plugins from a configured source, Git URL, or archive
#
# Most registry tools use built-in backends and need no plugin. When a tool's
# backend requires a plugin, mise installs it with the tool. Use this command
# to install one ahead of time or from a custom source.
#
# Pass a name that the registry or a `[plugins]` entry knows, a name and a
# URL, or only a URL. With only a URL, the plugin is named after the
# repository without an `asdf-`, `mise-`, or `vfox-` prefix. Pass several names
# to install several plugins. Prefix a name with `vfox:`, `vfox-backend:`,
# `package:`, or `asdf:` to choose the plugin type.
#
# A Git URL may end in `#ref` to select a plugin commit, tag, or branch. This
# selects the plugin code, separately from the tool version `mise use` installs.
@usage 'alias i a add'
@usage r#'long_help #"""
Install plugins from a configured source, Git URL, or archive

Most registry tools use built-in backends and need no plugin. When a tool's
backend requires a plugin, mise installs it with the tool. Use this command
to install one ahead of time or from a custom source.

Pass a name that the registry or a `[plugins]` entry knows, a name and a
URL, or only a URL. With only a URL, the plugin is named after the
repository without an `asdf-`, `mise-`, or `vfox-` prefix. Pass several names
to install several plugins. Prefix a name with `vfox:`, `vfox-backend:`,
`package:`, or `asdf:` to choose the plugin type.

A Git URL may end in `#ref` to select a plugin commit, tag, or branch. This
selects the plugin code, separately from the tool version `mise use` installs.
"""#'#
@usage 'flag "-a --all" help="Install every plugin the current config needs that is not installed yet" {
            long_help #"""
Install every plugin the current config needs that is not installed yet

Only plugins with a registry shorthand or a `[plugins]` entry can be installed this way.
"""#
            conflicts NEW_PLUGIN "--force"
        }'
@usage 'flag "-f --force" help="Reinstall even if the plugin is already installed"'
@usage 'flag "-j --jobs" help="Number of plugins to install in parallel (default: the `jobs` setting)" {
            arg <JOBS>
        }'
@usage 'flag "-v --verbose" help="Show installation output" var=#true count=#true'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[NEW_PLUGIN]" help="The plugin to install, or a URL to infer its name from" required=#false required_unless=--all'
@usage 'arg "[GIT_URL]" help="Where to install from: a Git URL (optionally ending in #ref) or an archive URL" required=#false'
@usage 'arg "[REST]…" required=#false var=#true hide=#true'
@usage 'example "mise plugins install my-tool https://github.com/your-org/mise-my-tool" help="Install a plugin from a Git repository"'
@usage r#'example "mise plugins install my-tool 'https://github.com/your-org/mise-my-tool#v1.2.0'" help="Pin the plugin to a tag"'#
@usage 'example "mise plugins install https://github.com/your-org/vfox-my-tool" help="Name the plugin after its repository (my-tool)"'
@usage 'example "mise plugins install my-tool file:///path/to/mise-my-tool#v1.0.0" help="Use a local plugin repository at a tag you created"'
@usage 'example "mise plugins install --all" help="Install the plugins that the current config needs"'
@usage 'complete git_url type=url'
export def "mise plugins install" [
    new_plugin?: string@"nus complete",  # The plugin to install, or a URL to infer its name from
    git_url?: string@"nus complete",     # Where to install from: a Git URL (optionally ending in #ref) or an archive URL
    ...rest: string,
    --cd (-C): path@"nus complete",      # Run as if mise were started in DIR
    --env_ (-E): list<string>,           # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --force (-f),                        # Reinstall even if the plugin is already installed
    --jobs (-j): string,                 # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                        # Suppress non-error messages
    --verbose (-v): int,                 # Show extra output (use -vv for even more)
    --yes (-y),                          # Answer yes to all confirmation prompts
    --raw,                               # Connect tasks and install commands directly to the terminal
    --locked,                            # Require download URLs from the lockfile when installing
    --silent,                            # Suppress all task output and mise non-error messages
    --all (-a),                          # Install every plugin the current config needs that is not installed yet
]: nothing -> string {
    ^mise plugins install ...(nus argv [$new_plugin $git_url ...$rest] {
        --cd: $cd
        --env: $env_
        --force: $force
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --all: $all
    })
}

# Link a local plugin directory into mise for development
#
# Edits in the source directory take effect without reinstalling the plugin.
# Pass a name and a directory, or only a directory to name the plugin after it
# without an `asdf-`, `mise-`, or `vfox-` prefix. Use the bare name, without a
# `vfox:` or `package:` prefix: mise detects the plugin type from the
# directory. This does not install a tool version.
@usage 'alias ln'
@usage 'long_help #"""
Link a local plugin directory into mise for development

Edits in the source directory take effect without reinstalling the plugin.
Pass a name and a directory, or only a directory to name the plugin after it
without an `asdf-`, `mise-`, or `vfox-` prefix. Use the bare name, without a
`vfox:` or `package:` prefix: mise detects the plugin type from the
directory. This does not install a tool version.
"""#'
@usage 'flag "-f --force" help="Replace an existing plugin with the same name"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <NAME> help="The plugin name, or the plugin directory when DIR is omitted"'
@usage 'arg "[DIR]" help="The local path to the plugin, such as ./mise-my-tool" required=#false'
@usage 'example "mise plugins link my-tool ./mise-my-tool" help="Link ./mise-my-tool as the plugin my-tool"'
@usage 'example "mise plugins link ./mise-my-tool" help="Infer the name my-tool from the directory"'
@usage 'example "mise ls-remote my-tool" help="List versions through the linked plugin"'
@usage 'complete dir type=dir'
export def "mise plugins link" [
    name: string,                    # The plugin name, or the plugin directory when DIR is omitted
    dir?: path@"nus complete",       # The local path to the plugin, such as ./mise-my-tool
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --force (-f),                    # Replace an existing plugin with the same name
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise plugins link ...(nus argv [$name $dir] {
        --cd: $cd
        --env: $env_
        --force: $force
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# List installed plugins
#
# Use `--core` to list the core tools built into mise instead, or
# `--core --user` for both. `--outdated` checks each plugin's Git remote for
# newer plugin code; it does not compare tool versions. Use `mise ls` for
# installed tool versions and `mise registry` for tools you can install.
@usage 'alias list'
@usage r#'long_help #"""
List installed plugins

Use `--core` to list the core tools built into mise instead, or
`--core --user` for both. `--outdated` checks each plugin's Git remote for
newer plugin code; it does not compare tool versions. Use `mise ls` for
installed tool versions and `mise registry` for tools you can install.
"""#'#
@usage 'flag "-a --all" help="List all available remote plugins (same as `mise plugins ls-remote`)" hide=#true'
@usage 'flag "-c --core" help="List the core tools built into mise instead of installed plugins" conflicts=--all'
@usage 'flag "-o --outdated" help="Only show plugins whose Git remote has newer commits"'
@usage r#'flag "-u --urls" help="Show each plugin's Git URL, ref, and commit" {
            alias "--url" hide=#true
        }'#
@usage r#'flag --refs help="Show each plugin's Git ref and commit, such as `main 1234abc`" hide=#true'#
@usage 'flag --user help="List installed plugins" conflicts=--all {
            long_help #"""
List installed plugins

This is the default behavior but can be used with --core
to show core and user plugins
"""#
        }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise plugins ls" help="List installed plugins"'
@usage r#'example "mise plugins ls --urls" help="Show each plugin's Git URL, ref, and commit"'#
@usage 'example "mise plugins ls --core --user" help="List core tools and installed plugins"'
@usage 'example "mise plugins ls --outdated" help="List plugins whose Git remote has newer commits"'
export def "mise plugins ls" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --core (-c),                     # List the core tools built into mise instead of installed plugins
    --urls (-u),                     # Show each plugin's Git URL, ref, and commit
    --user,                          # List installed plugins
    --outdated (-o),                 # Only show plugins whose Git remote has newer commits
]: nothing -> string {
    ^mise plugins ls ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --core: $core
        --urls: $urls
        --user: $user
        --outdated: $outdated
    })
}

# List registry tools that have an asdf or vfox plugin backend
#
# Each line is a registry shorthand that lists an asdf or vfox plugin among its
# backends; mise may still install the tool through another backend first. `*`
# marks plugins you have installed. Entries from the `shorthands_file` setting
# are listed too. Use `mise registry` to list every registry tool and its
# backends in order.
@usage 'alias list-remote list-all'
@usage 'long_help #"""
List registry tools that have an asdf or vfox plugin backend

Each line is a registry shorthand that lists an asdf or vfox plugin among its
backends; mise may still install the tool through another backend first. `*`
marks plugins you have installed. Entries from the `shorthands_file` setting
are listed too. Use `mise registry` to list every registry tool and its
backends in order.
"""#'
@usage 'flag "-u --urls" help="Show the plugin source for each shorthand, e.g. vfox:jdx/vfox-poetry"'
@usage 'flag --only-names help="Only show the name of each plugin, without the `*` marking installed plugins"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise plugins ls-remote" help="List registry tools with a plugin backend"'
export def "mise plugins ls-remote" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --urls (-u),                     # Show the plugin source for each shorthand, e.g. vfox:jdx/vfox-poetry
    --only-names,                    # Only show the name of each plugin, without the `*` marking installed plugins
]: nothing -> string {
    ^mise plugins ls-remote ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --urls: $urls
        --only-names: $only_names
    })
}

# Remove an installed plugin
#
# Installed tool versions are kept unless you pass `--purge`, which also
# removes a tool plugin's installs, downloads, and cache. `--purge` does not
# remove the tools of a backend plugin (`<plugin>:<tool>`); uninstall those
# first with `mise uninstall --all <plugin>:<tool>`.
@usage 'alias remove rm'
@usage r#'long_help #"""
Remove an installed plugin

Installed tool versions are kept unless you pass `--purge`, which also
removes a tool plugin's installs, downloads, and cache. `--purge` does not
remove the tools of a backend plugin (`<plugin>:<tool>`); uninstall those
first with `mise uninstall --all <plugin>:<tool>`.
"""#'#
@usage 'flag "-a --all" help="Remove all plugins" conflicts=PLUGIN'
@usage r#'flag "-p --purge" help="Also remove a tool plugin's installs, downloads, and cache"'#
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[PLUGIN]…" help="Plugins to remove" required=#false var=#true'
@usage 'example "mise plugins uninstall my-tool" help="Remove the plugin and keep the versions it installed"'
@usage 'example "mise plugins uninstall --purge my-tool" help="Also delete the versions it installed"'
export def "mise plugins uninstall" [
    ...plugin: string@"nus complete",  # Plugins to remove
    --cd (-C): path@"nus complete",    # Run as if mise were started in DIR
    --env_ (-E): list<string>,         # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,               # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                      # Suppress non-error messages
    --verbose (-v): int,               # Show extra output (use -vv for even more)
    --yes (-y),                        # Answer yes to all confirmation prompts
    --raw,                             # Connect tasks and install commands directly to the terminal
    --locked,                          # Require download URLs from the lockfile when installing
    --silent,                          # Suppress all task output and mise non-error messages
    --all (-a),                        # Remove all plugins
    --purge (-p),                      # Also remove a tool plugin's installs, downloads, and cache
]: nothing -> string {
    ^mise plugins uninstall ...(nus argv [...$plugin] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --all: $all
        --purge: $purge
    })
}

# Update installed plugins
#
# With no names, updates every installed plugin. This updates the plugin code,
# not the tool versions it manages. Linked local plugins are skipped; plugins
# installed from an archive cannot be updated with Git.
@usage 'alias up upgrade'
@usage 'long_help #"""
Update installed plugins

With no names, updates every installed plugin. This updates the plugin code,
not the tool versions it manages. Linked local plugins are skipped; plugins
installed from an archive cannot be updated with Git.
"""#'
@usage 'flag "-j --jobs" help="Number of plugins to update in parallel (default: the `jobs` setting)" {
            arg <JOBS>
        }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[PLUGIN]…" help="Plugins to update; append #ref to switch to a branch, tag, or commit" required=#false var=#true'
@usage 'example "mise plugins update" help="Update every installed plugin"'
@usage 'example "mise plugins update my-tool" help="Update one plugin"'
@usage 'example "mise plugins update my-tool#main" help="Switch a plugin to its main branch"'
export def "mise plugins update" [
    ...plugin: string@"nus complete",  # Plugins to update; append #ref to switch to a branch, tag, or commit
    --cd (-C): path@"nus complete",    # Run as if mise were started in DIR
    --env_ (-E): list<string>,         # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,               # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                      # Suppress non-error messages
    --verbose (-v): int,               # Show extra output (use -vv for even more)
    --yes (-y),                        # Answer yes to all confirmation prompts
    --raw,                             # Connect tasks and install commands directly to the terminal
    --locked,                          # Require download URLs from the lockfile when installing
    --silent,                          # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise plugins update ...(nus argv [...$plugin] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# [experimental] Manage project dependencies
#
# Installs project dependencies such as node_modules, separately from the tools
# `mise install` manages. Each provider is one package-manager step: a built-in
# one such as npm or uv, or a custom `[deps.<name>]` command. A provider runs only
# when its inputs changed or its outputs are missing; `--explain` shows why.
#
# With no subcommand, runs `mise deps install`. Providers with `auto = true` also
# run before `mise exec` and `mise run` unless you pass --no-deps.
@usage 'alias dep prepare'
@usage 'long_help #"""
[experimental] Manage project dependencies

Installs project dependencies such as node_modules, separately from the tools
`mise install` manages. Each provider is one package-manager step: a built-in
one such as npm or uv, or a custom `[deps.<name>]` command. A provider runs only
when its inputs changed or its outputs are missing; `--explain` shows why.

With no subcommand, runs `mise deps install`. Providers with `auto = true` also
run before `mise exec` and `mise run` unless you pass --no-deps.
"""#'
@usage 'after_long_help "\u{1b}[1m\u{1b}[4mConfiguration:\u{1b}[22m\u{1b}[24m\n\n```toml\n# Built-in npm provider; needs package.json and package-lock.json\n[deps.npm]\nauto = true              # run before mise exec and mise run\n\n# Custom provider\n[deps.codegen]\nauto = true\nsources = [\"schema/*.graphql\"]\noutputs = [\"src/generated/\"]\nrun = \"npm run codegen\"\n```\n\nSee https://mise.jdx.dev/dev-tools/deps.html."'
@usage 'flag --explain help="Show why a provider is fresh or stale, and exit non-zero unless it is fresh (requires a PROVIDER argument)"'
@usage 'flag "-f --force" help="Run providers even when their outputs are up to date"'
@usage 'flag "-n --dry-run" help="Show which providers would run, without running them"'
@usage 'flag --list help="List configured providers with their status, sources, and outputs"'
@usage r#'flag --monorepo help="Also run providers from every config root in `[monorepo].config_roots`" env=MISE_MONOREPO {
        long_help #"""
Also run providers from every config root in `[monorepo].config_roots`

Requires `monorepo_root = true` and an explicit `config_roots` list in the
monorepo root's config. Provider names then include their root, such as
`//apps/api:uv`.
"""#
    }'#
@usage 'flag --only help="Run only these providers" var=#true {
        arg <PROVIDER>
    }'
@usage 'flag --skip help="Skip these providers" var=#true {
        arg <PROVIDER>
    }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[PROVIDER]" help="Run only this provider, or explain it with --explain" required=#false'
@usage 'example "mise deps" help="Run every provider that is out of date"'
@usage 'example "mise deps install npm --explain" help="Show why the npm provider would or would not run"'
@usage 'example "mise deps --monorepo" help="Include providers from every monorepo config root"'
export def "mise deps" [
    provider?: string,               # Run only this provider, or explain it with --explain
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --force (-f),                    # Run providers even when their outputs are up to date
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                  # Show which providers would run, without running them
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --explain,                       # Show why a provider is fresh or stale, and exit non-zero unless it is fresh (requires a PROVIDER argument)
    --list,                          # List configured providers with their status, sources, and outputs
    --monorepo,                      # Also run providers from every config root in `[monorepo].config_roots`
    --only: list<string>,            # Run only these providers
    --skip: list<string>,            # Skip these providers
]: nothing -> string {
    ^mise deps ...(nus argv [$provider] {
        --cd: $cd
        --env: $env_
        --force: $force
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --explain: $explain
        --list: $list
        --monorepo: $monorepo
        --only: $only
        --skip: $skip
    })
}

# Add packages to the project's dependencies
#
# Runs the package manager's own add command, which updates the project's
# manifest (for npm, package.json) and its lockfile, not mise.toml. To install a
# CLI tool from npm for mise to manage, use `mise use npm:<package>` instead.
# Name each package as `<ecosystem>:<package>`, such as `npm:react` or
# `npm:@types/react@19`. See
# https://mise.jdx.dev/dev-tools/deps.html#adding-and-removing-packages.
@usage r#'long_help #"""
Add packages to the project's dependencies

Runs the package manager's own add command, which updates the project's
manifest (for npm, package.json) and its lockfile, not mise.toml. To install a
CLI tool from npm for mise to manage, use `mise use npm:<package>` instead.
Name each package as `<ecosystem>:<package>`, such as `npm:react` or
`npm:@types/react@19`. See
https://mise.jdx.dev/dev-tools/deps.html#adding-and-removing-packages.
"""#'#
@usage 'flag "-D --dev" help="Add as a development dependency"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <PACKAGES>… help="Packages to add, such as `npm:react` or `npm:@types/react@19`" var=#true'
@usage 'example "mise deps add npm:react" help="Add react to package.json"'
@usage 'example "mise deps add -D npm:vitest" help="Add vitest as a dev dependency"'
export def "mise deps add" [
    ...packages: string,             # Packages to add, such as `npm:react` or `npm:@types/react@19`
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --dev (-D),                      # Add as a development dependency
]: nothing -> string {
    ^mise deps add ...(nus argv [...$packages] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --dev: $dev
    })
}

# Install project dependencies
#
# Runs each provider whose inputs changed or whose outputs are missing. Pass
# PROVIDER to run only that one, --force to run regardless, or
# `--explain PROVIDER` to see why it would or would not run. With --explain,
# mise runs nothing and exits non-zero unless the provider is fresh.
@usage 'long_help #"""
Install project dependencies

Runs each provider whose inputs changed or whose outputs are missing. Pass
PROVIDER to run only that one, --force to run regardless, or
`--explain PROVIDER` to see why it would or would not run. With --explain,
mise runs nothing and exits non-zero unless the provider is fresh.
"""#'
@usage 'flag --explain help="Show why a provider is fresh or stale, and exit non-zero unless it is fresh (requires a PROVIDER argument)"'
@usage 'flag "-f --force" help="Run providers even when their outputs are up to date"'
@usage 'flag "-n --dry-run" help="Show which providers would run, without running them"'
@usage 'flag --list help="List configured providers with their status, sources, and outputs"'
@usage r#'flag --monorepo help="Also run providers from every config root in `[monorepo].config_roots`" env=MISE_MONOREPO {
            long_help #"""
Also run providers from every config root in `[monorepo].config_roots`

Requires `monorepo_root = true` and an explicit `config_roots` list in the
monorepo root's config. Provider names then include their root, such as
`//apps/api:uv`.
"""#
        }'#
@usage 'flag --only help="Run only these providers" var=#true {
            arg <PROVIDER>
        }'
@usage 'flag --skip help="Skip these providers" var=#true {
            arg <PROVIDER>
        }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[PROVIDER]" help="Run only this provider, or explain it with --explain" required=#false'
@usage 'example "mise deps install" help="Run every provider that is out of date"'
@usage 'example "mise deps install --force" help="Run every provider, even fresh ones"'
@usage 'example "mise deps install --dry-run" help="Show which providers would run"'
export def "mise deps install" [
    provider?: string,               # Run only this provider, or explain it with --explain
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --force (-f),                    # Run providers even when their outputs are up to date
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                  # Show which providers would run, without running them
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --explain,                       # Show why a provider is fresh or stale, and exit non-zero unless it is fresh (requires a PROVIDER argument)
    --list,                          # List configured providers with their status, sources, and outputs
    --monorepo,                      # Also run providers from every config root in `[monorepo].config_roots`
    --only: list<string>,            # Run only these providers
    --skip: list<string>,            # Skip these providers
]: nothing -> string {
    ^mise deps install ...(nus argv [$provider] {
        --cd: $cd
        --env: $env_
        --force: $force
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --explain: $explain
        --list: $list
        --monorepo: $monorepo
        --only: $only
        --skip: $skip
    })
}

# Remove packages from the project's dependencies
#
# Runs the package manager's remove command, which updates the project's manifest
# and its lockfile, not mise.toml. Name each package as `<ecosystem>:<package>`,
# such as `npm:lodash`.
@usage r#'long_help #"""
Remove packages from the project's dependencies

Runs the package manager's remove command, which updates the project's manifest
and its lockfile, not mise.toml. Name each package as `<ecosystem>:<package>`,
such as `npm:lodash`.
"""#'#
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <PACKAGES>… help="Packages to remove, such as `npm:lodash`" var=#true'
@usage 'example "mise deps remove npm:lodash" help="Remove lodash from package.json"'
export def "mise deps remove" [
    ...packages: string,             # Packages to remove, such as `npm:lodash`
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise deps remove ...(nus argv [...$packages] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Delete tool versions that nothing uses
#
# mise records each config file it loads (in ~/.local/state/mise/tracked-configs)
# and each tool stub it runs (in ~/.local/state/mise/tracked-stubs). `mise prune`
# deletes installed versions that none of them selects. A config that requests
# `node = "20"` keeps only the 20.x version it resolves to. Versions installed
# only for `mise exec <TOOL>@<VERSION>` or through `MISE_<TOOL>_VERSION` are
# deleted. Versions that a running process was started from are kept, so a
# long-running program keeps its files.
#
# It also forgets tracked, trusted, and ignored config files that no longer
# exist. Pass `--tools` or `--configs` to do only one of the two. List the
# versions it would delete with `mise ls --prunable`.
@usage 'long_help #"""
Delete tool versions that nothing uses

mise records each config file it loads (in ~/.local/state/mise/tracked-configs)
and each tool stub it runs (in ~/.local/state/mise/tracked-stubs). `mise prune`
deletes installed versions that none of them selects. A config that requests
`node = "20"` keeps only the 20.x version it resolves to. Versions installed
only for `mise exec <TOOL>@<VERSION>` or through `MISE_<TOOL>_VERSION` are
deleted. Versions that a running process was started from are kept, so a
long-running program keeps its files.

It also forgets tracked, trusted, and ignored config files that no longer
exist. Pass `--tools` or `--configs` to do only one of the two. List the
versions it would delete with `mise ls --prunable`.
"""#'
@usage 'flag "-n --dry-run" help="Show what would change without changing anything"'
@usage 'flag --configs help="Only forget tracked, trusted, and ignored config files that no longer exist"'
@usage 'flag --dry-run-code help="Like --dry-run, but exit with code 1 if there are tools to prune" {
        long_help #"""
Like --dry-run, but exit with code 1 if there are tools to prune

Use it in scripts that check whether tools need pruning.
"""#
    }'
@usage 'flag --monorepo help="Placeholder for future monorepo pruning; `mise prune --monorepo` is not implemented yet." hide=#true'
@usage 'flag --tools help="Only delete unused tool versions"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[INSTALLED_TOOL]…" help="Prune only these tools" required=#false var=#true'
@usage 'example #"""
mise prune --dry-run
mise node@20.0.0 is prunable: node is required at 20.19.5 by ~/src/app/mise.toml
mise node@20.0.0 [dryrun]  remove ~/.local/share/mise/installs/node/20.0.0, ~/.cache/mise/node/20.0.0
"""# help="Preview what would be deleted and why"'
@usage 'example "mise prune --tools node" help="Delete unused node versions only"'
export def "mise prune" [
    ...installed_tool: string@"nus complete",  # Prune only these tools
    --cd (-C): path@"nus complete",            # Run as if mise were started in DIR
    --env_ (-E): list<string>,                 # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                       # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                            # Show what would change without changing anything
    --quiet (-q),                              # Suppress non-error messages
    --verbose (-v): int,                       # Show extra output (use -vv for even more)
    --yes (-y),                                # Answer yes to all confirmation prompts
    --raw,                                     # Connect tasks and install commands directly to the terminal
    --locked,                                  # Require download URLs from the lockfile when installing
    --silent,                                  # Suppress all task output and mise non-error messages
    --configs,                                 # Only forget tracked, trusted, and ignored config files that no longer exist
    --dry-run-code,                            # Like --dry-run, but exit with code 1 if there are tools to prune
    --tools,                                   # Only delete unused tool versions
]: nothing -> string {
    ^mise prune ...(nus argv [...$installed_tool] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --configs: $configs
        --dry-run-code: $dry_run_code
        --tools: $tools
    })
}

# List registry shorthand names and their backends
#
# The registry maps short names to backends. For example, `node` uses the
# built-in node backend (`core:node`). When a tool lists several backends, mise
# uses the first one that this platform and your settings allow. An explicit
# identifier such as `aqua:jqlang/jq`, a `[tool_alias]` entry, or a
# `MISE_BACKENDS_<TOOL>` environment variable overrides that choice.
#
# This is not a list of every tool mise can install. Use an explicit identifier
# such as `github:owner/repo` for a source without a registry shorthand.
@usage 'long_help #"""
List registry shorthand names and their backends

The registry maps short names to backends. For example, `node` uses the
built-in node backend (`core:node`). When a tool lists several backends, mise
uses the first one that this platform and your settings allow. An explicit
identifier such as `aqua:jqlang/jq`, a `[tool_alias]` entry, or a
`MISE_BACKENDS_<TOOL>` environment variable overrides that choice.

This is not a list of every tool mise can install. Use an explicit identifier
such as `github:owner/repo` for a source without a registry shorthand.
"""#'
@usage 'flag "-b --backend" help="Show only tools for this backend" {
        arg <BACKEND>
    }'
@usage 'flag --complete help="Print all tools with descriptions for shell completions" hide=#true'
@usage 'flag --hide-aliased help="Hide names that are aliases of another registry tool"'
@usage 'flag "-J --json" help="Output in JSON format"'
@usage r#'flag --security help="Include security features for each tool's backends in JSON output" requires=--json {
        long_help #"""
Include security features for each tool's backends in JSON output

Requires --json. Features are merged across a tool's backends. Each backend is resolved separately, so this slows down a full listing.
"""#
    }'#
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage r#'arg "[NAME]" help="Show only this tool's backends, in the order mise prefers them" required=#false'#
@usage 'example "mise registry" help="List every registry tool and its backends"'
@usage 'example #"""
mise registry jq
aqua:jqlang/jq asdf:mise-plugins/asdf-jq
"""# help="Show the backends for one tool"'
@usage 'example "mise registry --backend aqua" help="List the tools that have an aqua backend"'
@usage 'example "mise registry --json" help="Print the registry as JSON"'
@usage 'output "json" framing="json" select="--json" {
    schema "{\n  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",\n  \"title\": \"mise registry [tool] --json\",\n  \"$defs\": {\n    \"security\": {\n      \"oneOf\": [\n        {\n          \"type\": \"object\",\n          \"properties\": {\n            \"type\": {\n              \"const\": \"checksum\"\n            },\n            \"algorithm\": {\n              \"type\": \"string\"\n            }\n          },\n          \"required\": [\n            \"type\"\n          ],\n          \"additionalProperties\": false\n        },\n        {\n          \"type\": \"object\",\n          \"properties\": {\n            \"type\": {\n              \"const\": \"github_attestations\"\n            },\n            \"signer_workflow\": {\n              \"type\": \"string\"\n            }\n          },\n          \"required\": [\n            \"type\"\n          ],\n          \"additionalProperties\": false\n        },\n        {\n          \"type\": \"object\",\n          \"properties\": {\n            \"type\": {\n              \"const\": \"slsa\"\n            },\n            \"level\": {\n              \"type\": \"integer\",\n              \"minimum\": 0,\n              \"maximum\": 255\n            }\n          },\n          \"required\": [\n            \"type\"\n          ],\n          \"additionalProperties\": false\n        },\n        {\n          \"type\": \"object\",\n          \"properties\": {\n            \"type\": {\n              \"const\": \"minisign\"\n            },\n            \"public_key\": {\n              \"type\": \"string\"\n            }\n          },\n          \"required\": [\n            \"type\"\n          ],\n          \"additionalProperties\": false\n        },\n        {\n          \"type\": \"object\",\n          \"properties\": {\n            \"type\": {\n              \"enum\": [\n                \"cosign\",\n                \"packslip\",\n                \"gpg\"\n              ]\n            }\n          },\n          \"required\": [\n            \"type\"\n          ],\n          \"additionalProperties\": false\n        }\n      ]\n    },\n    \"tool\": {\n      \"type\": \"object\",\n      \"properties\": {\n        \"short\": {\n          \"type\": \"string\"\n        },\n        \"backends\": {\n          \"type\": \"array\",\n          \"items\": {\n            \"type\": \"string\"\n          }\n        },\n        \"bins\": {\n          \"type\": \"array\",\n          \"items\": {\n            \"type\": \"string\"\n          },\n          \"minItems\": 1\n        },\n        \"description\": {\n          \"type\": \"string\"\n        },\n        \"url\": {\n          \"type\": \"string\"\n        },\n        \"aliases\": {\n          \"type\": \"array\",\n          \"items\": {\n            \"type\": \"string\"\n          },\n          \"minItems\": 1\n        },\n        \"security\": {\n          \"type\": \"array\",\n          \"items\": {\n            \"$ref\": \"#/$defs/security\"\n          },\n          \"minItems\": 1\n        }\n      },\n      \"required\": [\n        \"short\",\n        \"backends\"\n      ],\n      \"additionalProperties\": false\n    }\n  },\n  \"oneOf\": [\n    {\n      \"$ref\": \"#/$defs/tool\"\n    },\n    {\n      \"type\": \"array\",\n      \"items\": {\n        \"$ref\": \"#/$defs/tool\"\n      }\n    }\n  ]\n}\n"
}'
export def "mise registry" [
    name?: string,                          # Show only this tool's backends, in the order mise prefers them
    --cd (-C): path@"nus complete",         # Run as if mise were started in DIR
    --env_ (-E): list<string>,              # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                    # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                           # Suppress non-error messages
    --verbose (-v): int,                    # Show extra output (use -vv for even more)
    --yes (-y),                             # Answer yes to all confirmation prompts
    --raw,                                  # Connect tasks and install commands directly to the terminal
    --locked,                               # Require download URLs from the lockfile when installing
    --silent,                               # Suppress all task output and mise non-error messages
    --backend (-b): string@"nus complete",  # Show only tools for this backend
    --hide-aliased,                         # Hide names that are aliases of another registry tool
    --security,                             # Include security features for each tool's backends in JSON output
]: nothing -> oneof<record<short: string, backends: list<string>>, table<short: string, backends: list<string>>> {
    let text = ^mise registry --json ...(nus argv [$name] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --backend: $backend
        --hide-aliased: $hide_aliased
        --security: $security
    })
    nus decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"title\":\"mise registry [tool] --json\",\"$defs\":{\"security\":{\"oneOf\":[{\"type\":\"object\",\"properties\":{\"type\":{\"const\":\"checksum\"},\"algorithm\":{\"type\":\"string\"}},\"required\":[\"type\"],\"additionalProperties\":false},{\"type\":\"object\",\"properties\":{\"type\":{\"const\":\"github_attestations\"},\"signer_workflow\":{\"type\":\"string\"}},\"required\":[\"type\"],\"additionalProperties\":false},{\"type\":\"object\",\"properties\":{\"type\":{\"const\":\"slsa\"},\"level\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":255}},\"required\":[\"type\"],\"additionalProperties\":false},{\"type\":\"object\",\"properties\":{\"type\":{\"const\":\"minisign\"},\"public_key\":{\"type\":\"string\"}},\"required\":[\"type\"],\"additionalProperties\":false},{\"type\":\"object\",\"properties\":{\"type\":{\"enum\":[\"cosign\",\"packslip\",\"gpg\"]}},\"required\":[\"type\"],\"additionalProperties\":false}]},\"tool\":{\"type\":\"object\",\"properties\":{\"short\":{\"type\":\"string\"},\"backends\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}},\"bins\":{\"type\":\"array\",\"items\":{\"type\":\"string\"},\"minItems\":1},\"description\":{\"type\":\"string\"},\"url\":{\"type\":\"string\"},\"aliases\":{\"type\":\"array\",\"items\":{\"type\":\"string\"},\"minItems\":1},\"security\":{\"type\":\"array\",\"items\":{\"$ref\":\"#/$defs/security\"},\"minItems\":1}},\"required\":[\"short\",\"backends\"],\"additionalProperties\":false}},\"oneOf\":[{\"$ref\":\"#/$defs/tool\"},{\"type\":\"array\",\"items\":{\"$ref\":\"#/$defs/tool\"}}]}" { from json }
}

# Create shims for executables provided by installed tools
#
# Run this when an executable was added to an existing installation outside
# mise, for example after a language package manager installed a CLI globally.
# It rebuilds your shim directory (~/.local/share/mise/shims by default).
# `--system` rebuilds the system shim directory used by `mise install --system`.
#
# Shims are created for all installed versions. When invoked, a shim picks the
# version to run from the current config. `--force` rebuilds mise-owned shims;
# it does not turn unrelated files into mise-owned shims.
# See https://mise.jdx.dev/dev-tools/shims.html
@usage 'long_help #"""
Create shims for executables provided by installed tools

Run this when an executable was added to an existing installation outside
mise, for example after a language package manager installed a CLI globally.
It rebuilds your shim directory (~/.local/share/mise/shims by default).
`--system` rebuilds the system shim directory used by `mise install --system`.

Shims are created for all installed versions. When invoked, a shim picks the
version to run from the current config. `--force` rebuilds mise-owned shims;
it does not turn unrelated files into mise-owned shims.
See https://mise.jdx.dev/dev-tools/shims.html
"""#'
@usage 'flag "-f --force" help="Rebuild all mise-owned shims"'
@usage 'flag --system help="Rebuild the system shims, for tools installed with `mise install --system`"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[TOOL]" required=#false hide=#true'
@usage 'arg "[VERSION]" required=#false hide=#true'
@usage 'example #"""
mise reshim
~/.local/share/mise/shims/node -v
v24.11.0
"""# help="Rebuild shims, then run node through its shim"'
export def "mise reshim" [
    tool?: string@"nus complete",
    version?: string,
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --force (-f),                    # Rebuild all mise-owned shims
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --system,                        # Rebuild the system shims, for tools installed with `mise install --system`
]: nothing -> string {
    ^mise reshim ...(nus argv [$tool $version] {
        --cd: $cd
        --env: $env_
        --force: $force
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --system: $system
    })
}

# Run tasks and their dependencies
#
# Run one task with `mise run TASK [ARGS...]`, or several with `:::` between them. Put mise flags before the task name; everything after it goes to the task. With no task, mise runs the `default` task if there is one, or opens a task picker in an interactive terminal.
#
# Tasks come from `[tasks]` in `mise.toml` and from task directories such as `mise-tasks/`. A task with `sources` and `outputs` is skipped while its outputs are up to date; `--force` runs it anyway. For example:
#
# ```toml
# [tasks.build]
# run = "npm run build"
# sources = ["src/**/*.ts", "package.json", "package-lock.json"]
# outputs = ["dist/**/*.js"]
# ```
#
# The experimental artifact cache (a task's `cache` field) has separate `--task-cache` controls.
#
# To create a script task, run `mise tasks add --file hello -- echo hello`, then `mise run hello`. See https://mise.jdx.dev/tasks/running-tasks.html
@usage 'alias r'
@usage r#'long_help #"""
Run tasks and their dependencies

Run one task with `mise run TASK [ARGS...]`, or several with `:::` between them. Put mise flags before the task name; everything after it goes to the task. With no task, mise runs the `default` task if there is one, or opens a task picker in an interactive terminal.

Tasks come from `[tasks]` in `mise.toml` and from task directories such as `mise-tasks/`. A task with `sources` and `outputs` is skipped while its outputs are up to date; `--force` runs it anyway. For example:

```toml
[tasks.build]
run = "npm run build"
sources = ["src/**/*.ts", "package.json", "package-lock.json"]
outputs = ["dist/**/*.js"]
```

The experimental artifact cache (a task's `cache` field) has separate `--task-cache` controls.

To create a script task, run `mise tasks add --file hello -- echo hello`, then `mise run hello`. See https://mise.jdx.dev/tasks/running-tasks.html
"""#'#
@usage 'flag --affected help="Run matching tasks only in projects affected by Git changes" {
        long_help #"""
Run matching tasks only in projects affected by Git changes

Counts committed changes between the base and head revisions, plus staged, unstaged, and untracked changes in the working tree when the head revision is the checked-out commit. Requires a monorepo root (`monorepo_root = true`).
"""#
    }'
@usage 'flag --affected-base help="Git base revision for `--affected`" requires=--affected {
        long_help #"""
Git base revision for `--affected`

Defaults to `MISE_AFFECTED_BASE`, CI metadata, or `HEAD~1`.
"""#
        arg <REV>
    }'
@usage 'flag --affected-committed help="Count committed changes between the base and head revisions" requires=--affected {
        long_help #"""
Count committed changes between the base and head revisions

Alone, ignores the working tree. Combines with `--affected-uncommitted` and `--affected-untracked`. With none of the three, every source counts (the working-tree sources only when the head revision is the checked-out commit). Also set by `MISE_AFFECTED_COMMITTED`.
"""#
    }'
@usage 'flag --affected-explain help="Explain why `--affected` selected each project and task" conflicts=--affected-json requires=--affected'
@usage 'flag --affected-head help="Git head revision for `--affected`" requires=--affected {
        long_help #"""
Git head revision for `--affected`

Defaults to `MISE_AFFECTED_HEAD`, CI metadata, or `HEAD`.
"""#
        arg <REV>
    }'
@usage 'flag --affected-json help="Print the affected projects and tasks as JSON without running tasks" conflicts=--affected-explain requires=--affected'
@usage 'flag --affected-uncommitted help="Count staged and unstaged changes to tracked files" requires=--affected {
        long_help #"""
Count staged and unstaged changes to tracked files

Combines with the other source flags. Alone, ignores committed changes. Needs the head revision to be the current checkout. Also set by `MISE_AFFECTED_UNCOMMITTED`.
"""#
    }'
@usage 'flag --affected-untracked help="Count untracked files that Git does not ignore" requires=--affected {
        long_help #"""
Count untracked files that Git does not ignore

Combines with the other source flags. Alone, ignores committed changes. Needs the head revision to be the current checkout. Also set by `MISE_AFFECTED_UNTRACKED`.
"""#
    }'
@usage 'flag --all help="Open the task picker with tasks from every project in the monorepo" conflicts=--affected'
@usage 'flag "-c --continue-on-error" help="Continue running tasks even if one fails"'
@usage 'flag "-C --cd" help="Change to this directory before running the tasks" {
        arg <DIR>
    }'
@usage 'flag "-f --force" help="Run the tasks even if their outputs are up to date"'
@usage 'flag "-j --jobs" help="Number of tasks to run in parallel (default: the `jobs` setting)" env=MISE_JOBS {
        long_help #"""
Number of tasks to run in parallel (default: the `jobs` setting)

Values below 1 are treated as 1.
"""#
        arg <JOBS>
    }'
@usage 'flag "-n --dry-run" help="Print the tasks in the order they would run, without running them"'
@usage r#'flag "-o --output" help="How task output is displayed" env=MISE_TASK_OUTPUT {
        long_help #"""
How task output is displayed

- `prefix` - Print stdout/stderr by line, prefixed with the task's label
- `interleave` - Print directly to stdout/stderr instead of by line
- `replacing` - Stdout is replaced each time, stderr is printed as is
- `timed` - Only show stdout lines if they are displayed for more than 1 second
- `keep-order` - Print stdout/stderr by line, prefixed with the task's label, but keep the order of the output
- `quiet` - Deprecated; use `--output interleave --quiet`
- `silent` - Do not show any output, including the task's stdout and stderr, except errors
"""#
        arg <OUTPUT>
    }'#
@usage 'flag "-q --quiet" help="Do not show extra output" env=MISE_QUIET'
@usage 'flag "-r --raw" help="Connect the tasks directly to stdin, stdout, and stderr instead of reading their output by line" {
        long_help #"""
Connect the tasks directly to stdin, stdout, and stderr instead of reading their output by line

Redactions are not applied, and tasks run one at a time. Set the `raw` setting to make this the default.
"""#
    }'
@usage 'flag --secrets help="[experimental] Give the named tasks these secrets (comma-separated); their dependencies and subtasks do not get them" var=#true conflicts=--affected {
        long_help #"""
[experimental] Give the named tasks these secrets (comma-separated); their dependencies and subtasks do not get them

Put this flag before the task name. Not allowed in safe mode.
"""#
        arg <SECRET> delimiter=,
    }'
@usage 'flag --secrets-all help="[experimental] Give the named tasks every secret the project can inject; their dependencies and subtasks do not get them" {
        long_help #"""
[experimental] Give the named tasks every secret the project can inject; their dependencies and subtasks do not get them

Covers the fnox secrets with `env = true` or `env = "exec"`, never those with `env = false`. Put this flag before the task name. Not allowed in safe mode.
"""#
        conflicts "--secrets" "--affected"
    }'
@usage r#'flag "-s --shell" help="Shell used to run TOML tasks that do not set their own `shell`" {
        long_help #"""
Shell used to run TOML tasks that do not set their own `shell`

Defaults to `sh -o errexit -c` on Unix and `cmd /c` on Windows, from the `unix_default_inline_shell_args` or `windows_default_inline_shell_args` setting. A task's `shell` property takes precedence over this flag.
"""#
        arg <SHELL>
    }'#
@usage 'flag "-S --silent" help="Do not show any output except for errors" env=MISE_SILENT'
@usage 'flag "-t --tool" help="Extra tools to use with the tasks, e.g. node@24 python@3.13" var=#true {
        arg <TOOL@VERSION>
    }'
@usage r#'flag --allow-env help="Allow a specific env var through (implies `--deny-env` for everything else)" var=#true {
        long_help #"""
Allow a specific env var through (implies `--deny-env` for everything else)

Supports wildcards, such as `--allow-env='MYAPP_*'`.
"""#
        arg <VAR>
    }'#
@usage 'flag --allow-net help="Allow network access only to HOST (not supported on any platform)" var=#true {
        long_help #"""
Allow network access only to HOST (not supported on any platform)

Per-host filtering does not work: Linux and macOS exit with an error, and Windows runs the task without network restrictions. See https://mise.jdx.dev/sandboxing.html#access-to-particular-hosts
"""#
        arg <HOST>
    }'
@usage 'flag --allow-read help="Allow reads from a specific path (implies `--deny-read` for everything else)" var=#true {
        arg <PATH>
    }'
@usage 'flag --allow-write help="Allow writes to a specific path (implies `--deny-write` for everything else)" var=#true {
        arg <PATH>
    }'
@usage 'flag --deny-all help="Block reads, writes, network, and env vars"'
@usage 'flag --deny-env help="Block env var inheritance except PATH, HOME, USER, SHELL, TERM, COLORTERM, and LANG" {
        long_help #"""
Block env var inheritance except PATH, HOME, USER, SHELL, TERM, COLORTERM, and LANG

On Windows it also keeps the variables programs need to start, such as `SystemRoot` and `TEMP`.
"""#
    }'
@usage 'flag --deny-net help="Block all network access"'
@usage 'flag --deny-read help="Block filesystem reads (system libraries and tool directories stay readable)"'
@usage 'flag --deny-write help="Block filesystem writes except temporary and device paths (/tmp, /dev)"'
@usage 'flag --fresh-env help="Bypass the environment cache and recompute the environment"'
@usage 'flag --no-cache help="Do not use the cache for remote tasks" env=MISE_TASK_REMOTE_NO_CACHE'
@usage 'flag --no-deps help="Do not run `[deps]` providers that have `auto = true` before the tasks"'
@usage 'flag --no-timings help="Hide the elapsed time printed after each task completes" {
        alias "--no-timing" hide=#true
        long_help #"""
Hide the elapsed time printed after each task completes

Set `task.timings = false` to hide it by default.
"""#
    }'
@usage 'flag --skip-deps help="Run only the named tasks, not the tasks they depend on" env=MISE_TASK_SKIP_DEPENDS'
@usage 'flag --skip-tools help="Do not install missing tools before running the tasks" {
        long_help #"""
Do not install missing tools before running the tasks

Set `task.run_auto_install = false` to make this the default.
"""#
    }'
@usage 'flag --task-cache help="[experimental] Set artifact cache access for this run" env=MISE_TASK_CACHE default=read-write {
        long_help #"""
[experimental] Set artifact cache access for this run

- `read-write` - Read cached results and write new results
- `read-only` - Read cached results without writing new results
- `write-only` - Write new results without reading cached results
- `off` - Disable the artifact cache
- `local-only` - Read and write only the local cache, skipping any remote cache
"""#
        arg <TASK_CACHE> {
            choices {
                choice read-write help="Read cached results and write new results."
                choice read-only help="Read cached results without writing new results."
                choice write-only help="Write new results without reading cached results."
                choice off help="Disable task output caching for this run."
                choice local-only help="Read and write only the local cache."
            }
        }
    }'
@usage r#'flag --task-cache-explain help="[experimental] Explain the inputs that produced each task's artifact cache key"'#
@usage 'flag --task-cache-explain-json help="[experimental] Print cache-key input details as JSON Lines without running tasks (requires `--dry-run`)" conflicts=--task-cache-explain requires=--dry-run'
@usage 'flag --task-cache-stats help="[experimental] Report artifact cache hits, restored bytes, and time saved" conflicts=--dry-run'
@usage 'flag --timeout help="Stop the run if it takes longer than this, e.g. 30s or 5m" {
        long_help #"""
Stop the run if it takes longer than this, e.g. 30s or 5m

Overrides the `task.timeout` setting.
"""#
        arg <TIMEOUT>
    }'
@usage 'flag --timings help="Show the elapsed time after each task completes" hide=#true {
        alias "--timing" hide=#true
        long_help #"""
Show the elapsed time after each task completes

Set `task.timings = true` to show it by default.
"""#
    }'
@usage 'mount run="mise tasks --usage" synopsis="[TASK] [ARGS]…"'
@usage 'example "mise run lint" help="Run the \"lint\" task, defined in mise.toml or as a script"'
@usage 'example "mise run --force build" help="Run \"build\" even if its outputs are up to date"'
@usage 'example "mise run --raw test" help="Run \"test\" connected directly to the terminal, one task at a time"'
@usage 'example "mise run lint ::: test ::: check" help="Run the \"lint\", \"test\", and \"check\" tasks in parallel"'
@usage 'example "mise run cmd1 arg1 arg2 ::: cmd2 arg1 arg2" help="Run several tasks, each with its own arguments"'
@usage 'example "mise run -j 1 lint ::: test" help="Run tasks one at a time"'
@usage r#'example "mise run 'test:*'" help="Run every task that matches a pattern"'#
@usage 'example "mise run //services/api:build" help="Run a task in a monorepo project"'
@usage 'example "mise run --secrets DEPLOY_KEY deploy" help="Give \"deploy\" the DEPLOY_KEY secret (experimental); its dependencies do not get it"'
@usage 'complete dir type=dir'
export def "mise run" [
    --continue-on-error (-c),                                               # Continue running tasks even if one fails
    --cd (-C): path@"nus complete",                                         # Run as if mise were started in DIR
    --env_ (-E): list<string>,                                              # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --force (-f),                                                           # Run the tasks even if their outputs are up to date
    --jobs (-j): string,                                                    # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                                                         # Print the tasks in the order they would run, without running them
    --quiet (-q),                                                           # Suppress non-error messages
    --shell (-s): string,                                                   # Shell used to run TOML tasks that do not set their own `shell`
    --tool (-t): list<string>@"nus complete",                               # Extra tools to use with the tasks, e.g. node@24 python@3.13
    --verbose (-v): int,                                                    # Show extra output (use -vv for even more)
    --yes (-y),                                                             # Answer yes to all confirmation prompts
    --no-timings,                                                           # Hide the elapsed time printed after each task completes
    --output (-o): string,                                                  # How task output is displayed
    --raw (-r),                                                             # Connect tasks and install commands directly to the terminal
    --locked,                                                               # Require download URLs from the lockfile when installing
    --silent (-S),                                                          # Suppress all task output and mise non-error messages
    --affected,                                                             # Run matching tasks only in projects affected by Git changes
    --affected-base: string,                                                # Git base revision for `--affected`
    --affected-committed,                                                   # Count committed changes between the base and head revisions
    --affected-explain,                                                     # Explain why `--affected` selected each project and task
    --affected-head: string,                                                # Git head revision for `--affected`
    --affected-json,                                                        # Print the affected projects and tasks as JSON without running tasks
    --affected-uncommitted,                                                 # Count staged and unstaged changes to tracked files
    --affected-untracked,                                                   # Count untracked files that Git does not ignore
    --all,                                                                  # Open the task picker with tasks from every project in the monorepo
    --secrets: list<string>@"nus complete",                                 # [experimental] Give the named tasks these secrets (comma-separated); their dependencies and subtasks do not get them
    --secrets-all,                                                          # [experimental] Give the named tasks every secret the project can inject; their dependencies and subtasks do not get them
    --allow-env: list<string>,                                              # Allow a specific env var through (implies `--deny-env` for everything else)
    --allow-net: list<string>,                                              # Allow network access only to HOST (not supported on any platform)
    --allow-read: list<string>,                                             # Allow reads from a specific path (implies `--deny-read` for everything else)
    --allow-write: list<string>,                                            # Allow writes to a specific path (implies `--deny-write` for everything else)
    --deny-all,                                                             # Block reads, writes, network, and env vars
    --deny-env,                                                             # Block env var inheritance except PATH, HOME, USER, SHELL, TERM, COLORTERM, and LANG
    --deny-net,                                                             # Block all network access
    --deny-read,                                                            # Block filesystem reads (system libraries and tool directories stay readable)
    --deny-write,                                                           # Block filesystem writes except temporary and device paths (/tmp, /dev)
    --fresh-env,                                                            # Bypass the environment cache and recompute the environment
    --no-cache,                                                             # Do not use the cache for remote tasks
    --no-deps,                                                              # Do not run `[deps]` providers that have `auto = true` before the tasks
    --skip-deps,                                                            # Run only the named tasks, not the tasks they depend on
    --skip-tools,                                                           # Do not install missing tools before running the tasks
    --task-cache: string@[read-write read-only write-only off local-only],  # [experimental] Set artifact cache access for this run
    --task-cache-explain,                                                   # [experimental] Explain the inputs that produced each task's artifact cache key
    --task-cache-explain-json,                                              # [experimental] Print cache-key input details as JSON Lines without running tasks (requires `--dry-run`)
    --task-cache-stats,                                                     # [experimental] Report artifact cache hits, restored bytes, and time saved
    --timeout: string,                                                      # Stop the run if it takes longer than this, e.g. 30s or 5m
]: nothing -> string {
    ^mise run ...(nus argv [] {
        --continue-on-error: $continue_on_error
        --cd: $cd
        --env: $env_
        --force: $force
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --shell: $shell
        --tool: $tool
        --verbose: $verbose
        --yes: $yes
        --no-timings: $no_timings
        --output: $output
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --affected: $affected
        --affected-base: $affected_base
        --affected-committed: $affected_committed
        --affected-explain: $affected_explain
        --affected-head: $affected_head
        --affected-json: $affected_json
        --affected-uncommitted: $affected_uncommitted
        --affected-untracked: $affected_untracked
        --all: $all
        --secrets: $secrets
        --secrets-all: $secrets_all
        --allow-env: $allow_env
        --allow-net: $allow_net
        --allow-read: $allow_read
        --allow-write: $allow_write
        --deny-all: $deny_all
        --deny-env: $deny_env
        --deny-net: $deny_net
        --deny-read: $deny_read
        --deny-write: $deny_write
        --fresh-env: $fresh_env
        --no-cache: $no_cache
        --no-deps: $no_deps
        --skip-deps: $skip_deps
        --skip-tools: $skip_tools
        --task-cache: $task_cache
        --task-cache-explain: $task_cache_explain
        --task-cache-explain-json: $task_cache_explain_json
        --task-cache-stats: $task_cache_stats
        --timeout: $timeout
    })
}

# Search for available tools
#
# Searches the registry and the tool lists of installed backend plugins for
# tools matching NAME. When nothing matches, it also searches the aqua
# registry. Prefix NAME with `npm:`, `cargo:`, `gem:`, or `dotnet:` to also
# search that package registry, or pass `--all` to search every source.
#
# Matching is fuzzy by default. Use `--match-type equal` or
# `--match-type contains` for stricter matches.
@usage 'long_help #"""
Search for available tools

Searches the registry and the tool lists of installed backend plugins for
tools matching NAME. When nothing matches, it also searches the aqua
registry. Prefix NAME with `npm:`, `cargo:`, `gem:`, or `dotnet:` to also
search that package registry, or pass `--all` to search every source.

Matching is fuzzy by default. Use `--match-type equal` or
`--match-type contains` for stricter matches.
"""#'
@usage 'flag "-a --all" help="Search every source: the registry, aqua, installed backend plugins, and the npm, cargo, gem, and dotnet package registries"'
@usage 'flag "-i --interactive" help="Show an interactive search menu" {
        conflicts "--match-type" "--no-header"
    }'
@usage 'flag "-m --match-type" help="Match type: equal, contains, or fuzzy" default=fuzzy {
        arg <MATCH_TYPE> {
            choices {
                choice equal
                choice contains
                choice fuzzy
            }
        }
    }'
@usage 'flag --no-header help="Do not print the table header" {
        alias "--no-headers" hide=#true
    }'
@usage 'flag --complete help="Print all tools with descriptions for shell completions" hide=#true'
@usage 'flag --complete-ids help="Print only tool identifiers for shell completions" hide=#true'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[NAME]" help="The tool to search for" required=#false'
@usage 'example #"""
mise search jq
Tool  Description
jq    Command-line JSON processor. https://github.com/jqlang/jq
jqp   A TUI playground to experiment with jq. https://github.com/noahgorstein/jqp
jiq   jid on jq - interactive JSON query tool using jq expressions. https://github.com/fiatjaf/jiq
gojq  Pure Go implementation of jq. https://github.com/itchyny/gojq
"""# help="Fuzzy-search the registry for jq"'
@usage 'example #"""
mise search --match-type equal npm:typescript-language-server
Tool                            Description
npm:typescript-language-server  Language Server Protocol (LSP) implementation for TypeScript using tsserver
"""# help="Look up one npm package by its exact name"'
@usage 'example "mise search --interactive" help="Pick a tool from a filterable list"'
export def "mise search" [
    name?: string,                                     # The tool to search for
    --cd (-C): path@"nus complete",                    # Run as if mise were started in DIR
    --env_ (-E): list<string>,                         # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                               # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                                      # Suppress non-error messages
    --verbose (-v): int,                               # Show extra output (use -vv for even more)
    --yes (-y),                                        # Answer yes to all confirmation prompts
    --raw,                                             # Connect tasks and install commands directly to the terminal
    --locked,                                          # Require download URLs from the lockfile when installing
    --silent,                                          # Suppress all task output and mise non-error messages
    --all (-a),                                        # Search every source: the registry, aqua, installed backend plugins, and the npm, cargo, gem, and dotnet package registries
    --interactive (-i),                                # Show an interactive search menu
    --match-type (-m): string@[equal contains fuzzy],  # Match type: equal, contains, or fuzzy
    --no-header,                                       # Do not print the table header
]: nothing -> string {
    ^mise search ...(nus argv [$name] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --all: $all
        --interactive: $interactive
        --match-type: $match_type
        --no-header: $no_header
    })
}

# [experimental] Inspect the project's secrets source
#
# With no subcommand, lists secret names (same as `mise secrets ls`; the flags
# below are passed to it). See https://mise.jdx.dev/environments/secrets/fnox.html
@usage r#'long_help #"""
[experimental] Inspect the project's secrets source

With no subcommand, lists secret names (same as `mise secrets ls`; the flags
below are passed to it). See https://mise.jdx.dev/environments/secrets/fnox.html
"""#'#
@usage 'flag "-J --json" help="Output in JSON format"'
@usage 'flag --no-header help="Do not print the table header"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'output json framing=json select=--json'
export def "mise secrets" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --no-header,                     # Do not print the table header
] {
    ^mise secrets --json ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --no-header: $no_header
    }) | from json
}

# [experimental] List secret names from the project's secrets source
#
# Shows names and metadata, never values. The source is declared in the
# project's `mise.toml` with `[secrets.fnox]`. A line describing the source
# goes to stderr and the table to stdout.
#
# Columns:
# - ENV: the key's `env` setting in the source: true, exec, false, or - if unset
# - FILE: whether the value is handed over as a file
# - SCOPES: where mise can grant the key: run (tasks) and exec (`mise exec`)
# - TASKS: the tasks that request the key
#
# A SCOPES value of - means the key cannot be granted. A file secret can be
# granted to tasks only, because `mise exec` cannot clean up the file after it
# hands the process over.
@usage 'alias list'
@usage r#'long_help #"""
[experimental] List secret names from the project's secrets source

Shows names and metadata, never values. The source is declared in the
project's `mise.toml` with `[secrets.fnox]`. A line describing the source
goes to stderr and the table to stdout.

Columns:
- ENV: the key's `env` setting in the source: true, exec, false, or - if unset
- FILE: whether the value is handed over as a file
- SCOPES: where mise can grant the key: run (tasks) and exec (`mise exec`)
- TASKS: the tasks that request the key

A SCOPES value of - means the key cannot be granted. A file secret can be
granted to tasks only, because `mise exec` cannot clean up the file after it
hands the process over.
"""#'#
@usage 'flag "-J --json" help="Output in JSON format"'
@usage 'flag --no-header help="Do not print the table header"'
@usage 'flag --complete help="Render completions: the injectable key names, one per line" hide=#true'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example #"""
mise secrets ls
KEY                ENV    FILE  SCOPES     TASKS   DESCRIPTION
AWS_ACCESS_KEY_ID  -      no    run, exec          (lease aws)
DATABASE_URL       true   no    run, exec  deploy  app database
GCP_SA_JSON        exec   yes   run                service account
SIGNING_KEY        false  no    -                  release signing key
"""# help="List the secret names and how each can be granted"'
@usage 'output json framing=json select=--json'
export def "mise secrets ls" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --no-header,                     # Do not print the table header
] {
    ^mise secrets ls --json ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --no-header: $no_header
    }) | from json
}

# Update mise itself
#
# Installs the newest stable release, or VERSION, from GitHub Releases and
# verifies its signature before replacing the running binary. Without VERSION,
# releases younger than the minimum release age are skipped: the
# `self_update.minimum_release_age` setting, then `minimum_release_age`, else
# 24h. Installed plugins are updated too unless you pass `--no-plugins`. Set
# `self_update.auto` to update automatically.
#
# If a package manager such as Homebrew or apt installed mise, update it with
# that package manager instead: https://mise.jdx.dev/installing-mise.html#updating
# Packagers can disable this command: https://mise.jdx.dev/packaging.html
@usage 'long_help #"""
Update mise itself

Installs the newest stable release, or VERSION, from GitHub Releases and
verifies its signature before replacing the running binary. Without VERSION,
releases younger than the minimum release age are skipped: the
`self_update.minimum_release_age` setting, then `minimum_release_age`, else
24h. Installed plugins are updated too unless you pass `--no-plugins`. Set
`self_update.auto` to update automatically.

If a package manager such as Homebrew or apt installed mise, update it with
that package manager instead: https://mise.jdx.dev/installing-mise.html#updating
Packagers can disable this command: https://mise.jdx.dev/packaging.html
"""#'
@usage 'flag --minimum-release-age help="Minimum release age for this update, such as 7d" {
        long_help #"""
Minimum release age for this update, such as 7d

Defaults to the self_update.minimum_release_age setting, then the minimum_release_age setting, else 24h.
"""#
        arg <MINIMUM_RELEASE_AGE>
    }'
@usage 'flag "-f --force" help="Update even if already up to date" {
        long_help #"""
Update even if already up to date

Also updates when the package that installed mise has disabled self-update.
"""#
    }'
@usage 'flag "-y --yes" help="Skip confirmation prompt"'
@usage 'flag --no-plugins help="Do not update installed plugins"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[VERSION]" help="Update to a specific version, skipping the minimum release age" required=#false'
@usage 'example "mise self-update" help="Update to the newest eligible release"'
@usage 'example "mise self-update 2026.10.4" help="Install a specific release"'
@usage 'example "mise self-update -y --no-plugins" help="Update without prompting or touching plugins"'
export def "mise self-update" [
    version?: string,                # Update to a specific version, skipping the minimum release age
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --force (-f),                    # Update even if already up to date
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --minimum-release-age: string,   # Minimum release age for this update, such as 7d
    --no-plugins,                    # Do not update installed plugins
]: nothing -> string {
    ^mise self-update ...(nus argv [$version] {
        --cd: $cd
        --env: $env_
        --force: $force
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --minimum-release-age: $minimum_release_age
        --no-plugins: $no_plugins
    })
}

# Set, show, or list environment variables in mise.toml
#
# `mise set KEY=VALUE` writes to the lowest-precedence TOML file in the nearest
# config directory (`mise.toml` rather than `mise.local.toml`), creating
# `mise.toml` in the current directory if there is none. Run in your home
# directory, it writes to the global config. `mise set KEY` prints one value,
# and `mise set` lists every variable with its source file. Use `--global`,
# `--file`, or `-E <env>` to write elsewhere.
# See https://mise.jdx.dev/configuration.html#target-file-for-write-operations
@usage 'alias ev env-vars'
@usage 'long_help #"""
Set, show, or list environment variables in mise.toml

`mise set KEY=VALUE` writes to the lowest-precedence TOML file in the nearest
config directory (`mise.toml` rather than `mise.local.toml`), creating
`mise.toml` in the current directory if there is none. Run in your home
directory, it writes to the global config. `mise set KEY` prints one value,
and `mise set` lists every variable with its source file. Use `--global`,
`--file`, or `-E <env>` to write elsewhere.
See https://mise.jdx.dev/configuration.html#target-file-for-write-operations
"""#'
@usage 'flag "-E --env" help="Write to mise.<ENV>.toml in the current directory, or to .mise.<ENV>.toml if that exists" {
        overrides "--global" "--file"
        arg <ENV>
    }'
@usage 'flag "-g --global" help="Set the environment variable in the global config file" {
        overrides "--file" "--env"
    }'
@usage 'flag --override help="Set the environment variable in the global override file, `config.override.toml`" {
        long_help #"""
Set the environment variable in the global override file, `config.override.toml`

The override file outranks all project config. With `--env`, writes `config.<ENV>.override.toml` instead. See https://mise.jdx.dev/configuration.html#override-file
"""#
        conflicts "--global" "--file"
    }'
@usage 'flag --age-encrypt help="[experimental] Encrypt the value with age before storing" requires=ENV_VAR'
@usage 'flag --age-key-file help="[experimental] Age identity file whose public keys to encrypt to" requires=--age-encrypt {
        long_help #"""
[experimental] Age identity file whose public keys to encrypt to

Without --age-recipient, --age-ssh-recipient, or --age-key-file, mise encrypts to the identities in the `age.key_file` setting (or ~/.config/mise/age.txt if it exists) and to ~/.ssh/id_ed25519 and ~/.ssh/id_rsa when they exist.
"""#
        arg <PATH>
    }'
@usage 'flag --age-recipient help="[experimental] Age recipient (x25519 public key) for encryption" var=#true requires=--age-encrypt {
        long_help #"""
[experimental] Age recipient (x25519 public key) for encryption

Can be used multiple times. Requires --age-encrypt.
"""#
        arg <RECIPIENT>
    }'
@usage 'flag --age-ssh-recipient help="[experimental] SSH recipient (public key or path) for age encryption" var=#true requires=--age-encrypt {
        long_help #"""
[experimental] SSH recipient (public key or path) for age encryption

Can be used multiple times. Requires --age-encrypt.
"""#
        arg <PATH_OR_PUBKEY>
    }'
@usage 'flag --complete help="Render completions" hide=#true'
@usage 'flag "--file --path" help="The TOML file to update" {
        long_help #"""
The TOML file to update

Can be a file or a directory. For a directory, mise uses the config file already in it, or creates one named by MISE_DEFAULT_CONFIG_FILENAME (default `mise.toml`): https://mise.jdx.dev/configuration/settings.html#default_config_filename To move the global config file, set MISE_GLOBAL_CONFIG_FILE: https://mise.jdx.dev/configuration/settings.html#global_config_file
"""#
        arg <FILE>
    }'
@usage 'flag --no-redact help="Show raw values instead of redacting secrets"'
@usage 'flag --prompt help="Prompt for environment variable values (input is masked only with --age-encrypt)"'
@usage 'flag "--remove --rm --unset" help="Remove the environment variable from config file" var=#true hide=#true {
        long_help #"""
Remove the environment variable from config file

Can be used multiple times.
"""#
        arg <ENV_KEY>
    }'
@usage 'flag --stdin help="Read the value from stdin, for multiline input" conflicts=--prompt requires=ENV_VAR {
        long_help #"""
Read the value from stdin, for multiline input

Pass a single key without a value; the value is read from stdin until EOF.
"""#
    }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[ENV_VAR]…" help="Environment variables to set, such as NODE_ENV=production" required=#false var=#true'
@usage 'example "mise set NODE_ENV=production" help="Set NODE_ENV in mise.toml"'
@usage r#'example #"""
mise set NODE_ENV
production
"""# help="Show one variable's value"'#
@usage 'example "mise set" help="List variables, their values, and their source files"'
@usage 'example "mise set -E staging NODE_ENV=staging" help="Write the variable to mise.staging.toml"'
@usage 'example "mise set --prompt PASSWORD" help="Prompt for the value; input is visible unless you add --age-encrypt"'
@usage 'example "cat private.key | mise set --stdin MY_KEY" help="Read a multiline value from stdin"'
@usage 'example "mise set --age-encrypt --prompt API_KEY" help="Prompt with hidden input and store the value encrypted with age (experimental)"'
@usage 'complete path type=path'
@usage 'complete file type=path'
export def "mise set" [
    ...env_var: string@"nus complete",    # Environment variables to set, such as NODE_ENV=production
    --cd (-C): path@"nus complete",       # Run as if mise were started in DIR
    --env_ (-E): list<string>,            # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                  # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                         # Suppress non-error messages
    --verbose (-v): int,                  # Show extra output (use -vv for even more)
    --yes (-y),                           # Answer yes to all confirmation prompts
    --raw,                                # Connect tasks and install commands directly to the terminal
    --locked,                             # Require download URLs from the lockfile when installing
    --silent,                             # Suppress all task output and mise non-error messages
    --global (-g),                        # Set the environment variable in the global config file
    --override,                           # Set the environment variable in the global override file, `config.override.toml`
    --age-encrypt,                        # [experimental] Encrypt the value with age before storing
    --age-key-file: path@"nus complete",  # [experimental] Age identity file whose public keys to encrypt to
    --age-recipient: list<string>,        # [experimental] Age recipient (x25519 public key) for encryption
    --age-ssh-recipient: list<string>,    # [experimental] SSH recipient (public key or path) for age encryption
    --file: path@"nus complete",          # The TOML file to update
    --no-redact,                          # Show raw values instead of redacting secrets
    --prompt,                             # Prompt for environment variable values (input is masked only with --age-encrypt)
    --stdin,                              # Read the value from stdin, for multiline input
]: nothing -> string {
    ^mise set ...(nus argv [...$env_var] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --global: $global
        --override: $override
        --age-encrypt: $age_encrypt
        --age-key-file: $age_key_file
        --age-recipient: $age_recipient
        --age-ssh-recipient: $age_ssh_recipient
        --file: $file
        --no-redact: $no_redact
        --prompt: $prompt
        --stdin: $stdin
    })
}

# Manage settings
#
# With no arguments, lists the settings set in config files (same as
# `mise settings ls`). With SETTING, prints its effective value. With
# SETTING=VALUE or SETTING VALUE, writes it to the global config
# (~/.config/mise/config.toml), or to the nearest project config with
# `--local`. Every setting is described at
# https://mise.jdx.dev/configuration/settings.html
@usage 'long_help #"""
Manage settings

With no arguments, lists the settings set in config files (same as
`mise settings ls`). With SETTING, prints its effective value. With
SETTING=VALUE or SETTING VALUE, writes it to the global config
(~/.config/mise/config.toml), or to the nearest project config with
`--local`. Every setting is described at
https://mise.jdx.dev/configuration/settings.html
"""#'
@usage 'flag "-a --all" help="List all settings"'
@usage 'flag "-J --json" help="Output in JSON format"'
@usage 'flag "-l --local" help="Use only the nearest project config" global=#true {
        long_help #"""
Use only the nearest project config

Reads only its explicit settings, or writes to it instead of the global config.
"""#
    }'
@usage 'flag "-T --toml" help="Output in TOML format"'
@usage 'flag --complete help="Print all settings with descriptions for shell completions" hide=#true'
@usage 'flag --json-extended help="Output in JSON format with sources"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[SETTING]" help="Only show this setting, or the settings under this prefix such as `python`" required=#false'
@usage 'arg "[VALUE]" help="The value to set" required=#false conflicts=all'
@usage 'group output "--json" "--toml" "--json-extended"'
@usage 'example "mise settings" help="List settings set in config files"'
@usage 'example "mise settings jobs" help="Show the effective value of one setting"'
@usage 'example "mise settings jobs=4" help="Set jobs in the global config"'
@usage 'example "mise settings --local node.mirror_url https://npmmirror.com/mirrors/node/" help="Set a setting in the project config"'
@usage 'output json framing=json select=--json'
export def "mise settings" [
    setting?: string@"nus complete",  # Only show this setting, or the settings under this prefix such as `python`
    value?: string,                   # The value to set
    --cd (-C): path@"nus complete",   # Run as if mise were started in DIR
    --env_ (-E): list<string>,        # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,              # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                     # Suppress non-error messages
    --verbose (-v): int,              # Show extra output (use -vv for even more)
    --yes (-y),                       # Answer yes to all confirmation prompts
    --raw,                            # Connect tasks and install commands directly to the terminal
    --locked,                         # Require download URLs from the lockfile when installing
    --silent,                         # Suppress all task output and mise non-error messages
    --all (-a),                       # List all settings
    --local (-l),                     # Use only the nearest project config
    --toml (-T),                      # Output in TOML format
    --json-extended,                  # Output in JSON format with sources
] {
    ^mise settings --json ...(nus argv [$setting $value] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --all: $all
        --local: $local
        --toml: $toml
        --json-extended: $json_extended
    }) | from json
}

# Append a value to an array setting
#
# Adds the value to an array setting such as `disable_hints`, keeping existing
# entries. Writes ~/.config/mise/config.toml, or the nearest project config
# with `--local`.
@usage 'long_help #"""
Append a value to an array setting

Adds the value to an array setting such as `disable_hints`, keeping existing
entries. Writes ~/.config/mise/config.toml, or the nearest project config
with `--local`.
"""#'
@usage 'flag "-l --local" help="Write to the nearest project config instead of the global config" {
            long_help #"""
Write to the nearest project config instead of the global config

The nearest project config is the lowest-precedence TOML file in the nearest directory that has one, or ./mise.toml.
"""#
        }'
@usage r#'flag --override help="Write to the global override file, `config.override.toml`" conflicts=--local {
            long_help #"""
Write to the global override file, `config.override.toml`

The override file outranks all project config, so the setting wins over the same setting in a project's `mise.toml`.
"""#
        }'#
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <SETTING> help="The array setting to append to"'
@usage 'arg "[VALUE]" help="The value to append (or pass SETTING=VALUE)" required=#false'
@usage 'example "mise settings add disable_hints python_multi" help="Stop showing the python_multi hint"'
export def "mise settings add" [
    setting: string@"nus complete",  # The array setting to append to
    value?: string,                  # The value to append (or pass SETTING=VALUE)
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --local (-l),                    # Use only the nearest project config
    --override,                      # Write to the global override file, `config.override.toml`
]: nothing -> string {
    ^mise settings add ...(nus argv [$setting $value] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --local: $local
        --override: $override
    })
}

# Show the effective value of a setting
#
# Includes defaults, config files, and environment overrides. With `--local`,
# reads only the explicit settings in the nearest project config, and a
# setting that is not set there is an error. An optional setting with no
# default that is not set anywhere, such as `python.compile`, is also reported
# as not set and exits with an error. To inspect one file, use
# `mise config get settings.KEY --file path/to/mise.toml`.
@usage 'long_help #"""
Show the effective value of a setting

Includes defaults, config files, and environment overrides. With `--local`,
reads only the explicit settings in the nearest project config, and a
setting that is not set there is an error. An optional setting with no
default that is not set anywhere, such as `python.compile`, is also reported
as not set and exits with an error. To inspect one file, use
`mise config get settings.KEY --file path/to/mise.toml`.
"""#'
@usage 'flag "-l --local" help="Read only the explicit settings in the nearest project config"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <SETTING> help="The setting to show"'
@usage 'example "mise settings get jobs" help="Show the effective number of parallel jobs"'
@usage 'example "mise settings get --local experimental" help="Show the value set in the project config"'
export def "mise settings get" [
    setting: string@"nus complete",  # The setting to show
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --local (-l),                    # Use only the nearest project config
]: nothing -> string {
    ^mise settings get ...(nus argv [$setting] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --local: $local
    })
}

# List configured settings and their sources
#
# By default, lists the settings set in loaded TOML config files. `--all` also
# includes the effective value of every other setting. `--local` lists only the
# nearest project config, and `--json-extended` adds source information to
# JSON output. Use `mise settings get SETTING` for one effective value.
@usage 'alias list'
@usage 'long_help #"""
List configured settings and their sources

By default, lists the settings set in loaded TOML config files. `--all` also
includes the effective value of every other setting. `--local` lists only the
nearest project config, and `--json-extended` adds source information to
JSON output. Use `mise settings get SETTING` for one effective value.
"""#'
@usage 'flag "-a --all" help="List all settings"'
@usage 'flag "-J --json" help="Output in JSON format"'
@usage 'flag "-l --local" help="Use only the nearest project config" global=#true {
            long_help #"""
Use only the nearest project config

Reads only its explicit settings, or writes to it instead of the global config.
"""#
        }'
@usage 'flag "-T --toml" help="Output in TOML format"'
@usage 'flag --complete help="Print all settings with descriptions for shell completions" hide=#true'
@usage 'flag --json-extended help="Output in JSON format with sources"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[SETTING]" help="Only show this setting, or the settings under this prefix such as `python`" required=#false'
@usage 'group output "--json" "--toml" "--json-extended"'
@usage 'example "mise settings ls" help="List settings set in config files"'
@usage 'example "mise settings ls --all" help="Include settings left at their defaults"'
@usage 'example "mise settings ls python --json-extended" help="Show the python settings as JSON with their sources"'
@usage 'output json framing=json select=--json'
export def "mise settings ls" [
    setting?: string@"nus complete",  # Only show this setting, or the settings under this prefix such as `python`
    --cd (-C): path@"nus complete",   # Run as if mise were started in DIR
    --env_ (-E): list<string>,        # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,              # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                     # Suppress non-error messages
    --verbose (-v): int,              # Show extra output (use -vv for even more)
    --yes (-y),                       # Answer yes to all confirmation prompts
    --raw,                            # Connect tasks and install commands directly to the terminal
    --locked,                         # Require download URLs from the lockfile when installing
    --silent,                         # Suppress all task output and mise non-error messages
    --all (-a),                       # List all settings
    --local (-l),                     # Use only the nearest project config
    --toml (-T),                      # Output in TOML format
    --json-extended,                  # Output in JSON format with sources
] {
    ^mise settings ls --json ...(nus argv [$setting] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --all: $all
        --local: $local
        --toml: $toml
        --json-extended: $json_extended
    }) | from json
}

# Set a setting
#
# Writes ~/.config/mise/config.toml, or the nearest project config with
# `--local`. Settings that mise reads before loading config files cannot be set
# here: set `global_config_file` and similar through their environment
# variables, and `ceiling_paths` and similar in a `miserc.toml` file or their
# environment variables. `--local` refuses settings that only the global config
# can set, such as `yes`.
# See https://mise.jdx.dev/configuration/settings.html
@usage 'alias create'
@usage 'long_help #"""
Set a setting

Writes ~/.config/mise/config.toml, or the nearest project config with
`--local`. Settings that mise reads before loading config files cannot be set
here: set `global_config_file` and similar through their environment
variables, and `ceiling_paths` and similar in a `miserc.toml` file or their
environment variables. `--local` refuses settings that only the global config
can set, such as `yes`.
See https://mise.jdx.dev/configuration/settings.html
"""#'
@usage 'flag "-l --local" help="Write to the nearest project config instead of the global config" {
            long_help #"""
Write to the nearest project config instead of the global config

The nearest project config is the lowest-precedence TOML file in the nearest directory that has one, or ./mise.toml.
"""#
        }'
@usage r#'flag --override help="Write to the global override file, `config.override.toml`" conflicts=--local {
            long_help #"""
Write to the global override file, `config.override.toml`

The override file outranks all project config, so the setting wins over the same setting in a project's `mise.toml`.
"""#
        }'#
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <SETTING> help="The setting to set"'
@usage 'arg "[VALUE]" help="The value to set (or pass SETTING=VALUE)" required=#false'
@usage 'example "mise settings set jobs 4" help="Run up to 4 jobs in parallel"'
@usage 'example "mise settings set --local experimental=true" help="Enable experimental features in the project config"'
export def "mise settings set" [
    setting: string@"nus complete",  # The setting to set
    value?: string,                  # The value to set (or pass SETTING=VALUE)
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --local (-l),                    # Use only the nearest project config
    --override,                      # Write to the global override file, `config.override.toml`
]: nothing -> string {
    ^mise settings set ...(nus argv [$setting $value] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --local: $local
        --override: $override
    })
}

# Remove a setting from the global or project config
#
# Edits ~/.config/mise/config.toml, or the nearest project config with
# `--local`. The setting then falls back to its default or to a value from
# another config file.
@usage 'alias rm remove delete del'
@usage 'long_help #"""
Remove a setting from the global or project config

Edits ~/.config/mise/config.toml, or the nearest project config with
`--local`. The setting then falls back to its default or to a value from
another config file.
"""#'
@usage 'flag "-l --local" help="Write to the nearest project config instead of the global config" {
            long_help #"""
Write to the nearest project config instead of the global config

The nearest project config is the lowest-precedence TOML file in the nearest directory that has one, or ./mise.toml.
"""#
        }'
@usage r#'flag --override help="Write to the global override file, `config.override.toml`" conflicts=--local {
            long_help #"""
Write to the global override file, `config.override.toml`

The override file outranks all project config, so the setting wins over the same setting in a project's `mise.toml`.
"""#
        }'#
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <KEY> help="The setting to remove"'
@usage 'example "mise settings unset jobs" help="Remove jobs from the global config"'
export def "mise settings unset" [
    key: string,                     # The setting to remove
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --local (-l),                    # Use only the nearest project config
    --override,                      # Write to the global override file, `config.override.toml`
]: nothing -> string {
    ^mise settings unset ...(nus argv [$key] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --local: $local
        --override: $override
    })
}

# Set a tool version for the current shell session
#
# Installs the version if needed, then sets `MISE_<TOOL>_VERSION`, such as
# `MISE_NODE_VERSION`, to the resolved version in the current shell. That
# overrides config files until you close the shell or run
# `mise shell --unset <TOOL>`. Requires `mise activate`: the shell function it
# defines applies the variable that this command prints.
@usage 'alias sh'
@usage 'long_help #"""
Set a tool version for the current shell session

Installs the version if needed, then sets `MISE_<TOOL>_VERSION`, such as
`MISE_NODE_VERSION`, to the resolved version in the current shell. That
overrides config files until you close the shell or run
`mise shell --unset <TOOL>`. Requires `mise activate`: the shell function it
defines applies the variable that this command prints.
"""#'
@usage 'flag "-j --jobs" help="Number of jobs to run in parallel (default: the `jobs` setting)" env=MISE_JOBS {
        arg <JOBS>
    }'
@usage 'flag "-u --unset" help="Remove a version set earlier with `mise shell`"'
@usage r#'flag --raw help="Connect the install commands' stdin, stdout, and stderr to the terminal" overrides=--jobs {
        long_help #"""
Connect the install commands' stdin, stdout, and stderr to the terminal

Implies `--jobs=1`.
"""#
    }'#
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <TOOL@VERSION>… help="Tools to set, such as node@20" var=#true'
@usage 'example #"""
mise shell node@20
node -v
v20.19.5
"""# help="Use node 20 in this shell"'
@usage 'example "mise shell --unset node" help="Go back to the version the config requests"'
export def "mise shell" [
    ...tool_version: string@"nus complete",  # Tools to set, such as node@20
    --cd (-C): path@"nus complete",          # Run as if mise were started in DIR
    --env_ (-E): list<string>,               # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                     # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                            # Suppress non-error messages
    --verbose (-v): int,                     # Show extra output (use -vv for even more)
    --yes (-y),                              # Answer yes to all confirmation prompts
    --raw,                                   # Connect tasks and install commands directly to the terminal
    --locked,                                # Require download URLs from the lockfile when installing
    --silent,                                # Suppress all task output and mise non-error messages
    --unset (-u),                            # Remove a version set earlier with `mise shell`
]: nothing -> string {
    ^mise shell ...(nus argv [...$tool_version] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --unset: $unset
    })
}

# Open an SSH session, optionally borrowing read-only GitHub access
#
# Without relay flags, runs OpenSSH to DESTINATION and passes -i, -p, and -o
# through. With `--github-relay-read-only`, Git and mise on the remote host can
# clone, fetch, and download releases from the GitHub repositories you allow,
# using this machine's GitHub credentials, until the session ends. The token
# is not copied to the host, and pushes and API writes are refused.
#
# `--github-relay-read-only` needs exactly one of `--github-relay-repo`,
# repeated for each repository, or `--github-relay-all-repos`. A compromised
# host can read what you allow while the session lasts.
# See https://mise.jdx.dev/bootstrap/github-relay.html
@usage r#'long_help #"""
Open an SSH session, optionally borrowing read-only GitHub access

Without relay flags, runs OpenSSH to DESTINATION and passes -i, -p, and -o
through. With `--github-relay-read-only`, Git and mise on the remote host can
clone, fetch, and download releases from the GitHub repositories you allow,
using this machine's GitHub credentials, until the session ends. The token
is not copied to the host, and pushes and API writes are refused.

`--github-relay-read-only` needs exactly one of `--github-relay-repo`,
repeated for each repository, or `--github-relay-all-repos`. A compromised
host can read what you allow while the session lasts.
See https://mise.jdx.dev/bootstrap/github-relay.html
"""#'#
@usage 'flag "-i --identity-file" help="SSH identity file" {
        arg <IDENTITY_FILE>
    }'
@usage 'flag "-p --port" help="SSH port" {
        arg <PORT>
    }'
@usage 'flag "-o --ssh-option" help="OpenSSH option; repeat for multiple options" var=#true {
        arg <SSH_OPTION>
    }'
@usage 'flag --github-relay-read-only help="Borrow read-only GitHub access for this session only"'
@usage 'flag --github-relay-repo help="GitHub repository the host may read; repeat for more repositories" var=#true {
        arg "<OWNER/REPO>"
    }'
@usage 'flag --github-relay-all-repos help="Allow reads of every repository your local GitHub credentials can access"'
@usage 'flag --github-relay-log-requests help="Log sanitized relay requests on local stderr" conflicts=--github-relay-no-log-requests'
@usage 'flag --github-relay-no-log-requests help="Turn off request logging even if the github_relay.log_requests setting is on"'
@usage 'flag --github-relay-log-format help="Relay log and summary format: text or jsonl (default: the github_relay.log_format setting)" {
        arg <FORMAT>
    }'
@usage 'flag --github-relay-max-duration help="End borrowed access after a duration such as 1h; 0s lasts the whole session" {
        arg <DURATION>
    }'
@usage 'flag --relay-session help="Internal session adapter" hide=#true {
        arg <RELAY_SESSION>
    }'
@usage 'flag --repository-bundle hide=#true {
        arg <REPOSITORY_BUNDLE>
    }'
@usage 'flag --repository-origin hide=#true {
        arg <REPOSITORY_ORIGIN>
    }'
@usage 'flag --repository-revision hide=#true {
        arg <REPOSITORY_REVISION>
    }'
@usage 'flag --repository-update hide=#true'
@usage 'flag --repository-require-branch help="The bundled branch was requested with `?ref=`" hide=#true'
@usage 'flag --repository-yes hide=#true'
@usage r#'flag --repository-dry-run help="Preview the transferred repository's installation without writing it" hide=#true'#
@usage 'flag --repository-preview-directory hide=#true {
        arg <REPOSITORY_PREVIEW_DIRECTORY>
    }'
@usage 'flag --global-config-directory hide=#true'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[DESTINATION]" help="OpenSSH destination or SSH config alias (required)" required=#false'
@usage 'arg "[COMMAND]…" help="Command to execute after --; omit for an interactive shell" required=#false double_dash=automatic var=#true'
@usage 'example "mise ssh devbox --github-relay-read-only --github-relay-repo you/setup -- git clone https://github.com/you/setup.git" help="Let devbox clone one private repository"'
@usage 'example "mise ssh devbox --github-relay-read-only --github-relay-all-repos" help="Open a shell that can read every repository your credentials can read"'
@usage 'example "mise ssh devbox -i ~/.ssh/devbox -p 2222 -o ServerAliveInterval=30 -- uname -a" help="Run a command over plain SSH with an identity file, port, and option"'
export def "mise ssh" [
    destination?: string,                 # OpenSSH destination or SSH config alias (required)
    ...command: string,                   # Command to execute after --; omit for an interactive shell
    --cd (-C): path@"nus complete",       # Run as if mise were started in DIR
    --env_ (-E): list<string>,            # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                  # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                         # Suppress non-error messages
    --verbose (-v): int,                  # Show extra output (use -vv for even more)
    --yes (-y),                           # Answer yes to all confirmation prompts
    --raw,                                # Connect tasks and install commands directly to the terminal
    --locked,                             # Require download URLs from the lockfile when installing
    --silent,                             # Suppress all task output and mise non-error messages
    --identity-file (-i): string,         # SSH identity file
    --port (-p): string,                  # SSH port
    --ssh-option (-o): list<string>,      # OpenSSH option; repeat for multiple options
    --github-relay-read-only,             # Borrow read-only GitHub access for this session only
    --github-relay-repo: list<string>,    # GitHub repository the host may read; repeat for more repositories
    --github-relay-all-repos,             # Allow reads of every repository your local GitHub credentials can access
    --github-relay-log-requests,          # Log sanitized relay requests on local stderr
    --github-relay-no-log-requests,       # Turn off request logging even if the github_relay.log_requests setting is on
    --github-relay-log-format: string,    # Relay log and summary format: text or jsonl (default: the github_relay.log_format setting)
    --github-relay-max-duration: string,  # End borrowed access after a duration such as 1h; 0s lasts the whole session
]: nothing -> string {
    ^mise ssh ...(nus argv [$destination ...$command] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --identity-file: $identity_file
        --port: $port
        --ssh-option: $ssh_option
        --github-relay-read-only: $github_relay_read_only
        --github-relay-repo: $github_relay_repo
        --github-relay-all-repos: $github_relay_all_repos
        --github-relay-log-requests: $github_relay_log_requests
        --github-relay-no-log-requests: $github_relay_no_log_requests
        --github-relay-log-format: $github_relay_log_format
        --github-relay-max-duration: $github_relay_max_duration
    })
}

# Manage shell aliases
#
# Shell aliases are defined under `[shell_alias]` in mise.toml. In a shell
# where mise is activated, mise sets them when you enter the directory and
# removes them when you leave. With no subcommand, lists them (same as
# `mise shell-alias ls`). See https://mise.jdx.dev/shell-aliases.html
@usage 'long_help #"""
Manage shell aliases

Shell aliases are defined under `[shell_alias]` in mise.toml. In a shell
where mise is activated, mise sets them when you enter the directory and
removes them when you leave. With no subcommand, lists them (same as
`mise shell-alias ls`). See https://mise.jdx.dev/shell-aliases.html
"""#'
@usage 'flag --no-header help="Do not print the table header"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise shell-alias" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --no-header,                     # Do not print the table header
]: nothing -> string {
    ^mise shell-alias ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --no-header: $no_header
    })
}

# Show the command for a shell alias
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <shell_alias> help="The alias to show"'
@usage 'example #"""
mise shell-alias get ll
ls -la
"""# help="Print the command that ll runs"'
export def "mise shell-alias get" [
    shell_alias: string,             # The alias to show
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise shell-alias get ...(nus argv [$shell_alias] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# List shell aliases
#
# Lists the shell aliases configured for the current directory: the
# `[shell_alias]` entries of every config file mise loads here.
@usage 'alias list'
@usage 'long_help #"""
List shell aliases

Lists the shell aliases configured for the current directory: the
`[shell_alias]` entries of every config file mise loads here.
"""#'
@usage 'flag --no-header help="Do not print the table header"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example #"""
mise shell-alias ls
alias    command
ll       ls -la
gs       git status
"""# help="List the aliases set in this directory"'
export def "mise shell-alias ls" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --no-header,                     # Do not print the table header
]: nothing -> string {
    ^mise shell-alias ls ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --no-header: $no_header
    })
}

# Set a shell alias in the global config
#
# Writes the global config (~/.config/mise/config.toml by default). To share
# an alias with a project, add it under `[shell_alias]` in the project's
# mise.toml.
@usage 'alias add create'
@usage r#'long_help #"""
Set a shell alias in the global config

Writes the global config (~/.config/mise/config.toml by default). To share
an alias with a project, add it under `[shell_alias]` in the project's
mise.toml.
"""#'#
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <shell_alias> help="The alias name"'
@usage 'arg "[COMMAND]" help="The command to run (or pass ALIAS=COMMAND)" required=#false'
@usage 'example "mise shell-alias set ll \"ls -la\"" help="Define ll in every directory"'
@usage 'example "mise shell-alias set gs=\"git status\"" help="Use the ALIAS=COMMAND form"'
export def "mise shell-alias set" [
    shell_alias: string,             # The alias name
    command?: string,                # The command to run (or pass ALIAS=COMMAND)
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise shell-alias set ...(nus argv [$shell_alias $command] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Remove a shell alias from the global config
#
# Edits the global config (~/.config/mise/config.toml by default). An alias
# defined in a project's mise.toml has to be removed there.
@usage 'alias rm remove delete del'
@usage r#'long_help #"""
Remove a shell alias from the global config

Edits the global config (~/.config/mise/config.toml by default). An alias
defined in a project's mise.toml has to be removed there.
"""#'#
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <shell_alias> help="The alias to remove"'
@usage 'example "mise shell-alias unset ll" help="Remove ll from the global config"'
export def "mise shell-alias unset" [
    shell_alias: string,             # The alias to remove
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise shell-alias unset ...(nus argv [$shell_alias] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# List and link the agent skills that active tools ship
#
# A tool installed with the `packslip:` backend may declare an agent skill: a
# directory holding `SKILL.md` and whatever it references, in the Agent Skills
# format. mise knows which version of each tool is active here, so it can hand
# an agent the skill for exactly that version.
#
# With no subcommand, lists the skills (same as `mise skills ls`).
# See https://mise.jdx.dev/dev-tools/packslip-resources.html#skills
@usage 'alias skill'
@usage 'long_help #"""
List and link the agent skills that active tools ship

A tool installed with the `packslip:` backend may declare an agent skill: a
directory holding `SKILL.md` and whatever it references, in the Agent Skills
format. mise knows which version of each tool is active here, so it can hand
an agent the skill for exactly that version.

With no subcommand, lists the skills (same as `mise skills ls`).
See https://mise.jdx.dev/dev-tools/packslip-resources.html#skills
"""#'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise skills" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise skills ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# List the skills the active tools declare
#
# Each line is a skill of a tool that is installed and active in the current
# directory, with the version it belongs to and the directory holding its
# `SKILL.md`.
@usage 'alias list'
@usage 'long_help #"""
List the skills the active tools declare

Each line is a skill of a tool that is installed and active in the current
directory, with the version it belongs to and the directory holding its
`SKILL.md`.
"""#'
@usage 'flag "-J --json" help="Output in JSON format"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example #"""
mise skills ls
Skill         Tool                        Version  Path
hk-configure  packslip:github.com/jdx/hk  2.5.0    ~/.local/share/mise/installs/packslip-github-com-jdx-hk/2.5.0/skills/hk-configure
hk-debug      packslip:github.com/jdx/hk  2.5.0    ~/.local/share/mise/installs/packslip-github-com-jdx-hk/2.5.0/skills/hk-debug
"""# help="List the skills of the active tools"'
@usage 'output "json" framing="json" select="--json" {
    schema "{\n  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",\n  \"title\": \"mise skills ls --json\",\n  \"type\": \"array\",\n  \"items\": {\n    \"type\": \"object\",\n    \"properties\": {\n      \"name\": {\n        \"type\": \"string\"\n      },\n      \"tool\": {\n        \"type\": \"string\"\n      },\n      \"version\": {\n        \"type\": \"string\"\n      },\n      \"path\": {\n        \"type\": \"string\"\n      }\n    },\n    \"required\": [\n      \"name\",\n      \"tool\",\n      \"version\",\n      \"path\"\n    ],\n    \"additionalProperties\": false\n  }\n}\n"
}'
export def "mise skills ls" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> table<name: string, tool: string, version: string, path: string> {
    let text = ^mise skills ls --json ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
    nus decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"title\":\"mise skills ls --json\",\"type\":\"array\",\"items\":{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"},\"tool\":{\"type\":\"string\"},\"version\":{\"type\":\"string\"},\"path\":{\"type\":\"string\"}},\"required\":[\"name\",\"tool\",\"version\",\"path\"],\"additionalProperties\":false}}" { from json }
}

# Link the active tools' skills where an agent looks for them
#
# Writes one symlink per skill into DIR, named after the skill and pointing
# at the directory of the version that is active here. DIR defaults to the
# `skills.dir` setting, `.claude/skills`, under the project root: the
# directory of the nearest mise config. Run it again after `mise use` changes
# a version and the links follow, or set `skills.auto_sync` to have mise do
# that after every install and `mise use`.
#
# mise replaces only the links it made, which point into its installs
# directory, and removes them only with --prune or the `skills.prune` setting.
# A real directory or a link of your own at a skill's name is left alone and
# reported.
@usage r#'long_help #"""
Link the active tools' skills where an agent looks for them

Writes one symlink per skill into DIR, named after the skill and pointing
at the directory of the version that is active here. DIR defaults to the
`skills.dir` setting, `.claude/skills`, under the project root: the
directory of the nearest mise config. Run it again after `mise use` changes
a version and the links follow, or set `skills.auto_sync` to have mise do
that after every install and `mise use`.

mise replaces only the links it made, which point into its installs
directory, and removes them only with --prune or the `skills.prune` setting.
A real directory or a link of your own at a skill's name is left alone and
reported.
"""#'#
@usage 'flag --dir help="The directory to link skills into" {
            arg <DIR>
        }'
@usage r#'flag "-g --global" help="Link into the skills.dir directory under your home directory instead of the project's" conflicts=--dir {
            long_help #"""
Link into the skills.dir directory under your home directory instead of the project's

With the default skills.dir, that is ~/.claude/skills.
"""#
        }'#
@usage 'flag --prune help="Remove links mise made for skills that are no longer active"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage r#'example "mise skills sync" help="Link skills into the project's skills.dir (default .claude/skills)"'#
@usage 'example "mise skills sync --dir .agents/skills --prune" help="Link into .agents/skills and remove links for skills that are no longer active"'
@usage 'complete dir type=dir'
export def "mise skills sync" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --dir: path@"nus complete",      # The directory to link skills into
    --global (-g),                   # Link into the skills.dir directory under your home directory instead of the project's
    --prune,                         # Remove links mise made for skills that are no longer active
]: nothing -> string {
    ^mise skills sync ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --dir: $dir
        --global: $global
        --prune: $prune
    })
}

# Show the companies sponsoring mise and the jdx.dev open source tools
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise sponsors" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise sponsors ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Use tool versions installed by other version managers
#
# Links node versions from nvm, nodenv, or Homebrew, python versions from pyenv
# or uv, and ruby versions from Homebrew into mise, so `mise use` can select
# them without reinstalling.
@usage 'long_help #"""
Use tool versions installed by other version managers

Links node versions from nvm, nodenv, or Homebrew, python versions from pyenv
or uv, and ruby versions from Homebrew into mise, so `mise use` can select
them without reinstalling.
"""#'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise sync" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise sync ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Symlink node versions installed by nvm, nodenv, or Homebrew into mise
#
# Use this to make versions installed by another version manager available to
# mise. It does not overwrite managed installs, runtime aliases, or links from
# other providers. Pass one or more of --brew, --nodenv, and --nvm.
@usage 'long_help #"""
Symlink node versions installed by nvm, nodenv, or Homebrew into mise

Use this to make versions installed by another version manager available to
mise. It does not overwrite managed installs, runtime aliases, or links from
other providers. Pass one or more of --brew, --nodenv, and --nvm.
"""#'
@usage 'flag --brew help="Get tool versions from Homebrew"'
@usage 'flag --nodenv help="Get tool versions from nodenv"'
@usage 'flag --nvm help="Get tool versions from nvm"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'group sync-node-type "--brew" "--nodenv" "--nvm" required=#true multiple=#true'
@usage 'example #"""
brew install node@24
mise sync node --brew
mise use -g node@24
"""# help="Use the node that Homebrew installed"'
export def "mise sync node" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --brew,                          # Get tool versions from Homebrew
    --nodenv,                        # Get tool versions from nodenv
    --nvm,                           # Get tool versions from nvm
]: nothing -> string {
    ^mise sync node ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --brew: $brew
        --nodenv: $nodenv
        --nvm: $nvm
    })
}

# Symlink python versions installed by pyenv or uv into mise
#
# Use this to make versions installed by another version manager available to
# mise. It does not overwrite managed installs, runtime aliases, or links from
# other providers. With --uv, it also links mise's python versions into uv.
# Pass --pyenv, --uv, or both; with neither, nothing is linked.
@usage r#'long_help #"""
Symlink python versions installed by pyenv or uv into mise

Use this to make versions installed by another version manager available to
mise. It does not overwrite managed installs, runtime aliases, or links from
other providers. With --uv, it also links mise's python versions into uv.
Pass --pyenv, --uv, or both; with neither, nothing is linked.
"""#'#
@usage 'flag --pyenv help="Get tool versions from pyenv"'
@usage r#'flag --uv help="Link uv's python versions into mise and mise's python versions into uv"'#
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example #"""
pyenv install 3.13.0
mise sync python --pyenv
mise use -g python@3.13.0
"""# help="Use a python that pyenv installed"'
@usage 'example #"""
uv python install 3.13.0
mise install python@3.12.0
mise sync python --uv
mise exec python@3.13.0 -- python -V
uv run -p 3.12.0 -- python -V
"""# help="Share python versions with uv in both directions"'
export def "mise sync python" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --pyenv,                         # Get tool versions from pyenv
    --uv,                            # Link uv's python versions into mise and mise's python versions into uv
]: nothing -> string {
    ^mise sync python ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --pyenv: $pyenv
        --uv: $uv
    })
}

# Symlink ruby versions installed by Homebrew into mise
#
# Use this to make versions installed by another version manager available to
# mise. It does not overwrite managed installs, runtime aliases, or links from
# other providers. Homebrew is the only source, so --brew is required. mise
# links each ruby@X.Y directory under Homebrew's opt directory, not opt/ruby.
@usage r#'long_help #"""
Symlink ruby versions installed by Homebrew into mise

Use this to make versions installed by another version manager available to
mise. It does not overwrite managed installs, runtime aliases, or links from
other providers. Homebrew is the only source, so --brew is required. mise
links each ruby@X.Y directory under Homebrew's opt directory, not opt/ruby.
"""#'#
@usage 'flag --brew help="Get tool versions from Homebrew" required=#true'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example #"""
brew install ruby@3.4
mise sync ruby --brew
mise ls ruby --installed
"""# help="Link the Homebrew ruby@3.4, then list it with the other installed versions"'
export def "mise sync ruby" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --brew,                          # Get tool versions from Homebrew
]: nothing -> string {
    ^mise sync ruby ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --brew: $brew
    })
}

# Manage tasks
#
# With no subcommand, lists tasks like `mise tasks ls` and accepts the same flags. With a task name, shows that task like `mise tasks info`. To run a task, use `mise run`.
@usage 'alias t task'
@usage 'long_help #"""
Manage tasks

With no subcommand, lists tasks like `mise tasks ls` and accepts the same flags. With a task name, shows that task like `mise tasks info`. To run a task, use `mise run`.
"""#'
@usage 'flag "-g --global" help="Only show global tasks" overrides=--local'
@usage 'flag "-J --json" help="Output in JSON format"'
@usage 'flag "-l --local" help="Only show non-global tasks" overrides=--global'
@usage 'flag "-x --extended" help="Show all columns"'
@usage r#'flag "-a --all" help="Include tasks from every project in the monorepo, not only the current directory's hierarchy"'#
@usage 'flag --complete help="Display tasks for usage completion" hide=#true'
@usage 'flag --hidden help="Show hidden tasks"'
@usage 'flag --name-only help="Print only task names, one per line (for fzf and similar tools)" {
        conflicts "--json" "--extended" "--usage"
    }'
@usage 'flag --no-header help="Do not print the table header" {
        alias "--no-headers" hide=#true
    }'
@usage 'flag --sort help="Column to sort by (default: name)" {
        arg <COLUMN> {
            choices {
                choice name
                choice alias
                choice description
                choice source
            }
        }
    }'
@usage 'flag --sort-order help="Sort direction (default: asc)" {
        arg <SORT_ORDER> {
            choices {
                choice asc
                choice desc
            }
        }
    }'
@usage 'flag --usage hide=#true'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[TASK]" help="Task to show, as `mise tasks info` does" required=#false'
@usage 'example "mise tasks" help="List tasks"'
@usage 'example "mise tasks build" help="Show the build task"'
@usage 'example "mise tasks --hidden --sort source" help="Include hidden tasks, sorted by source"'
@usage 'output "json" framing="json" select="--json" {
    schema "{\n  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",\n  \"title\": \"mise tasks [ls] --json\",\n  \"$defs\": {\n    \"dependency\": {\n      \"oneOf\": [\n        {\n          \"type\": \"string\"\n        },\n        {\n          \"type\": \"array\",\n          \"items\": {\n            \"type\": \"string\"\n          },\n          \"minItems\": 1\n        },\n        {\n          \"type\": \"object\",\n          \"properties\": {\n            \"task\": {\n              \"type\": \"string\"\n            },\n            \"args\": {\n              \"type\": \"array\",\n              \"items\": {\n                \"type\": \"string\"\n              },\n              \"minItems\": 1\n            },\n            \"env\": {\n              \"type\": \"object\",\n              \"additionalProperties\": {\n                \"type\": \"string\"\n              },\n              \"minProperties\": 1\n            },\n            \"optional\": {\n              \"const\": true\n            }\n          },\n          \"required\": [\n            \"task\"\n          ],\n          \"additionalProperties\": false\n        }\n      ]\n    },\n    \"run\": {\n      \"oneOf\": [\n        {\n          \"type\": \"string\"\n        },\n        {\n          \"type\": \"object\",\n          \"properties\": {\n            \"task\": {\n              \"type\": \"string\"\n            },\n            \"args\": {\n              \"type\": \"array\",\n              \"items\": {\n                \"type\": \"string\"\n              },\n              \"minItems\": 1\n            },\n            \"env\": {\n              \"type\": \"object\",\n              \"additionalProperties\": {\n                \"type\": \"string\"\n              },\n              \"minProperties\": 1\n            }\n          },\n          \"required\": [\n            \"task\"\n          ],\n          \"additionalProperties\": false\n        },\n        {\n          \"type\": \"object\",\n          \"properties\": {\n            \"tasks\": {\n              \"type\": \"array\",\n              \"items\": {\n                \"type\": \"string\"\n              }\n            }\n          },\n          \"required\": [\n            \"tasks\"\n          ],\n          \"additionalProperties\": false\n        }\n      ]\n    }\n  },\n  \"type\": \"array\",\n  \"items\": {\n    \"type\": \"object\",\n    \"properties\": {\n      \"name\": {\n        \"type\": \"string\"\n      },\n      \"aliases\": {\n        \"type\": \"array\",\n        \"items\": {\n          \"type\": \"string\"\n        }\n      },\n      \"description\": {\n        \"type\": \"string\"\n      },\n      \"source\": {\n        \"type\": \"string\"\n      },\n      \"config_sources\": {\n        \"type\": \"array\",\n        \"items\": {\n          \"type\": \"string\"\n        }\n      },\n      \"depends\": {\n        \"type\": \"array\",\n        \"items\": {\n          \"$ref\": \"#/$defs/dependency\"\n        }\n      },\n      \"daemons\": {\n        \"oneOf\": [\n          {\n            \"type\": \"boolean\"\n          },\n          {\n            \"type\": \"string\"\n          },\n          {\n            \"type\": \"array\",\n            \"items\": {\n              \"type\": \"string\"\n            }\n          },\n          {\n            \"type\": \"null\"\n          }\n        ]\n      },\n      \"secrets\": {\n        \"type\": \"array\",\n        \"items\": {\n          \"type\": \"string\"\n        }\n      },\n      \"depends_post\": {\n        \"type\": \"array\",\n        \"items\": {\n          \"$ref\": \"#/$defs/dependency\"\n        }\n      },\n      \"wait_for\": {\n        \"type\": \"array\",\n        \"items\": {\n          \"$ref\": \"#/$defs/dependency\"\n        }\n      },\n      \"env\": {\n        \"type\": \"array\",\n        \"items\": {\n          \"type\": \"string\"\n        }\n      },\n      \"dir\": {\n        \"type\": [\n          \"string\",\n          \"null\"\n        ]\n      },\n      \"hide\": {\n        \"type\": \"boolean\"\n      },\n      \"global\": {\n        \"type\": \"boolean\"\n      },\n      \"raw\": {\n        \"type\": \"boolean\"\n      },\n      \"interactive\": {\n        \"type\": \"boolean\"\n      },\n      \"sources\": {\n        \"type\": \"array\",\n        \"items\": {\n          \"type\": \"string\"\n        }\n      },\n      \"outputs\": {\n        \"oneOf\": [\n          {\n            \"type\": \"array\",\n            \"items\": {\n              \"type\": \"string\"\n            }\n          },\n          {\n            \"type\": \"object\",\n            \"properties\": {\n              \"auto\": {\n                \"const\": true\n              }\n            },\n            \"required\": [\n              \"auto\"\n            ],\n            \"additionalProperties\": false\n          }\n        ]\n      },\n      \"shell\": {\n        \"type\": [\n          \"string\",\n          \"null\"\n        ]\n      },\n      \"quiet\": {\n        \"type\": \"boolean\"\n      },\n      \"silent\": {\n        \"oneOf\": [\n          {\n            \"type\": \"boolean\"\n          },\n          {\n            \"enum\": [\n              \"stdout\",\n              \"stderr\"\n            ]\n          }\n        ]\n      },\n      \"tools\": {\n        \"type\": \"object\",\n        \"additionalProperties\": {\n          \"oneOf\": [\n            {\n              \"type\": \"string\"\n            },\n            {\n              \"type\": \"object\",\n              \"properties\": {\n                \"version\": {\n                  \"type\": \"string\"\n                }\n              },\n              \"required\": [\n                \"version\"\n              ],\n              \"additionalProperties\": true\n            }\n          ]\n        }\n      },\n      \"usage\": {\n        \"type\": \"string\"\n      },\n      \"timeout\": {\n        \"type\": [\n          \"string\",\n          \"null\"\n        ]\n      },\n      \"run\": {\n        \"type\": \"array\",\n        \"items\": {\n          \"$ref\": \"#/$defs/run\"\n        }\n      },\n      \"args\": {\n        \"type\": \"array\",\n        \"items\": {\n          \"type\": \"string\"\n        }\n      },\n      \"file\": {\n        \"type\": [\n          \"string\",\n          \"null\"\n        ]\n      }\n    },\n    \"required\": [\n      \"name\",\n      \"aliases\",\n      \"description\",\n      \"source\",\n      \"config_sources\",\n      \"depends\",\n      \"daemons\",\n      \"secrets\",\n      \"depends_post\",\n      \"wait_for\",\n      \"env\",\n      \"dir\",\n      \"hide\",\n      \"global\",\n      \"raw\",\n      \"interactive\",\n      \"sources\",\n      \"outputs\",\n      \"shell\",\n      \"quiet\",\n      \"silent\",\n      \"tools\",\n      \"usage\",\n      \"timeout\",\n      \"run\",\n      \"args\",\n      \"file\"\n    ],\n    \"additionalProperties\": false\n  }\n}\n"
}'
export def "mise tasks" [
    task?: string@"nus complete",                    # Task to show, as `mise tasks info` does
    --cd (-C): path@"nus complete",                  # Run as if mise were started in DIR
    --env_ (-E): list<string>,                       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                                    # Suppress non-error messages
    --verbose (-v): int,                             # Show extra output (use -vv for even more)
    --yes (-y),                                      # Answer yes to all confirmation prompts
    --raw,                                           # Connect tasks and install commands directly to the terminal
    --locked,                                        # Require download URLs from the lockfile when installing
    --silent,                                        # Suppress all task output and mise non-error messages
    --global (-g),                                   # Only show global tasks
    --local (-l),                                    # Only show non-global tasks
    --extended (-x),                                 # Show all columns
    --all (-a),                                      # Include tasks from every project in the monorepo, not only the current directory's hierarchy
    --hidden,                                        # Show hidden tasks
    --name-only,                                     # Print only task names, one per line (for fzf and similar tools)
    --no-header,                                     # Do not print the table header
    --sort: string@[name alias description source],  # Column to sort by (default: name)
    --sort-order: string@[asc desc],                 # Sort direction (default: asc)
]: nothing -> table<name: string, aliases: list<string>, description: string, source: string, config_sources: list<string>, depends: list<oneof<string, list<string>, record<task: string>>>, daemons: oneof<bool, string, list<string>, nothing>, secrets: list<string>, depends_post: list<oneof<string, list<string>, record<task: string>>>, wait_for: list<oneof<string, list<string>, record<task: string>>>, env: list<string>, dir: oneof<string, nothing>, hide: bool, global: bool, raw: bool, interactive: bool, sources: list<string>, outputs: oneof<list<string>, record<auto: bool>>, shell: oneof<string, nothing>, quiet: bool, silent: oneof<bool, string>, tools: record, usage: string, timeout: oneof<string, nothing>, run: list<oneof<string, record<task: string>, record<tasks: list<string>>>>, args: list<string>, file: oneof<string, nothing>> {
    let text = ^mise tasks --json ...(nus argv [$task] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --global: $global
        --local: $local
        --extended: $extended
        --all: $all
        --hidden: $hidden
        --name-only: $name_only
        --no-header: $no_header
        --sort: $sort
        --sort-order: $sort_order
    })
    nus decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"title\":\"mise tasks [ls] --json\",\"$defs\":{\"dependency\":{\"oneOf\":[{\"type\":\"string\"},{\"type\":\"array\",\"items\":{\"type\":\"string\"},\"minItems\":1},{\"type\":\"object\",\"properties\":{\"task\":{\"type\":\"string\"},\"args\":{\"type\":\"array\",\"items\":{\"type\":\"string\"},\"minItems\":1},\"env\":{\"type\":\"object\",\"additionalProperties\":{\"type\":\"string\"},\"minProperties\":1},\"optional\":{\"const\":true}},\"required\":[\"task\"],\"additionalProperties\":false}]},\"run\":{\"oneOf\":[{\"type\":\"string\"},{\"type\":\"object\",\"properties\":{\"task\":{\"type\":\"string\"},\"args\":{\"type\":\"array\",\"items\":{\"type\":\"string\"},\"minItems\":1},\"env\":{\"type\":\"object\",\"additionalProperties\":{\"type\":\"string\"},\"minProperties\":1}},\"required\":[\"task\"],\"additionalProperties\":false},{\"type\":\"object\",\"properties\":{\"tasks\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}}},\"required\":[\"tasks\"],\"additionalProperties\":false}]}},\"type\":\"array\",\"items\":{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"},\"aliases\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}},\"description\":{\"type\":\"string\"},\"source\":{\"type\":\"string\"},\"config_sources\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}},\"depends\":{\"type\":\"array\",\"items\":{\"$ref\":\"#/$defs/dependency\"}},\"daemons\":{\"oneOf\":[{\"type\":\"boolean\"},{\"type\":\"string\"},{\"type\":\"array\",\"items\":{\"type\":\"string\"}},{\"type\":\"null\"}]},\"secrets\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}},\"depends_post\":{\"type\":\"array\",\"items\":{\"$ref\":\"#/$defs/dependency\"}},\"wait_for\":{\"type\":\"array\",\"items\":{\"$ref\":\"#/$defs/dependency\"}},\"env\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}},\"dir\":{\"type\":[\"string\",\"null\"]},\"hide\":{\"type\":\"boolean\"},\"global\":{\"type\":\"boolean\"},\"raw\":{\"type\":\"boolean\"},\"interactive\":{\"type\":\"boolean\"},\"sources\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}},\"outputs\":{\"oneOf\":[{\"type\":\"array\",\"items\":{\"type\":\"string\"}},{\"type\":\"object\",\"properties\":{\"auto\":{\"const\":true}},\"required\":[\"auto\"],\"additionalProperties\":false}]},\"shell\":{\"type\":[\"string\",\"null\"]},\"quiet\":{\"type\":\"boolean\"},\"silent\":{\"oneOf\":[{\"type\":\"boolean\"},{\"enum\":[\"stdout\",\"stderr\"]}]},\"tools\":{\"type\":\"object\",\"additionalProperties\":{\"oneOf\":[{\"type\":\"string\"},{\"type\":\"object\",\"properties\":{\"version\":{\"type\":\"string\"}},\"required\":[\"version\"],\"additionalProperties\":true}]}},\"usage\":{\"type\":\"string\"},\"timeout\":{\"type\":[\"string\",\"null\"]},\"run\":{\"type\":\"array\",\"items\":{\"$ref\":\"#/$defs/run\"}},\"args\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}},\"file\":{\"type\":[\"string\",\"null\"]}},\"required\":[\"name\",\"aliases\",\"description\",\"source\",\"config_sources\",\"depends\",\"daemons\",\"secrets\",\"depends_post\",\"wait_for\",\"env\",\"dir\",\"hide\",\"global\",\"raw\",\"interactive\",\"sources\",\"outputs\",\"shell\",\"quiet\",\"silent\",\"tools\",\"usage\",\"timeout\",\"run\",\"args\",\"file\"],\"additionalProperties\":false}}" { from json }
}

# Add a task
#
# Writes a `[tasks.<name>]` table to the nearest project config file and marks that file as trusted. See https://mise.jdx.dev/configuration.html#target-file-for-write-operations for how the file is chosen.
#
# With `--file`, creates an executable script in the project's task directory (for example `mise-tasks/`) instead, and does not change any config file.
@usage r#'long_help #"""
Add a task

Writes a `[tasks.<name>]` table to the nearest project config file and marks that file as trusted. See https://mise.jdx.dev/configuration.html#target-file-for-write-operations for how the file is chosen.

With `--file`, creates an executable script in the project's task directory (for example `mise-tasks/`) instead, and does not change any config file.
"""#'#
@usage 'flag "-a --alias" help="Other names for the task" var=#true {
            arg <ALIAS>
        }'
@usage 'flag "-d --depends" help="Tasks to run before this one" var=#true {
            arg <TASK>
        }'
@usage 'flag "-D --dir" help="Run the task in a specific directory" {
            arg <DIR>
        }'
@usage 'flag "-f --file" help="Create a file task instead of a TOML task"'
@usage 'flag "-H --hide" help="Hide the task from `mise tasks` and completions"'
@usage 'flag "-q --quiet" help="Do not print the command before running"'
@usage r#'flag "-r --raw" help="Connect the task directly to the terminal's stdin, stdout, and stderr"'#
@usage 'flag "-s --sources" help="Glob patterns of files this task uses as input" var=#true {
            arg <GLOB>
        }'
@usage 'flag "-w --wait-for" help="Wait for these tasks to finish if they are also being run" var=#true {
            arg <TASK>
        }'
@usage 'flag --depends-post help="Tasks to run after this one" var=#true {
            arg <TASK>
        }'
@usage 'flag --description help="Description of the task" {
            arg <DESCRIPTION>
        }'
@usage 'flag --outputs help="Glob patterns of files this task creates, used to skip it when they are up to date" var=#true {
            arg <GLOB>
        }'
@usage 'flag --run-windows help="Command to run on Windows (TOML tasks only; ignored with `--file`)" {
            arg <COMMAND>
        }'
@usage 'flag --shell help="Run the task in a specific shell" {
            arg <SHELL>
        }'
@usage 'flag --silent help="Do not print the command or its output"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <TASK> help="Name of the task to add"'
@usage 'arg "[-- RUN]…" help="Command to run, given after `--`" required=#false var=#true'
@usage r#'example "mise tasks add build --description \"Build the app\" --sources 'src/**/*.ts' --outputs 'dist/**' -- npm run build" help="Add a TOML task that is skipped while its outputs are up to date"'#
@usage 'example "mise tasks add --file lint -- eslint ." help="Create an executable lint script in the task directory"'
@usage 'example "mise tasks add ci --depends lint --depends test -- echo done" help="Add a task that runs after lint and test"'
export def "mise tasks add" [
    task: string@"nus complete",                   # Name of the task to add
    ...run: string,                                # Command to run, given after `--`
    --cd (-C): path@"nus complete",                # Run as if mise were started in DIR
    --env_ (-E): list<string>,                     # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                           # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                                  # Suppress non-error messages
    --shell: string,                               # Run the task in a specific shell
    --verbose (-v): int,                           # Show extra output (use -vv for even more)
    --yes (-y),                                    # Answer yes to all confirmation prompts
    --raw (-r),                                    # Connect tasks and install commands directly to the terminal
    --locked,                                      # Require download URLs from the lockfile when installing
    --silent,                                      # Suppress all task output and mise non-error messages
    --alias (-a): list<string>@"nus complete",     # Other names for the task
    --depends (-d): list<string>@"nus complete",   # Tasks to run before this one
    --dir (-D): path@"nus complete",               # Run the task in a specific directory
    --file (-f),                                   # Create a file task instead of a TOML task
    --hide (-H),                                   # Hide the task from `mise tasks` and completions
    --sources (-s): list<string>,                  # Glob patterns of files this task uses as input
    --wait-for (-w): list<string>@"nus complete",  # Wait for these tasks to finish if they are also being run
    --depends-post: list<string>@"nus complete",   # Tasks to run after this one
    --description: string,                         # Description of the task
    --outputs: list<string>,                       # Glob patterns of files this task creates, used to skip it when they are up to date
    --run-windows: string,                         # Command to run on Windows (TOML tasks only; ignored with `--file`)
]: nothing -> string {
    ^mise tasks add ...(nus argv [$task ...$run] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --shell: $shell
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --alias: $alias
        --depends: $depends
        --dir: $dir
        --file: $file
        --hide: $hide
        --sources: $sources
        --wait-for: $wait_for
        --depends-post: $depends_post
        --description: $description
        --outputs: $outputs
        --run-windows: $run_windows
    })
}

# Show the dependency tree of tasks
#
# The tree is built from declared dependencies: `depends`, `depends_post`, and `wait_for`. Task references inside a `run` or `run_windows` array (`{ task = "..." }` or `{ tasks = [...] }`) are execution steps, not graph edges, so they do not appear here. Those nested tasks still run, including their own `depends`.
@usage 'long_help #"""
Show the dependency tree of tasks

The tree is built from declared dependencies: `depends`, `depends_post`, and `wait_for`. Task references inside a `run` or `run_windows` array (`{ task = "..." }` or `{ tasks = [...] }`) are execution steps, not graph edges, so they do not appear here. Those nested tasks still run, including their own `depends`.
"""#'
@usage 'flag --compact help="Collapse repeated dependencies after their first occurrence" conflicts=--dot'
@usage 'flag --dot help="Display dependencies in DOT format"'
@usage 'flag --hidden help="Show hidden tasks"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[TASKS]…" help="Tasks to show (default: all tasks)" required=#false var=#true'
@usage 'example "mise tasks deps" help="Show dependencies for all tasks"'
@usage 'example "mise tasks deps lint test check" help="Show dependencies for the \"lint\", \"test\" and \"check\" tasks"'
@usage 'example "mise tasks deps --dot" help="Show dependencies in DOT format"'
@usage 'example "mise tasks deps --compact" help="Collapse repeated dependencies"'
export def "mise tasks deps" [
    ...tasks: string,                # Tasks to show (default: all tasks)
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --hidden,                        # Show hidden tasks
    --compact,                       # Collapse repeated dependencies after their first occurrence
    --dot,                           # Display dependencies in DOT format
]: nothing -> string {
    ^mise tasks deps ...(nus argv [...$tasks] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --hidden: $hidden
        --compact: $compact
        --dot: $dot
    })
}

# Open a task in your editor
#
# Opens the file that defines the task in `$VISUAL` or `$EDITOR`: the script for a file task, or the config file for a TOML task. If no task has that name, mise creates an executable bash script for it in the project's task directory (for example `mise-tasks/`) and opens that. `--path` prints the file's path instead of opening it; a missing task is still created.
@usage r#'long_help #"""
Open a task in your editor

Opens the file that defines the task in `$VISUAL` or `$EDITOR`: the script for a file task, or the config file for a TOML task. If no task has that name, mise creates an executable bash script for it in the project's task directory (for example `mise-tasks/`) and opens that. `--path` prints the file's path instead of opening it; a missing task is still created.
"""#'#
@usage r#'flag "-p --path" help="Print the task's file path instead of opening it"'#
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <TASK> help="Task to edit"'
@usage 'example "mise tasks edit build" help="Edit the build task"'
@usage r#'example "mise tasks edit --path build" help="Print the build task's file path"'#
export def "mise tasks edit" [
    task: string@"nus complete",     # Task to edit
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --path (-p),                     # Print the task's file path instead of opening it
]: nothing -> string {
    ^mise tasks edit ...(nus argv [$task] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --path: $path
    })
}

# Show the monorepo project graph
#
# Lists the projects mise infers from Cargo, uv, Go, Gradle, and Node.js workspace manifests, with each project's ID, root directory, dependencies, and metadata. `mise run --affected` uses this graph to decide which projects a change touches.
#
# See https://mise.jdx.dev/tasks/workspace-graph.html
@usage r#'long_help #"""
Show the monorepo project graph

Lists the projects mise infers from Cargo, uv, Go, Gradle, and Node.js workspace manifests, with each project's ID, root directory, dependencies, and metadata. `mise run --affected` uses this graph to decide which projects a change touches.

See https://mise.jdx.dev/tasks/workspace-graph.html
"""#'#
@usage 'flag "-J --json" help="Output the project graph as JSON"'
@usage 'flag --explain help="Show which provider and workspace file each project, dependency, and task field came from" conflicts=--json'
@usage 'flag --no-header help="Do not print table headers" {
            alias "--no-headers" hide=#true
        }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise tasks graph" help="List projects and their dependencies"'
@usage 'example "mise tasks graph --json" help="Print the project graph as JSON"'
@usage 'example "mise tasks graph --explain" help="Show which workspace file each project, dependency, and task came from"'
@usage 'output json framing=json select=--json'
export def "mise tasks graph" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --no-header,                     # Do not print table headers
    --explain,                       # Show which provider and workspace file each project, dependency, and task field came from
] {
    ^mise tasks graph --json ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --no-header: $no_header
        --explain: $explain
    }) | from json
}

# Show a task's definition
#
# Prints the task's description, source file, dependencies, sources, outputs, run commands, environment, and usage spec. `--json` prints the full definition.
@usage r#'long_help #"""
Show a task's definition

Prints the task's description, source file, dependencies, sources, outputs, run commands, environment, and usage spec. `--json` prints the full definition.
"""#'#
@usage 'flag "-J --json" help="Output in JSON format"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <TASK> help="Name of the task to get information about"'
@usage 'example "mise tasks info test" help="Show the test task and the file that defines it"'
@usage 'example "mise tasks info test --json" help="Get the full structured task definition"'
@usage 'output json framing=json select=--json'
export def "mise tasks info" [
    task: string@"nus complete",     # Name of the task to get information about
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
] {
    ^mise tasks info --json ...(nus argv [$task] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    }) | from json
}

# List available tasks
#
# Lists tasks from `[tasks]` in your config files and from task directories such as `mise-tasks/`, `.mise-tasks/`, and `.mise/tasks/`, including global tasks in `~/.config/mise/tasks/`. Tasks from parent directories and the global config are included; a project task overrides a global task with the same name. In a monorepo, `--all` also lists tasks from sibling projects.
#
# See https://mise.jdx.dev/tasks/task-discovery.html
@usage 'long_help #"""
List available tasks

Lists tasks from `[tasks]` in your config files and from task directories such as `mise-tasks/`, `.mise-tasks/`, and `.mise/tasks/`, including global tasks in `~/.config/mise/tasks/`. Tasks from parent directories and the global config are included; a project task overrides a global task with the same name. In a monorepo, `--all` also lists tasks from sibling projects.

See https://mise.jdx.dev/tasks/task-discovery.html
"""#'
@usage 'flag "-g --global" help="Only show global tasks" overrides=--local'
@usage 'flag "-J --json" help="Output in JSON format"'
@usage 'flag "-l --local" help="Only show non-global tasks" overrides=--global'
@usage 'flag "-x --extended" help="Show all columns"'
@usage r#'flag "-a --all" help="Include tasks from every project in the monorepo, not only the current directory's hierarchy"'#
@usage 'flag --complete help="Display tasks for usage completion" hide=#true'
@usage 'flag --hidden help="Show hidden tasks"'
@usage 'flag --name-only help="Print only task names, one per line (for fzf and similar tools)" {
            conflicts "--json" "--extended" "--usage"
        }'
@usage 'flag --no-header help="Do not print the table header" {
            alias "--no-headers" hide=#true
        }'
@usage 'flag --sort help="Column to sort by (default: name)" {
            arg <COLUMN> {
                choices {
                    choice name
                    choice alias
                    choice description
                    choice source
                }
            }
        }'
@usage 'flag --sort-order help="Sort direction (default: asc)" {
            arg <SORT_ORDER> {
                choices {
                    choice asc
                    choice desc
                }
            }
        }'
@usage 'flag --usage hide=#true'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example "mise tasks ls" help="List tasks"'
@usage 'example "mise tasks ls --hidden" help="Include hidden tasks"'
@usage 'example "mise tasks ls --all" help="List tasks from every monorepo project"'
@usage 'example "mise tasks ls --name-only | fzf" help="Pick a task name interactively"'
@usage 'output "json" framing="json" select="--json" {
    schema "{\n  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",\n  \"title\": \"mise tasks [ls] --json\",\n  \"$defs\": {\n    \"dependency\": {\n      \"oneOf\": [\n        {\n          \"type\": \"string\"\n        },\n        {\n          \"type\": \"array\",\n          \"items\": {\n            \"type\": \"string\"\n          },\n          \"minItems\": 1\n        },\n        {\n          \"type\": \"object\",\n          \"properties\": {\n            \"task\": {\n              \"type\": \"string\"\n            },\n            \"args\": {\n              \"type\": \"array\",\n              \"items\": {\n                \"type\": \"string\"\n              },\n              \"minItems\": 1\n            },\n            \"env\": {\n              \"type\": \"object\",\n              \"additionalProperties\": {\n                \"type\": \"string\"\n              },\n              \"minProperties\": 1\n            },\n            \"optional\": {\n              \"const\": true\n            }\n          },\n          \"required\": [\n            \"task\"\n          ],\n          \"additionalProperties\": false\n        }\n      ]\n    },\n    \"run\": {\n      \"oneOf\": [\n        {\n          \"type\": \"string\"\n        },\n        {\n          \"type\": \"object\",\n          \"properties\": {\n            \"task\": {\n              \"type\": \"string\"\n            },\n            \"args\": {\n              \"type\": \"array\",\n              \"items\": {\n                \"type\": \"string\"\n              },\n              \"minItems\": 1\n            },\n            \"env\": {\n              \"type\": \"object\",\n              \"additionalProperties\": {\n                \"type\": \"string\"\n              },\n              \"minProperties\": 1\n            }\n          },\n          \"required\": [\n            \"task\"\n          ],\n          \"additionalProperties\": false\n        },\n        {\n          \"type\": \"object\",\n          \"properties\": {\n            \"tasks\": {\n              \"type\": \"array\",\n              \"items\": {\n                \"type\": \"string\"\n              }\n            }\n          },\n          \"required\": [\n            \"tasks\"\n          ],\n          \"additionalProperties\": false\n        }\n      ]\n    }\n  },\n  \"type\": \"array\",\n  \"items\": {\n    \"type\": \"object\",\n    \"properties\": {\n      \"name\": {\n        \"type\": \"string\"\n      },\n      \"aliases\": {\n        \"type\": \"array\",\n        \"items\": {\n          \"type\": \"string\"\n        }\n      },\n      \"description\": {\n        \"type\": \"string\"\n      },\n      \"source\": {\n        \"type\": \"string\"\n      },\n      \"config_sources\": {\n        \"type\": \"array\",\n        \"items\": {\n          \"type\": \"string\"\n        }\n      },\n      \"depends\": {\n        \"type\": \"array\",\n        \"items\": {\n          \"$ref\": \"#/$defs/dependency\"\n        }\n      },\n      \"daemons\": {\n        \"oneOf\": [\n          {\n            \"type\": \"boolean\"\n          },\n          {\n            \"type\": \"string\"\n          },\n          {\n            \"type\": \"array\",\n            \"items\": {\n              \"type\": \"string\"\n            }\n          },\n          {\n            \"type\": \"null\"\n          }\n        ]\n      },\n      \"secrets\": {\n        \"type\": \"array\",\n        \"items\": {\n          \"type\": \"string\"\n        }\n      },\n      \"depends_post\": {\n        \"type\": \"array\",\n        \"items\": {\n          \"$ref\": \"#/$defs/dependency\"\n        }\n      },\n      \"wait_for\": {\n        \"type\": \"array\",\n        \"items\": {\n          \"$ref\": \"#/$defs/dependency\"\n        }\n      },\n      \"env\": {\n        \"type\": \"array\",\n        \"items\": {\n          \"type\": \"string\"\n        }\n      },\n      \"dir\": {\n        \"type\": [\n          \"string\",\n          \"null\"\n        ]\n      },\n      \"hide\": {\n        \"type\": \"boolean\"\n      },\n      \"global\": {\n        \"type\": \"boolean\"\n      },\n      \"raw\": {\n        \"type\": \"boolean\"\n      },\n      \"interactive\": {\n        \"type\": \"boolean\"\n      },\n      \"sources\": {\n        \"type\": \"array\",\n        \"items\": {\n          \"type\": \"string\"\n        }\n      },\n      \"outputs\": {\n        \"oneOf\": [\n          {\n            \"type\": \"array\",\n            \"items\": {\n              \"type\": \"string\"\n            }\n          },\n          {\n            \"type\": \"object\",\n            \"properties\": {\n              \"auto\": {\n                \"const\": true\n              }\n            },\n            \"required\": [\n              \"auto\"\n            ],\n            \"additionalProperties\": false\n          }\n        ]\n      },\n      \"shell\": {\n        \"type\": [\n          \"string\",\n          \"null\"\n        ]\n      },\n      \"quiet\": {\n        \"type\": \"boolean\"\n      },\n      \"silent\": {\n        \"oneOf\": [\n          {\n            \"type\": \"boolean\"\n          },\n          {\n            \"enum\": [\n              \"stdout\",\n              \"stderr\"\n            ]\n          }\n        ]\n      },\n      \"tools\": {\n        \"type\": \"object\",\n        \"additionalProperties\": {\n          \"oneOf\": [\n            {\n              \"type\": \"string\"\n            },\n            {\n              \"type\": \"object\",\n              \"properties\": {\n                \"version\": {\n                  \"type\": \"string\"\n                }\n              },\n              \"required\": [\n                \"version\"\n              ],\n              \"additionalProperties\": true\n            }\n          ]\n        }\n      },\n      \"usage\": {\n        \"type\": \"string\"\n      },\n      \"timeout\": {\n        \"type\": [\n          \"string\",\n          \"null\"\n        ]\n      },\n      \"run\": {\n        \"type\": \"array\",\n        \"items\": {\n          \"$ref\": \"#/$defs/run\"\n        }\n      },\n      \"args\": {\n        \"type\": \"array\",\n        \"items\": {\n          \"type\": \"string\"\n        }\n      },\n      \"file\": {\n        \"type\": [\n          \"string\",\n          \"null\"\n        ]\n      }\n    },\n    \"required\": [\n      \"name\",\n      \"aliases\",\n      \"description\",\n      \"source\",\n      \"config_sources\",\n      \"depends\",\n      \"daemons\",\n      \"secrets\",\n      \"depends_post\",\n      \"wait_for\",\n      \"env\",\n      \"dir\",\n      \"hide\",\n      \"global\",\n      \"raw\",\n      \"interactive\",\n      \"sources\",\n      \"outputs\",\n      \"shell\",\n      \"quiet\",\n      \"silent\",\n      \"tools\",\n      \"usage\",\n      \"timeout\",\n      \"run\",\n      \"args\",\n      \"file\"\n    ],\n    \"additionalProperties\": false\n  }\n}\n"
}'
export def "mise tasks ls" [
    --cd (-C): path@"nus complete",                  # Run as if mise were started in DIR
    --env_ (-E): list<string>,                       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                                    # Suppress non-error messages
    --verbose (-v): int,                             # Show extra output (use -vv for even more)
    --yes (-y),                                      # Answer yes to all confirmation prompts
    --raw,                                           # Connect tasks and install commands directly to the terminal
    --locked,                                        # Require download URLs from the lockfile when installing
    --silent,                                        # Suppress all task output and mise non-error messages
    --global (-g),                                   # Only show global tasks
    --local (-l),                                    # Only show non-global tasks
    --extended (-x),                                 # Show all columns
    --all (-a),                                      # Include tasks from every project in the monorepo, not only the current directory's hierarchy
    --hidden,                                        # Show hidden tasks
    --name-only,                                     # Print only task names, one per line (for fzf and similar tools)
    --no-header,                                     # Do not print the table header
    --sort: string@[name alias description source],  # Column to sort by (default: name)
    --sort-order: string@[asc desc],                 # Sort direction (default: asc)
]: nothing -> table<name: string, aliases: list<string>, description: string, source: string, config_sources: list<string>, depends: list<oneof<string, list<string>, record<task: string>>>, daemons: oneof<bool, string, list<string>, nothing>, secrets: list<string>, depends_post: list<oneof<string, list<string>, record<task: string>>>, wait_for: list<oneof<string, list<string>, record<task: string>>>, env: list<string>, dir: oneof<string, nothing>, hide: bool, global: bool, raw: bool, interactive: bool, sources: list<string>, outputs: oneof<list<string>, record<auto: bool>>, shell: oneof<string, nothing>, quiet: bool, silent: oneof<bool, string>, tools: record, usage: string, timeout: oneof<string, nothing>, run: list<oneof<string, record<task: string>, record<tasks: list<string>>>>, args: list<string>, file: oneof<string, nothing>> {
    let text = ^mise tasks ls --json ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --global: $global
        --local: $local
        --extended: $extended
        --all: $all
        --hidden: $hidden
        --name-only: $name_only
        --no-header: $no_header
        --sort: $sort
        --sort-order: $sort_order
    })
    nus decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"title\":\"mise tasks [ls] --json\",\"$defs\":{\"dependency\":{\"oneOf\":[{\"type\":\"string\"},{\"type\":\"array\",\"items\":{\"type\":\"string\"},\"minItems\":1},{\"type\":\"object\",\"properties\":{\"task\":{\"type\":\"string\"},\"args\":{\"type\":\"array\",\"items\":{\"type\":\"string\"},\"minItems\":1},\"env\":{\"type\":\"object\",\"additionalProperties\":{\"type\":\"string\"},\"minProperties\":1},\"optional\":{\"const\":true}},\"required\":[\"task\"],\"additionalProperties\":false}]},\"run\":{\"oneOf\":[{\"type\":\"string\"},{\"type\":\"object\",\"properties\":{\"task\":{\"type\":\"string\"},\"args\":{\"type\":\"array\",\"items\":{\"type\":\"string\"},\"minItems\":1},\"env\":{\"type\":\"object\",\"additionalProperties\":{\"type\":\"string\"},\"minProperties\":1}},\"required\":[\"task\"],\"additionalProperties\":false},{\"type\":\"object\",\"properties\":{\"tasks\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}}},\"required\":[\"tasks\"],\"additionalProperties\":false}]}},\"type\":\"array\",\"items\":{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"},\"aliases\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}},\"description\":{\"type\":\"string\"},\"source\":{\"type\":\"string\"},\"config_sources\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}},\"depends\":{\"type\":\"array\",\"items\":{\"$ref\":\"#/$defs/dependency\"}},\"daemons\":{\"oneOf\":[{\"type\":\"boolean\"},{\"type\":\"string\"},{\"type\":\"array\",\"items\":{\"type\":\"string\"}},{\"type\":\"null\"}]},\"secrets\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}},\"depends_post\":{\"type\":\"array\",\"items\":{\"$ref\":\"#/$defs/dependency\"}},\"wait_for\":{\"type\":\"array\",\"items\":{\"$ref\":\"#/$defs/dependency\"}},\"env\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}},\"dir\":{\"type\":[\"string\",\"null\"]},\"hide\":{\"type\":\"boolean\"},\"global\":{\"type\":\"boolean\"},\"raw\":{\"type\":\"boolean\"},\"interactive\":{\"type\":\"boolean\"},\"sources\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}},\"outputs\":{\"oneOf\":[{\"type\":\"array\",\"items\":{\"type\":\"string\"}},{\"type\":\"object\",\"properties\":{\"auto\":{\"const\":true}},\"required\":[\"auto\"],\"additionalProperties\":false}]},\"shell\":{\"type\":[\"string\",\"null\"]},\"quiet\":{\"type\":\"boolean\"},\"silent\":{\"oneOf\":[{\"type\":\"boolean\"},{\"enum\":[\"stdout\",\"stderr\"]}]},\"tools\":{\"type\":\"object\",\"additionalProperties\":{\"oneOf\":[{\"type\":\"string\"},{\"type\":\"object\",\"properties\":{\"version\":{\"type\":\"string\"}},\"required\":[\"version\"],\"additionalProperties\":true}]}},\"usage\":{\"type\":\"string\"},\"timeout\":{\"type\":[\"string\",\"null\"]},\"run\":{\"type\":\"array\",\"items\":{\"$ref\":\"#/$defs/run\"}},\"args\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}},\"file\":{\"type\":[\"string\",\"null\"]}},\"required\":[\"name\",\"aliases\",\"description\",\"source\",\"config_sources\",\"depends\",\"daemons\",\"secrets\",\"depends_post\",\"wait_for\",\"env\",\"dir\",\"hide\",\"global\",\"raw\",\"interactive\",\"sources\",\"outputs\",\"shell\",\"quiet\",\"silent\",\"tools\",\"usage\",\"timeout\",\"run\",\"args\",\"file\"],\"additionalProperties\":false}}" { from json }
}

# Check task definitions for errors
#
# Checks each task for dependency cycles; references to tasks that do not exist; `#USAGE` specs that do not parse; invalid `timeout` values; aliases that more than one task uses; missing or non-executable file tasks; invalid `dir` paths and templates; missing shell executables; invalid `sources` and `outputs` globs; broken task references in `run` arrays, empty scripts, and tasks with nothing to run; required `daemons` that no readable `[daemons]` section declares; and `secrets` grants that conflict with the sandbox or `[env]`, or, when the config is trusted, that name keys missing from the secrets source.
#
# Exits 1 if any error is found, so you can run it in CI. Warnings are reported but do not fail the command.
@usage 'long_help #"""
Check task definitions for errors

Checks each task for dependency cycles; references to tasks that do not exist; `#USAGE` specs that do not parse; invalid `timeout` values; aliases that more than one task uses; missing or non-executable file tasks; invalid `dir` paths and templates; missing shell executables; invalid `sources` and `outputs` globs; broken task references in `run` arrays, empty scripts, and tasks with nothing to run; required `daemons` that no readable `[daemons]` section declares; and `secrets` grants that conflict with the sandbox or `[env]`, or, when the config is trusted, that name keys missing from the secrets source.

Exits 1 if any error is found, so you can run it in CI. Warnings are reported but do not fail the command.
"""#'
@usage 'flag --errors-only help="Only show errors (skip warnings)"'
@usage 'flag --json help="Output validation results in JSON format"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[TASKS]…" help="Tasks to validate (default: all tasks)" required=#false var=#true'
@usage 'example "mise tasks validate" help="Validate all tasks"'
@usage 'example "mise tasks validate build test" help="Validate specific tasks"'
@usage 'example "mise tasks validate --json" help="Output results as JSON"'
@usage 'example "mise tasks validate --errors-only" help="Only show errors (skip warnings)"'
@usage 'output "json" framing="json" select="--json" {
    schema "{\n  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",\n  \"title\": \"mise tasks validate --json\",\n  \"type\": \"object\",\n  \"properties\": {\n    \"tasks_validated\": {\n      \"type\": \"integer\",\n      \"minimum\": 0\n    },\n    \"errors\": {\n      \"type\": \"integer\",\n      \"minimum\": 0\n    },\n    \"warnings\": {\n      \"type\": \"integer\",\n      \"minimum\": 0\n    },\n    \"issues\": {\n      \"type\": \"array\",\n      \"items\": {\n        \"type\": \"object\",\n        \"properties\": {\n          \"task\": {\n            \"type\": \"string\"\n          },\n          \"severity\": {\n            \"enum\": [\n              \"error\",\n              \"warning\",\n              \"info\"\n            ]\n          },\n          \"category\": {\n            \"type\": \"string\"\n          },\n          \"message\": {\n            \"type\": \"string\"\n          },\n          \"details\": {\n            \"type\": \"string\"\n          }\n        },\n        \"required\": [\n          \"task\",\n          \"severity\",\n          \"category\",\n          \"message\"\n        ],\n        \"additionalProperties\": false\n      }\n    }\n  },\n  \"required\": [\n    \"tasks_validated\",\n    \"errors\",\n    \"warnings\",\n    \"issues\"\n  ],\n  \"additionalProperties\": false\n}\n"
}'
export def "mise tasks validate" [
    ...tasks: string,                # Tasks to validate (default: all tasks)
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --errors-only,                   # Only show errors (skip warnings)
]: nothing -> record<tasks_validated: int, errors: int, warnings: int, issues: table<task: string, severity: string, category: string, message: string, details: oneof<string, nothing>>> {
    let text = ^mise tasks validate --json ...(nus argv [...$tasks] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --errors-only: $errors_only
    })
    nus decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"title\":\"mise tasks validate --json\",\"type\":\"object\",\"properties\":{\"tasks_validated\":{\"type\":\"integer\",\"minimum\":0},\"errors\":{\"type\":\"integer\",\"minimum\":0},\"warnings\":{\"type\":\"integer\",\"minimum\":0},\"issues\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"properties\":{\"task\":{\"type\":\"string\"},\"severity\":{\"enum\":[\"error\",\"warning\",\"info\"]},\"category\":{\"type\":\"string\"},\"message\":{\"type\":\"string\"},\"details\":{\"type\":\"string\"}},\"required\":[\"task\",\"severity\",\"category\",\"message\"],\"additionalProperties\":false}}},\"required\":[\"tasks_validated\",\"errors\",\"warnings\",\"issues\"],\"additionalProperties\":false}" { from json | update issues { default null details } }
}

# Test that a tool installs and runs
#
# Installs each tool and runs the `test` command from its registry entry
# (registry/<tool>.toml), checking the output. Use it when adding or changing
# a registry entry. The minimum release age is ignored so that new releases
# can be tested right away.
#
# Warning: before testing, this deletes every installed version of each tested
# tool, along with its cache and downloads directories, so the test installs
# from scratch. To keep your installs and caches, run it with throwaway
# MISE_DATA_DIR and MISE_CACHE_DIR directories.
#
# Registry tools with no `test` entry, or that registry/ marks as unsupported
# on this OS, are skipped without output, and the command still exits 0. Pass
# --include-non-defined to run `<tool> --version` for tools with no `test`
# entry.
@usage 'long_help #"""
Test that a tool installs and runs

Installs each tool and runs the `test` command from its registry entry
(registry/<tool>.toml), checking the output. Use it when adding or changing
a registry entry. The minimum release age is ignored so that new releases
can be tested right away.

Warning: before testing, this deletes every installed version of each tested
tool, along with its cache and downloads directories, so the test installs
from scratch. To keep your installs and caches, run it with throwaway
MISE_DATA_DIR and MISE_CACHE_DIR directories.

Registry tools with no `test` entry, or that registry/ marks as unsupported
on this OS, are skipped without output, and the command still exits 0. Pass
--include-non-defined to run `<tool> --version` for tools with no `test`
entry.
"""#'
@usage 'flag "-a --all" help="Test every registry tool that defines a `test` and supports this OS" {
        conflicts TOOLS "--all-config"
    }'
@usage 'flag "-j --jobs" help="Number of tools to test in parallel (default 4)" env=MISE_TEST_TOOL_JOBS {
        arg <JOBS>
    }'
@usage 'flag --all-config help="Test all tools specified in config files" {
        conflicts TOOLS "--all"
    }'
@usage 'flag --include-non-defined help="Also test registry tools that have no `test` entry by running `<tool> --version`" {
        long_help #"""
Also test registry tools that have no `test` entry by running `<tool> --version`

These always report a failure that shows the output, for use when writing a test.
"""#
    }'
@usage r#'flag --raw help="Connect the install commands' stdin, stdout, and stderr to the terminal" overrides=--jobs {
        long_help #"""
Connect the install commands' stdin, stdout, and stderr to the terminal

Implies `--jobs=1`.
"""#
    }'#
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[TOOLS]…" help="Tools to test" required=#false var=#true {
        required_unless "--all" "--all-config"
    }'
@usage 'example "mise test-tool ripgrep" help="Reinstall ripgrep and run its registry test"'
@usage 'example "MISE_DATA_DIR=$(mktemp -d) MISE_CACHE_DIR=$(mktemp -d) mise test-tool --all-config" help="Test every tool in the config without touching your installs"'
export def "mise test-tool" [
    ...tools: string,                # Tools to test
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --all (-a),                      # Test every registry tool that defines a `test` and supports this OS
    --all-config,                    # Test all tools specified in config files
    --include-non-defined,           # Also test registry tools that have no `test` entry by running `<tool> --version`
]: nothing -> string {
    ^mise test-tool ...(nus argv [...$tools] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --all: $all
        --all-config: $all_config
        --include-non-defined: $include_non_defined
    })
}

# Show which Git provider token mise uses
#
# Shows the token mise would send to a GitHub, GitLab, or Forgejo host and
# where it came from, to debug authentication.
# See https://mise.jdx.dev/dev-tools/github-tokens.html
@usage 'long_help #"""
Show which Git provider token mise uses

Shows the token mise would send to a GitHub, GitLab, or Forgejo host and
where it came from, to debug authentication.
See https://mise.jdx.dev/dev-tools/github-tokens.html
"""#'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise token" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise token ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Show the Forgejo token mise uses for a host
#
# Shows the token and where it came from, to debug authentication. The token
# is masked unless you pass --unmask.
@usage 'long_help #"""
Show the Forgejo token mise uses for a host

Shows the token and where it came from, to debug authentication. The token
is masked unless you pass --unmask.
"""#'
@usage 'flag --unmask help="Show the full unmasked token"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[HOST]" help="Forgejo hostname" required=#false default=codeberg.org'
@usage 'example #"""
mise token forgejo
codeberg.org: xxxx…xxxx (source: FORGEJO_TOKEN)
"""# help="Show the token for codeberg.org"'
@usage 'example #"""
mise token forgejo --unmask
codeberg.org: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx (source: FORGEJO_TOKEN)
"""# help="Show the whole token"'
@usage 'example #"""
mise token forgejo forgejo.mycompany.com
forgejo.mycompany.com: (none)
"""# help="Check a self-hosted Forgejo instance"'
export def "mise token forgejo" [
    host?: string,                   # Forgejo hostname
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --unmask,                        # Show the full unmasked token
]: nothing -> string {
    ^mise token forgejo ...(nus argv [$host] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --unmask: $unmask
    })
}

# Show the GitHub token mise uses for a host
#
# Shows the token and where it came from, to debug authentication. The token
# is masked unless you pass --unmask or --raw.
@usage 'long_help #"""
Show the GitHub token mise uses for a host

Shows the token and where it came from, to debug authentication. The token
is masked unless you pass --unmask or --raw.
"""#'
@usage r#'flag --git-credential help="Speak Git's credential helper protocol" hide=#true {
            arg <GIT_CREDENTIAL>
        }'#
@usage 'flag --oauth help="Use only native GitHub OAuth (a cached token, a refresh, or the device-code flow), ignoring other token sources"'
@usage 'flag --raw help="Print only the token, unmasked, for use in scripts"'
@usage r#'flag --refresh help="With --oauth, get a new OAuth token even if the cached one has not expired, through the refresh-token grant or a new device-code flow. Use it after changing the GitHub App's installations or permissions: cached tokens keep their original access until they expire." requires=--oauth'#
@usage 'flag --unmask help="Show the full unmasked token"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[HOST]" help="GitHub hostname" required=#false default=github.com'
@usage 'example #"""
mise token github
github.com: ghp_…xxxx (source: GITHUB_TOKEN)
"""# help="Show the token for github.com"'
@usage 'example #"""
mise token github --unmask
github.com: ghp_xxxxxxxxxxxx (source: GITHUB_TOKEN)
"""# help="Show the whole token"'
@usage 'example #"""
mise token github github.mycompany.com
github.mycompany.com: (none)
"""# help="Check a GitHub Enterprise host"'
@usage 'example #"""
mise token github --oauth --refresh
github.com: gho_…xxxx (source: GitHub OAuth)
"""# help="Get a new token through native GitHub OAuth"'
@usage 'example "GH_TOKEN=$(mise token github --raw) gh api user" help="Pass the resolved token to another tool"'
export def "mise token github" [
    host?: string,                   # GitHub hostname
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --oauth,                         # Use only native GitHub OAuth (a cached token, a refresh, or the device-code flow), ignoring other token sources
    --refresh,                       # With --oauth, get a new OAuth token even if the cached one has not expired, through the refresh-token grant or a new device-code flow. Use it after changing the GitHub App's installations or permissions: cached tokens keep their original access until they expire.
    --unmask,                        # Show the full unmasked token
]: nothing -> string {
    ^mise token github ...(nus argv [$host] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --oauth: $oauth
        --refresh: $refresh
        --unmask: $unmask
    })
}

# Show the GitLab token mise uses for a host
#
# Shows the token and where it came from, to debug authentication. The token
# is masked unless you pass --unmask.
@usage 'long_help #"""
Show the GitLab token mise uses for a host

Shows the token and where it came from, to debug authentication. The token
is masked unless you pass --unmask.
"""#'
@usage 'flag --unmask help="Show the full unmasked token"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[HOST]" help="GitLab hostname" required=#false default=gitlab.com'
@usage 'example #"""
mise token gitlab
gitlab.com: glpa…xxxx (source: GITLAB_TOKEN)
"""# help="Show the token for gitlab.com"'
@usage 'example #"""
mise token gitlab --unmask
gitlab.com: glpat-xxxxxxxxxxxx (source: GITLAB_TOKEN)
"""# help="Show the whole token"'
@usage 'example #"""
mise token gitlab gitlab.mycompany.com
gitlab.mycompany.com: (none)
"""# help="Check a self-managed GitLab instance"'
export def "mise token gitlab" [
    host?: string,                   # GitLab hostname
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --unmask,                        # Show the full unmasked token
]: nothing -> string {
    ^mise token gitlab ...(nus argv [$host] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --unmask: $unmask
    })
}

# Show information about a tool
#
# Shows the tool's backend, its description and project URL when known, the
# installed, active, and requested versions, the config file that requests it,
# its tool options, and the backend's security features. Pass a field flag
# such as `--backend` to print one field, or `--json` for all of them.
@usage r#'long_help #"""
Show information about a tool

Shows the tool's backend, its description and project URL when known, the
installed, active, and requested versions, the config file that requests it,
its tool options, and the backend's security features. Pass a field flag
such as `--backend` to print one field, or `--json` for all of them.
"""#'#
@usage 'flag "-J --json" help="Output in JSON format"'
@usage 'flag --active help="Only show active versions"'
@usage 'flag --backend help="Only show backend field"'
@usage 'flag --config-source help="Only show config source"'
@usage 'flag --description help="Only show description field"'
@usage 'flag --installed help="Only show installed versions"'
@usage 'flag --requested help="Only show requested versions"'
@usage 'flag --tool-options help="Only show tool options"'
@usage 'flag --url help="Only show the project URL from the registry"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <TOOL> help="The tool, such as `node` or `aqua:jqlang/jq`"'
@usage 'group tool-info-filter "--active" "--backend" "--config-source" "--description" "--installed" "--requested" "--tool-options" "--url"'
@usage 'example #"""
mise tool node
Backend:            core:node
Installed Versions: 22.0.0 24.0.0
Active Version:     24.0.0
Requested Version:  24
Config Source:      ~/.config/mise/config.toml
Tool Options:       [none]
Security:           checksum (sha256), gpg
"""# help="Show everything mise knows about node"'
@usage 'example #"""
mise tool node --backend
core:node
"""# help="Print only the backend"'
@usage 'output json framing=json select=--json'
export def "mise tool" [
    tool: string@"nus complete",     # The tool, such as `node` or `aqua:jqlang/jq`
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --active,                        # Only show active versions
    --backend,                       # Only show backend field
    --config-source,                 # Only show config source
    --description,                   # Only show description field
    --installed,                     # Only show installed versions
    --requested,                     # Only show requested versions
    --tool-options,                  # Only show tool options
    --url,                           # Only show the project URL from the registry
] {
    ^mise tool --json ...(nus argv [$tool] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --active: $active
        --backend: $backend
        --config-source: $config_source
        --description: $description
        --installed: $installed
        --requested: $requested
        --tool-options: $tool_options
        --url: $url
    }) | from json
}

# Run a tool stub file
#
# A tool stub is an executable file whose shebang is
# `#!/usr/bin/env -S mise tool-stub` and whose body is TOML naming a tool,
# version, and executable. Running the stub runs this command, which installs
# the tool if needed and runs it with the stub's arguments. You rarely call it
# directly; create stubs with `mise generate tool-stub`.
#
# ```toml
# #!/usr/bin/env -S mise tool-stub
# # Node.js 24
#
# tool = "node"
# version = "24"
# bin = "node"
# ```
#
# See https://mise.jdx.dev/dev-tools/tool-stubs.html
@usage r#'long_help #"""
Run a tool stub file

A tool stub is an executable file whose shebang is
`#!/usr/bin/env -S mise tool-stub` and whose body is TOML naming a tool,
version, and executable. Running the stub runs this command, which installs
the tool if needed and runs it with the stub's arguments. You rarely call it
directly; create stubs with `mise generate tool-stub`.

```toml
#!/usr/bin/env -S mise tool-stub
# Node.js 24

tool = "node"
version = "24"
bin = "node"
```

See https://mise.jdx.dev/dev-tools/tool-stubs.html
"""#'#
@usage r#'arg <FILE> help="Path to the TOML tool stub file to execute" help_long=#"""
Path to the TOML tool stub file to execute

Every field is optional: `version` defaults to `latest`, `tool` defaults to the stub's file name (or `http:<file name>` when the stub sets `url` or platform URLs), and `bin` defaults to the stub's file name. A stub can also set backend-specific options.
"""# double_dash=automatic'#
@usage 'arg "[ARGS]…" help="Arguments to pass to the tool" help_long=#"""
Arguments to pass to the tool

Every argument after the stub path is passed to the tool unchanged, including a literal `--`.
"""# required=#false double_dash=automatic var=#true'
export def "mise tool-stub" [
    file: string,                    # Path to the TOML tool stub file to execute
    ...args: string,                 # Arguments to pass to the tool
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise tool-stub ...(nus argv [$file ...$args] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Mark a config file as trusted
#
# Trust lets mise load the parts of a config file that can run code or change
# your environment. Without it, mise prompts, skips the file, or fails with an
# untrusted-config error when it cannot prompt.
#
# A file with no template syntax that contains only `min_version`, `[tools]`
# entries with plain version strings (or arrays of them), and `[tasks]` in
# which no task lists `secrets` does not need trust unless paranoid mode is on.
# Commands that run project code (`mise run`, task shorthand such as
# `mise build`, `mise install`, `mise exec`, `mise watch`, and
# `mise daemons start|restart|register`) trust their active config
# automatically.
#
# In paranoid mode, `mise trust` with no path also trusts the env files and
# scripts that config reads (`env._.file`, `env._.source` and the `env_file`
# setting), which have trust of their own. Give a file's path to trust only
# that file.
#
# Trusting a config file in a repository's main checkout also trusts the same
# path in its git worktrees. Paranoid mode (https://mise.jdx.dev/paranoid.html)
# turns off automatic and worktree trust and requires trust, tied to the
# file's contents, for every config outside the global and system config.
# See https://mise.jdx.dev/security.html#configuration-trust
@usage r#'long_help #"""
Mark a config file as trusted

Trust lets mise load the parts of a config file that can run code or change
your environment. Without it, mise prompts, skips the file, or fails with an
untrusted-config error when it cannot prompt.

A file with no template syntax that contains only `min_version`, `[tools]`
entries with plain version strings (or arrays of them), and `[tasks]` in
which no task lists `secrets` does not need trust unless paranoid mode is on.
Commands that run project code (`mise run`, task shorthand such as
`mise build`, `mise install`, `mise exec`, `mise watch`, and
`mise daemons start|restart|register`) trust their active config
automatically.

In paranoid mode, `mise trust` with no path also trusts the env files and
scripts that config reads (`env._.file`, `env._.source` and the `env_file`
setting), which have trust of their own. Give a file's path to trust only
that file.

Trusting a config file in a repository's main checkout also trusts the same
path in its git worktrees. Paranoid mode (https://mise.jdx.dev/paranoid.html)
turns off automatic and worktree trust and requires trust, tied to the
file's contents, for every config outside the global and system config.
See https://mise.jdx.dev/security.html#configuration-trust
"""#'#
@usage 'flag "-a --all" help="Trust all config files in the current directory, its parents, and its subdirectories" {
        long_help #"""
Trust all config files in the current directory, its parents, and its subdirectories

Subdirectories are walked respecting .gitignore, skipping hidden directories and common build and dependency directories (node_modules, vendor, target, dist, build).
"""#
        conflicts "--ignore" "--untrust"
    }'
@usage 'flag --ignore help="Do not trust this config and ignore it in the future" conflicts=--untrust'
@usage 'flag --show help="Show the trust status of config files in the current directory and its parents" {
        long_help #"""
Show the trust status of config files in the current directory and its parents

Does not trust or untrust any files.
"""#
    }'
@usage 'flag --untrust help="Remove explicit trust for this config"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[CONFIG_FILE]" help="The config file whose trust status to change" required=#false'
@usage 'example "mise trust" help="Trust the nearest untrusted config in this directory or a parent, and in paranoid mode the env files it reads"'
@usage 'example "mise trust ~/src/app/mise.toml" help="Trust a specific file"'
@usage 'example "mise trust --show" help="List configs here and above with their trust status"'
@usage 'complete config_file type=path'
export def "mise trust" [
    config_file?: path@"nus complete",  # The config file whose trust status to change
    --cd (-C): path@"nus complete",     # Run as if mise were started in DIR
    --env_ (-E): list<string>,          # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                       # Suppress non-error messages
    --verbose (-v): int,                # Show extra output (use -vv for even more)
    --yes (-y),                         # Answer yes to all confirmation prompts
    --raw,                              # Connect tasks and install commands directly to the terminal
    --locked,                           # Require download URLs from the lockfile when installing
    --silent,                           # Suppress all task output and mise non-error messages
    --all (-a),                         # Trust all config files in the current directory, its parents, and its subdirectories
    --ignore,                           # Do not trust this config and ignore it in the future
    --show,                             # Show the trust status of config files in the current directory and its parents
    --untrust,                          # Remove explicit trust for this config
]: nothing -> string {
    ^mise trust ...(nus argv [$config_file] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --all: $all
        --ignore: $ignore
        --show: $show
        --untrust: $untrust
    })
}

# Remove installed tool versions
#
# Removes installed versions but does not edit mise.toml. Use `mise unuse` to
# remove a tool from mise.toml and uninstall it. A tool name or version prefix,
# such as `node` or `node@22`, must match exactly one installed version unless
# you pass `--all`.
@usage 'long_help #"""
Remove installed tool versions

Removes installed versions but does not edit mise.toml. Use `mise unuse` to
remove a tool from mise.toml and uninstall it. A tool name or version prefix,
such as `node` or `node@22`, must match exactly one installed version unless
you pass `--all`.
"""#'
@usage 'flag "-a --all" help="Remove every installed version of the named tools, or of every tool when none is named"'
@usage 'flag "-n --dry-run" help="Show what would change without changing anything"'
@usage 'flag --dry-run-code help="Like --dry-run, but exit with code 1 if there are tools to uninstall" {
        long_help #"""
Like --dry-run, but exit with code 1 if there are tools to uninstall

Use it in scripts that check whether tools need uninstalling.
"""#
    }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[INSTALLED_TOOL@VERSION]…" help="Tools to remove, such as node@22.0.0" required=#false var=#true required_unless=--all'
@usage 'example "mise uninstall node@22.0.0" help="Uninstall a specific version"'
@usage 'example "mise uninstall node" help="Uninstall node when exactly one version is installed"'
@usage 'example "mise uninstall --all node" help="Uninstall every installed version of node"'
export def "mise uninstall" [
    ...installed_tool_version: string@"nus complete",  # Tools to remove, such as node@22.0.0
    --cd (-C): path@"nus complete",                    # Run as if mise were started in DIR
    --env_ (-E): list<string>,                         # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                               # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                                    # Show what would change without changing anything
    --quiet (-q),                                      # Suppress non-error messages
    --verbose (-v): int,                               # Show extra output (use -vv for even more)
    --yes (-y),                                        # Answer yes to all confirmation prompts
    --raw,                                             # Connect tasks and install commands directly to the terminal
    --locked,                                          # Require download URLs from the lockfile when installing
    --silent,                                          # Suppress all task output and mise non-error messages
    --all (-a),                                        # Remove every installed version of the named tools, or of every tool when none is named
    --dry-run-code,                                    # Like --dry-run, but exit with code 1 if there are tools to uninstall
]: nothing -> string {
    ^mise uninstall ...(nus argv [...$installed_tool_version] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --all: $all
        --dry-run-code: $dry_run_code
    })
}

# Remove environment variables from mise.toml
#
# Edits the same file `mise set` writes: the lowest-precedence TOML file in the
# nearest config directory, or the global config when run in your home
# directory. Use `--global` or `--file` to pick another file.
@usage 'long_help #"""
Remove environment variables from mise.toml

Edits the same file `mise set` writes: the lowest-precedence TOML file in the
nearest config directory, or the global config when run in your home
directory. Use `--global` or `--file` to pick another file.
"""#'
@usage 'flag "-f --file --path" help="The TOML file to edit instead of the default target" {
        long_help #"""
The TOML file to edit instead of the default target

Can be a file or a directory. For a directory, mise uses the config file in it, or one named by MISE_DEFAULT_CONFIG_FILENAME (default `mise.toml`): https://mise.jdx.dev/configuration/settings.html#default_config_filename To move the global config file, set MISE_GLOBAL_CONFIG_FILE: https://mise.jdx.dev/configuration/settings.html#global_config_file
"""#
        arg <FILE>
    }'
@usage 'flag "-g --global" help="Use the global config file" overrides=--file'
@usage 'flag --override help="Use the global override file, `config.override.toml`" {
        long_help #"""
Use the global override file, `config.override.toml`

See https://mise.jdx.dev/configuration.html#override-file
"""#
        conflicts "--global" "--file"
    }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[ENV_KEY]…" help="Environment variables to remove, such as NODE_ENV" required=#false var=#true'
@usage 'example "mise unset NODE_ENV" help="Remove NODE_ENV from the project config"'
@usage 'example "mise unset -g NODE_ENV" help="Remove NODE_ENV from the global config"'
@usage 'complete file type=path'
export def "mise unset" [
    ...env_key: string@"nus complete",  # Environment variables to remove, such as NODE_ENV
    --cd (-C): path@"nus complete",     # Run as if mise were started in DIR
    --env_ (-E): list<string>,          # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                       # Suppress non-error messages
    --verbose (-v): int,                # Show extra output (use -vv for even more)
    --yes (-y),                         # Answer yes to all confirmation prompts
    --raw,                              # Connect tasks and install commands directly to the terminal
    --locked,                           # Require download URLs from the lockfile when installing
    --silent,                           # Suppress all task output and mise non-error messages
    --file (-f): path@"nus complete",   # The TOML file to edit instead of the default target
    --global (-g),                      # Use the global config file
    --override,                         # Use the global override file, `config.override.toml`
]: nothing -> string {
    ^mise unset ...(nus argv [...$env_key] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --file: $file
        --global: $global
        --override: $override
    })
}

# Remove explicit trust for a config
#
# mise asks again before loading the parts of the file that can run code. With
# no file, untrusts the nearest config in this directory or a parent. Same as
# `mise trust --untrust`.
@usage 'long_help #"""
Remove explicit trust for a config

mise asks again before loading the parts of the file that can run code. With
no file, untrusts the nearest config in this directory or a parent. Same as
`mise trust --untrust`.
"""#'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[CONFIG_FILE]" help="The config file to untrust" required=#false'
@usage 'example "mise untrust ~/src/app/mise.toml" help="Stop trusting a specific file"'
@usage 'complete config_file type=path'
export def "mise untrust" [
    config_file?: path@"nus complete",  # The config file to untrust
    --cd (-C): path@"nus complete",     # Run as if mise were started in DIR
    --env_ (-E): list<string>,          # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                       # Suppress non-error messages
    --verbose (-v): int,                # Show extra output (use -vv for even more)
    --yes (-y),                         # Answer yes to all confirmation prompts
    --raw,                              # Connect tasks and install commands directly to the terminal
    --locked,                           # Require download URLs from the lockfile when installing
    --silent,                           # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise untrust ...(nus argv [$config_file] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Remove tool requests from config files and prune unused installations
#
# Without `--path`, `--global`, or `--env`, mise edits the first loaded config
# that declares one of the tools; in your home directory it edits the global
# config. A version argument matches the configured request literally: to
# remove `node = "20"`, use `mise unuse node@20`, not the installed version it
# resolved to. Omit the version to remove every request for that tool from the
# selected file.
#
# The installed versions the arguments name are pruned only when no remaining
# tracked config or tool stub needs them; mise says which file keeps one. A tool
# named without a version has all of its unused versions pruned. Pass
# `--no-prune` to edit the config and keep the installations. To remove an
# installation without editing config, use `mise uninstall`.
@usage 'alias rm remove'
@usage 'long_help #"""
Remove tool requests from config files and prune unused installations

Without `--path`, `--global`, or `--env`, mise edits the first loaded config
that declares one of the tools; in your home directory it edits the global
config. A version argument matches the configured request literally: to
remove `node = "20"`, use `mise unuse node@20`, not the installed version it
resolved to. Omit the version to remove every request for that tool from the
selected file.

The installed versions the arguments name are pruned only when no remaining
tracked config or tool stub needs them; mise says which file keeps one. A tool
named without a version has all of its unused versions pruned. Pass
`--no-prune` to edit the config and keep the installations. To remove an
installation without editing config, use `mise uninstall`.
"""#'
@usage 'flag "-e --env" help="Edit mise.<ENV>.toml in the current directory, or .mise.<ENV>.toml if that exists" {
        long_help #"""
Edit mise.<ENV>.toml in the current directory, or .mise.<ENV>.toml if that exists

Not the same as the global -E, which only chooses which config files are loaded.
"""#
        overrides "--global" "--path"
        arg <ENV>
    }'
@usage 'flag "-g --global" help="Use the global config file (`~/.config/mise/config.toml`) instead of the local one" {
        overrides "--path" "--env"
    }'
@usage 'flag "-p --path --file" help="Edit this config file, or the config file in this directory" {
        overrides "--global" "--env"
        arg <PATH>
    }'
@usage 'flag --override help="Write to the global override file, `config.override.toml`" {
        long_help #"""
Write to the global override file, `config.override.toml`

The override file outranks all project config. With `--env`, writes `config.<ENV>.override.toml` instead. See https://mise.jdx.dev/configuration.html#override-file
"""#
        conflicts "--global" "--path"
    }'
@usage 'flag --no-prune help="Do not also prune the installed version"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <INSTALLED_TOOL@VERSION>… help="Tools to remove from the config, with the version written as in the config" var=#true'
@usage 'example "mise unuse node@22.0.0" help="Remove node@22.0.0 from mise.toml and uninstall it if nothing else uses it"'
@usage 'example "mise unuse -g node@22.0.0" help="Remove it from the global config instead"'
@usage 'example "mise unuse --env staging node@20" help="Remove the node@20 request from mise.staging.toml"'
@usage 'complete path type=path'
export def "mise unuse" [
    ...installed_tool_version: string@"nus complete",  # Tools to remove from the config, with the version written as in the config
    --cd (-C): path@"nus complete",                    # Run as if mise were started in DIR
    --env_ (-E): list<string>,                         # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                               # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                                      # Suppress non-error messages
    --verbose (-v): int,                               # Show extra output (use -vv for even more)
    --yes (-y),                                        # Answer yes to all confirmation prompts
    --raw,                                             # Connect tasks and install commands directly to the terminal
    --locked,                                          # Require download URLs from the lockfile when installing
    --silent,                                          # Suppress all task output and mise non-error messages
    --global (-g),                                     # Use the global config file (`~/.config/mise/config.toml`) instead of the local one
    --path (-p): path@"nus complete",                  # Edit this config file, or the config file in this directory
    --override,                                        # Write to the global override file, `config.override.toml`
    --no-prune,                                        # Do not also prune the installed version
]: nothing -> string {
    ^mise unuse ...(nus argv [...$installed_tool_version] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --global: $global
        --path: $path
        --override: $override
        --no-prune: $no_prune
    })
}

# Upgrade outdated tools
#
# By default, keeps the range in mise.toml: with `node = "20"`, it installs the
# newest 20.x release. Use `--bump` to upgrade to the newest release overall
# and update the version in mise.toml. Also updates mise.lock when lockfiles
# are enabled; see https://mise.jdx.dev/dev-tools/mise-lock.html
#
# The version you upgraded from is removed after the `upgrade.prune_after`
# setting's grace period unless a tracked config or tool stub still uses it.
# Pass `--prune` to remove it now or `--no-prune` to keep it.
@usage 'alias up'
@usage r#'long_help #"""
Upgrade outdated tools

By default, keeps the range in mise.toml: with `node = "20"`, it installs the
newest 20.x release. Use `--bump` to upgrade to the newest release overall
and update the version in mise.toml. Also updates mise.lock when lockfiles
are enabled; see https://mise.jdx.dev/dev-tools/mise-lock.html

The version you upgraded from is removed after the `upgrade.prune_after`
setting's grace period unless a tracked config or tool stub still uses it.
Pass `--prune` to remove it now or `--no-prune` to keep it.
"""#'#
@usage 'after_long_help "\u{1b}[1m\u{1b}[4mDeprecation:\u{1b}[22m\u{1b}[24m\n\nThe `-l` shorthand for `--bump` is deprecated and will be removed in mise 2027.8.5.\nAfter removal, `-l` will become shorthand for `--local`. Use `-b` or `--bump` instead."'
@usage 'flag "-b --bump" help="Upgrade past the configured range to the newest release, and update the config to match" {
        long_help #"""
Upgrade past the configured range to the newest release, and update the config to match

The config keeps its precision: `node = "20"` becomes `node = "22"`, and `node = "20.0.0"` becomes `node = "22.1.0"`. If you name a version on the command line (`node@latest`, `node@3`, or `node@prefix:3`), that request is written instead; `mise upgrade node@latest --bump` writes `latest`. With the `pin` setting on, a version request such as `node@3` is written as the version it resolved to, and a bare `mise upgrade --bump` writes the resolved version for every request that is not exact, such as `latest` or `20`. Requests that do not come from a config file mise can write, such as `MISE_NODE_VERSION`, are upgraded but not written.
"""#
    }'
@usage r#'flag --pin help="With --bump, write the resolved version instead of keeping the request's precision" requires=--bump {
        long_help #"""
With --bump, write the resolved version instead of keeping the request's precision

`node = "latest"` and `node = "20"` become `node = "24.14.0"`. A named request such as `node@3` is written as the version it resolved to. Make this the default with the `pin` setting (`MISE_PIN=1`).
"""#
    }'#
@usage 'flag "-i --interactive" help="Choose which tools to upgrade from a multiselect menu" conflicts=INSTALLED_TOOL@VERSION'
@usage 'flag "-j --jobs" help="Number of jobs to run in parallel (default: the `jobs` setting)" env=MISE_JOBS {
        arg <JOBS>
    }'
@usage 'flag -l help="Deprecated shorthand for --bump" hide=#true'
@usage 'flag "-n --dry-run" help="Show what would change without changing anything"'
@usage 'flag "-x --exclude" help="Tools to exclude from upgrading, such as go python" var=#true {
        arg <INSTALLED_TOOL>
    }'
@usage 'flag --dry-run-code help="Like --dry-run, but exit with code 1 if there are outdated tools" {
        long_help #"""
Like --dry-run, but exit with code 1 if there are outdated tools

Use it in scripts that check whether tools need upgrading.
"""#
    }'
@usage 'flag --inactive help="Also upgrade installed tools that the current config does not request" conflicts=--local'
@usage 'flag --global help="Only upgrade tools defined in the global config" {
        long_help #"""
Only upgrade tools defined in the global config

Upgrades the requests in the global and system config (~/.config/mise/config.toml, /etc/mise/config.toml), even where a project config or a `MISE_<TOOL>_VERSION` environment variable sets its own version of the tool. It runs as if from outside any project, so project config, lockfiles, and `[env]` are neither read nor changed. Tools that update themselves, such as coding agents, run this instead of their own updater; see https://mise.jdx.dev/dev-tools/self-updating-tools.html
"""#
        conflicts "--local" "--inactive"
    }'
@usage 'flag --local help="Only upgrade tools defined in project config files" {
        long_help #"""
Only upgrade tools defined in project config files

Skips tools defined in the global config (~/.config/mise/config.toml) and tools set through `MISE_<TOOL>_VERSION` environment variables.
"""#
    }'
@usage 'flag --minimum-release-age help="Only upgrade to versions released before this date or older than this duration" {
        alias "--before" hide=#true
        long_help #"""
Only upgrade to versions released before this date or older than this duration

Supports absolute dates such as "2024-06-01" and relative durations such as "90d" or "1y".

Applies only to requests that can match several versions, such as "20" or "latest". Exact versions such as "22.5.0" are not filtered.
"""#
        arg <MINIMUM_RELEASE_AGE>
    }'
@usage 'flag --monorepo help="Placeholder for future monorepo upgrades; `mise upgrade --monorepo` is not implemented yet." hide=#true'
@usage 'flag --no-prune help="Do not uninstall the versions that were upgraded away from" overrides=--prune {
        long_help #"""
Do not uninstall the versions that were upgraded away from

The old version is left in place and is not scheduled for removal. Use this when something outside mise points at the install directory.

Set `upgrade.auto_prune = false` to make this the default.
"""#
    }'
@usage 'flag --prune help="Immediately uninstall the versions that were upgraded away from" overrides=--no-prune {
        long_help #"""
Immediately uninstall the versions that were upgraded away from

Use this to bypass `upgrade.prune_after`, or to override `upgrade.auto_prune = false` for a single run.
"""#
    }'
@usage r#'flag --raw help="Connect the install commands' stdin, stdout, and stderr to the terminal" overrides=--jobs {
        long_help #"""
Connect the install commands' stdin, stdout, and stderr to the terminal

Implies `--jobs=1`.
"""#
    }'#
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[INSTALLED_TOOL@VERSION]…" help="Tools to upgrade, such as node@20 python@3.10" help_long=#"""
Tools to upgrade, such as node@20 python@3.10

Upgrades every configured tool when omitted.
"""# required=#false var=#true'
@usage 'example "mise upgrade" help="Upgrade every configured tool within its range"'
@usage 'example "mise upgrade node" help="Upgrade only node"'
@usage 'example "mise upgrade --bump" help="Upgrade every tool to its newest release and update mise.toml"'
@usage 'example "mise upgrade --dry-run" help="Show what would be upgraded"'
@usage 'example "mise upgrade --exclude go" help="Upgrade everything except go"'
@usage 'example "mise upgrade --interactive" help="Choose tools from a menu"'
@usage r#'example "mise upgrade --global claude" help="Upgrade claude within the global config's request, leaving project config alone"'#
export def "mise upgrade" [
    ...installed_tool_version: string@"nus complete",  # Tools to upgrade, such as node@20 python@3.10
    --cd (-C): path@"nus complete",                    # Run as if mise were started in DIR
    --env_ (-E): list<string>,                         # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                               # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                                    # Show what would change without changing anything
    --quiet (-q),                                      # Suppress non-error messages
    --verbose (-v): int,                               # Show extra output (use -vv for even more)
    --yes (-y),                                        # Answer yes to all confirmation prompts
    --raw,                                             # Connect tasks and install commands directly to the terminal
    --locked,                                          # Require download URLs from the lockfile when installing
    --silent,                                          # Suppress all task output and mise non-error messages
    --bump (-b),                                       # Upgrade past the configured range to the newest release, and update the config to match
    --pin,                                             # With --bump, write the resolved version instead of keeping the request's precision
    --interactive (-i),                                # Choose which tools to upgrade from a multiselect menu
    --exclude (-x): list<string>@"nus complete",       # Tools to exclude from upgrading, such as go python
    --dry-run-code,                                    # Like --dry-run, but exit with code 1 if there are outdated tools
    --inactive,                                        # Also upgrade installed tools that the current config does not request
    --global,                                          # Only upgrade tools defined in the global config
    --local,                                           # Only upgrade tools defined in project config files
    --minimum-release-age: string,                     # Only upgrade to versions released before this date or older than this duration
    --no-prune,                                        # Do not uninstall the versions that were upgraded away from
    --prune,                                           # Immediately uninstall the versions that were upgraded away from
]: nothing -> string {
    ^mise upgrade ...(nus argv [...$installed_tool_version] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --bump: $bump
        --pin: $pin
        --interactive: $interactive
        --exclude: $exclude
        --dry-run-code: $dry_run_code
        --inactive: $inactive
        --global: $global
        --local: $local
        --minimum-release-age: $minimum_release_age
        --no-prune: $no_prune
        --prune: $prune
    })
}

# Install a tool and add it to configuration
#
# Installs missing tool versions and records the requests in a config file.
# By default, mise selects the nearest directory with a supported config and
# writes to its lowest-precedence file, such as `mise.toml` rather than
# `mise.local.toml`. If no project config exists, it creates one in the current
# directory. Run from your home directory, it writes to the global config.
#
# Use `--path` for an explicit file or directory, `--global` for personal
# defaults, or `--env` to write `mise.ENV.toml` in the current directory (an
# existing `.mise.ENV.toml` is used instead). If you pass more than one, the
# last one wins.
#
# See https://mise.jdx.dev/configuration.html#target-file-for-write-operations
# for filename overrides and config precedence. The change takes effect in an
# activated shell at its next prompt, and immediately in `mise exec` commands.
@usage 'alias u'
@usage 'long_help #"""
Install a tool and add it to configuration

Installs missing tool versions and records the requests in a config file.
By default, mise selects the nearest directory with a supported config and
writes to its lowest-precedence file, such as `mise.toml` rather than
`mise.local.toml`. If no project config exists, it creates one in the current
directory. Run from your home directory, it writes to the global config.

Use `--path` for an explicit file or directory, `--global` for personal
defaults, or `--env` to write `mise.ENV.toml` in the current directory (an
existing `.mise.ENV.toml` is used instead). If you pass more than one, the
last one wins.

See https://mise.jdx.dev/configuration.html#target-file-for-write-operations
for filename overrides and config precedence. The change takes effect in an
activated shell at its next prompt, and immediately in `mise exec` commands.
"""#'
@usage 'flag "-e --env" help="Write mise.<ENV>.toml in the current directory, or .mise.<ENV>.toml if that exists" {
        long_help #"""
Write mise.<ENV>.toml in the current directory, or .mise.<ENV>.toml if that exists

Not the same as the global -E, which only chooses which config files are loaded.
"""#
        overrides "--global" "--path"
        arg <ENV>
    }'
@usage 'flag "-f --force" help="Reinstall even if already installed" requires=TOOL@VERSION'
@usage 'flag "-g --global" help="Write to the global config instead of the project config" {
        long_help #"""
Write to the global config instead of the project config

Updates the global config file that already declares the tool, otherwise the file set by the `write_targets.tools` setting, otherwise ~/.config/mise/config.toml.
"""#
        overrides "--path" "--env"
    }'
@usage 'flag "-j --jobs" help="Number of jobs to run in parallel (default: the `jobs` setting)" env=MISE_JOBS {
        arg <JOBS>
    }'
@usage 'flag "-n --dry-run" help="Show what would change without changing anything"'
@usage 'flag "-p --path" help="Write to this config file, or to the config file in this directory" {
        long_help #"""
Write to this config file, or to the config file in this directory

For a directory, mise picks the file by the usual write-target rules.
"""#
        overrides "--global" "--env"
        arg <PATH>
    }'
@usage 'flag --override help="Write to the global override file, `config.override.toml`" {
        long_help #"""
Write to the global override file, `config.override.toml`

The override file outranks all project config. With `--env`, writes `config.<ENV>.override.toml` instead. See https://mise.jdx.dev/configuration.html#override-file
"""#
        conflicts "--global" "--path"
    }'
@usage 'flag --dry-run-code help="Like --dry-run, but exit with code 1 if there are changes to make" {
        long_help #"""
Like --dry-run, but exit with code 1 if there are changes to make

Use it in scripts that check whether tools need to be added or removed.
"""#
    }'
@usage 'flag --fuzzy help="Write the version as requested, such as `20` for node@20" overrides=--pin {
        long_help #"""
Write the version as requested, such as `20` for node@20

This is the default unless the `pin` setting is on.
"""#
    }'
@usage 'flag --minimum-release-age help="Only install versions released before this date or older than this duration" {
        alias "--before" hide=#true
        long_help #"""
Only install versions released before this date or older than this duration

Supports absolute dates such as "2024-06-01" and relative durations such as "90d" or "1y".
"""#
        arg <MINIMUM_RELEASE_AGE>
    }'
@usage 'flag --pin help="Write the resolved version, such as `20.19.5` for node@20" overrides=--fuzzy {
        long_help #"""
Write the resolved version, such as `20.19.5` for node@20

If the request exactly matches an available release, mise uses that release rather than an installed version that only matches it as a prefix. Write `prefix:` before the version, as in `node@prefix:20`, to force prefix matching. Make this the default with the `pin` setting (`MISE_PIN=1`).

To record exact versions without editing mise.toml, use a lockfile: https://mise.jdx.dev/dev-tools/mise-lock.html
"""#
    }'
@usage r#'flag --raw help="Connect the install commands' stdin, stdout, and stderr to the terminal" overrides=--jobs {
        long_help #"""
Connect the install commands' stdin, stdout, and stderr to the terminal

Implies `--jobs=1`.
"""#
    }'#
@usage 'flag --remove help="Remove these tools from the config file" var=#true {
        alias "--rm" "--unset" hide=#true
        arg <TOOL>
    }'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'clause tools {
        flag --postinstall help="Command to run after installing this tool" {
            arg <COMMAND>
        }
        flag --tool-option help="Set an option for the tool that follows; repeat for several options" var=#true {
            long_help #"""
Set an option for the tool that follows; repeat for several options

Values use inline tool-option types; unquoted text is a string. Put these flags before the tool they apply to.
"""#
            arg "<KEY=VALUE>"
        }
        arg <TOOL@VERSION> help="Tool to add to the config file, such as node@24, cargo:ripgrep@latest, or npm:prettier@3" help_long=#"""
Tool to add to the config file, such as node@24, cargo:ripgrep@latest, or npm:prettier@3

Without a version, mise requests `latest` but reuses the newest installed version.
Write `@latest` to install the newest release; in locked mode the lockfile still decides.
With --pin it writes the resolved version.
Tool options can also be set inline:

    mise use "cargo:ripgrep[features=pcre2]"
"""#
    }'
@usage 'example "mise use" help="Choose tools from an interactive selector"'
@usage 'example "mise use node@24" help="Use node 24.x in the project config and record the request `24`"'
@usage 'example "mise use --postinstall \"mbx setup --defaults\" mr-boxington" help="Run a command after installing a tool"'
@usage 'example "mise use --postinstall \"corepack enable\" node@24 --postinstall \"python -m pip install -U pip\" python@3.13" help="Give each tool its own postinstall command"'
@usage 'example "mise use --tool-option mr_boxington=true rust mr-boxington" help="Enable a Rust tool option while installing Rust and mbx"'
@usage 'example "mise use -g --pin node@24" help="Use node 24.x globally and record the exact version it resolves to"'
@usage 'example "mise use --env local node@24" help="Write mise.local.toml (an existing .mise.local.toml is used instead)"'
@usage 'example "mise use --env staging node@24" help="Write mise.staging.toml, which mise loads when MISE_ENV=staging"'
@usage 'complete path type=path'
export def "mise use" [
    ...tool_version: string@"nus complete",  # Tool to add to the config file, such as node@24, cargo:ripgrep@latest, or npm:prettier@3
    --cd (-C): path@"nus complete",          # Run as if mise were started in DIR
    --env_ (-E): list<string>,               # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --force (-f),                            # Reinstall even if already installed
    --jobs (-j): string,                     # How many jobs to run in parallel; defaults to the `jobs` setting
    --dry-run (-n),                          # Show what would change without changing anything
    --quiet (-q),                            # Suppress non-error messages
    --verbose (-v): int,                     # Show extra output (use -vv for even more)
    --yes (-y),                              # Answer yes to all confirmation prompts
    --raw,                                   # Connect tasks and install commands directly to the terminal
    --locked,                                # Require download URLs from the lockfile when installing
    --silent,                                # Suppress all task output and mise non-error messages
    --global (-g),                           # Write to the global config instead of the project config
    --path (-p): path@"nus complete",        # Write to this config file, or to the config file in this directory
    --override,                              # Write to the global override file, `config.override.toml`
    --dry-run-code,                          # Like --dry-run, but exit with code 1 if there are changes to make
    --fuzzy,                                 # Write the version as requested, such as `20` for node@20
    --minimum-release-age: string,           # Only install versions released before this date or older than this duration
    --pin,                                   # Write the resolved version, such as `20.19.5` for node@20
    --remove: list<string>@"nus complete",   # Remove these tools from the config file
    --postinstall: string,                   # Command to run after installing this tool
    --tool-option: list<string>,             # Set an option for the tool that follows; repeat for several options
]: nothing -> string {
    ^mise use ...(nus argv [...$tool_version] {
        --cd: $cd
        --env: $env_
        --force: $force
        --jobs: $jobs
        --dry-run: $dry_run
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --global: $global
        --path: $path
        --override: $override
        --dry-run-code: $dry_run_code
        --fuzzy: $fuzzy
        --minimum-release-age: $minimum_release_age
        --pin: $pin
        --remove: $remove
    } {--postinstall: $postinstall, --tool-option: $tool_option})
}

# List, set, and ask for config vars
#
# Like `mise set`: with no arguments, lists every var and where it comes from;
# `mise vars NAME=VALUE` saves a value on this machine and `mise vars NAME`
# prints one. Saved values live in `$MISE_STATE_DIR/vars.toml`, outside every
# config file, and sit above a var's `default` but below any value a config
# file sets. `mise vars prompt` asks for the `[vars]` that declare a `prompt`;
# only it and `mise bootstrap --prompt-vars` ever ask.
# See https://mise.jdx.dev/configuration/vars.html#prompt
@usage r#'long_help #"""
List, set, and ask for config vars

Like `mise set`: with no arguments, lists every var and where it comes from;
`mise vars NAME=VALUE` saves a value on this machine and `mise vars NAME`
prints one. Saved values live in `$MISE_STATE_DIR/vars.toml`, outside every
config file, and sit above a var's `default` but below any value a config
file sets. `mise vars prompt` asks for the `[vars]` that declare a `prompt`;
only it and `mise bootstrap --prompt-vars` ever ask.
See https://mise.jdx.dev/configuration/vars.html#prompt
"""#'#
@usage 'flag --no-header help="Do not print the table header"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[NAME[=VALUE]]…" help="Values to save (`NAME=VALUE`) or to print (`NAME`)" required=#false var=#true'
@usage 'example "mise vars git_name=\"Ada Lovelace\"" help="Save a value on this machine without asking"'
@usage 'example "mise vars git_name" help="Print the saved value of git_name"'
@usage 'example "mise vars" help="List every var and its source"'
export def "mise vars" [
    ...name_value: string,           # Values to save (`NAME=VALUE`) or to print (`NAME`)
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --no-header,                     # Do not print the table header
]: nothing -> string {
    ^mise vars ...(nus argv [...$name_value] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --no-header: $no_header
    })
}

# List every var, with the file it comes from
#
# Lists the `[vars]` of every config file mise loads here, plus the answers
# saved on this machine (source: `$MISE_STATE_DIR/vars.toml`). Values hidden
# with `redact` show as `[redacted]`. A `required` var that is still unset only
# warns here.
@usage 'alias list'
@usage 'long_help #"""
List every var, with the file it comes from

Lists the `[vars]` of every config file mise loads here, plus the answers
saved on this machine (source: `$MISE_STATE_DIR/vars.toml`). Values hidden
with `redact` show as `[redacted]`. A `required` var that is still unset only
warns here.
"""#'
@usage 'flag --no-header help="Do not print the table header"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
export def "mise vars ls" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
    --no-header,                     # Do not print the table header
]: nothing -> string {
    ^mise vars ls ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --no-header: $no_header
    })
}

# Ask for the prompt vars that have no saved answer, or set answers directly
#
# Enter accepts the suggested default. Each answer, accepted defaults
# included, is saved and never asked for again; use `mise vars unset` to be
# asked again. With no arguments, asks about every unanswered `prompt` var in
# the config files that apply here. `NAME` asks for only that var;
# `NAME=VALUE` saves the answer without asking, as `mise set` does for an
# env var, so it needs no terminal.
@usage 'long_help #"""
Ask for the prompt vars that have no saved answer, or set answers directly

Enter accepts the suggested default. Each answer, accepted defaults
included, is saved and never asked for again; use `mise vars unset` to be
asked again. With no arguments, asks about every unanswered `prompt` var in
the config files that apply here. `NAME` asks for only that var;
`NAME=VALUE` saves the answer without asking, as `mise set` does for an
env var, so it needs no terminal.
"""#'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[NAME[=VALUE]]…" help="Vars to ask for (`NAME`) or answers to save (`NAME=VALUE`)" required=#false var=#true'
@usage 'example "mise vars prompt" help="Ask for every unanswered prompt var"'
@usage 'example "mise vars prompt git_name" help="Ask for git_name only"'
@usage 'example "mise vars prompt git_name=\"Ada Lovelace\"" help="Set the answer for git_name without asking"'
export def "mise vars prompt" [
    ...name_value: string,           # Vars to ask for (`NAME`) or answers to save (`NAME=VALUE`)
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise vars prompt ...(nus argv [...$name_value] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Forget saved answers so they are asked for again
#
# Edits `$MISE_STATE_DIR/vars.toml`; no config is loaded. The next
# `mise vars prompt` or `mise bootstrap --prompt-vars` asks again.
@usage 'alias rm remove'
@usage 'long_help #"""
Forget saved answers so they are asked for again

Edits `$MISE_STATE_DIR/vars.toml`; no config is loaded. The next
`mise vars prompt` or `mise bootstrap --prompt-vars` asks again.
"""#'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[NAME]…" help="The vars whose answers to forget" required=#false var=#true'
@usage 'example "mise vars unset git_name" help="Be asked for git_name again"'
export def "mise vars unset" [
    ...name: string,                 # The vars whose answers to forget
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise vars unset ...(nus argv [...$name] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Show the version of mise
#
# Prints the version, OS, architecture, and build date, and warns when a newer
# release is available. `mise --version`, `mise -V`, and `mise -v` with no
# other arguments print the same line.
@usage 'alias v'
@usage 'long_help #"""
Show the version of mise

Prints the version, OS, architecture, and build date, and warns when a newer
release is available. `mise --version`, `mise -V`, and `mise -v` with no
other arguments print the same line.
"""#'
@usage 'flag "-J --json" help="Print the version information in JSON format"'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'example #"""
mise version
2026.10.4 linux-x64 (2026-10-07)
"""# help="Show the version"'
@usage 'example "mise version --json" help="Also show the latest release and the build time, as JSON"'
@usage 'output "json" framing="json" select="--json" {
    schema "{\n  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",\n  \"type\": \"object\",\n  \"properties\": {\n    \"version\": {\n      \"type\": \"string\"\n    },\n    \"latest\": {\n      \"type\": [\n        \"string\",\n        \"null\"\n      ]\n    },\n    \"os\": {\n      \"type\": \"string\"\n    },\n    \"arch\": {\n      \"type\": \"string\"\n    },\n    \"build_time\": {\n      \"type\": \"string\"\n    }\n  },\n  \"required\": [\n    \"version\",\n    \"latest\",\n    \"os\",\n    \"arch\",\n    \"build_time\"\n  ],\n  \"additionalProperties\": false\n}\n"
}'
export def "mise version" [
    --cd (-C): path@"nus complete",  # Run as if mise were started in DIR
    --env_ (-E): list<string>,       # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,             # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                    # Suppress non-error messages
    --verbose (-v): int,             # Show extra output (use -vv for even more)
    --yes (-y),                      # Answer yes to all confirmation prompts
    --raw,                           # Connect tasks and install commands directly to the terminal
    --locked,                        # Require download URLs from the lockfile when installing
    --silent,                        # Suppress all task output and mise non-error messages
]: nothing -> record<version: string, latest: oneof<string, nothing>, os: string, arch: string, build_time: string> {
    let text = ^mise version --json ...(nus argv [] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
    nus decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":\"object\",\"properties\":{\"version\":{\"type\":\"string\"},\"latest\":{\"type\":[\"string\",\"null\"]},\"os\":{\"type\":\"string\"},\"arch\":{\"type\":\"string\"},\"build_time\":{\"type\":\"string\"}},\"required\":[\"version\",\"latest\",\"os\",\"arch\",\"build_time\"],\"additionalProperties\":false}" { from json }
}

# Run tasks and rerun them when files change
#
# Runs the tasks with `mise run` under watchexec, then reruns them whenever one of their `sources` changes, including the sources of their dependencies unless you pass `--skip-deps`. When no selected task declares `sources`, watchexec watches the current directory. With no task, runs the `default` task.
#
# Choose what to watch with `--watch`, `--exts`, and `--filter`, and use `--print-events` to see what triggered a run. Arguments for the task go after `--`. Requires watchexec, which `mise use -g watchexec` installs.
#
# To keep a server or database running alongside your tasks, with readiness checks and automatic restarts, see `mise daemons` (experimental): https://mise.jdx.dev/daemons.html. For cron scheduling and standalone process management, see pitchfork: https://pitchfork.jdx.dev
@usage 'alias w'
@usage 'long_help #"""
Run tasks and rerun them when files change

Runs the tasks with `mise run` under watchexec, then reruns them whenever one of their `sources` changes, including the sources of their dependencies unless you pass `--skip-deps`. When no selected task declares `sources`, watchexec watches the current directory. With no task, runs the `default` task.

Choose what to watch with `--watch`, `--exts`, and `--filter`, and use `--print-events` to see what triggered a run. Arguments for the task go after `--`. Requires watchexec, which `mise use -g watchexec` installs.

To keep a server or database running alongside your tasks, with readiness checks and automatic restarts, see `mise daemons` (experimental): https://mise.jdx.dev/daemons.html. For cron scheduling and standalone process management, see pitchfork: https://pitchfork.jdx.dev
"""#'
@usage 'flag "-t --task-flag" help="Tasks to run" var=#true hide=#true {
        arg <TASK_FLAG>
    }'
@usage r#'flag "-g --glob" help="Globs to watch instead of the tasks' sources" var=#true {
        arg <GLOB>
    }'#
@usage 'flag --skip-deps help="Run and watch only the named tasks, not the tasks they depend on"'
@usage r#'flag "-w --watch" help="Watch a file or directory" var=#true help_heading=Filtering {
        long_help #"""
Watch a file or directory

By default, mise watches each task's directory and any source directory outside it, and filters events to the tasks' `sources`. When no task declares sources, watchexec watches the current directory. Paths given here are added to the task directories, or replace the current-directory default when there are no sources. Events are still filtered to the sources, so use `--filter` to widen what triggers a rerun.

To watch a single file, watch its directory and filter on the file name instead: some editors replace a file when they save it, and some platforms do not report changes to the replacement. Repeat the flag to watch several paths.
"""#
        arg <PATH>
    }'#
@usage 'flag "-W --watch-non-recursive" help="Watch a directory without recursing into it" var=#true help_heading=Filtering {
        long_help #"""
Watch a directory without recursing into it

Repeat the flag to watch several directories.
"""#
        arg <PATH>
    }'
@usage 'flag "-F --watch-file" help="Read paths to watch from a file, one per line" help_heading=Filtering {
        long_help #"""
Read paths to watch from a file, one per line

Each line is treated like a `--watch` value. The value `-` reads from stdin and cannot be combined with `--stdin-quit`.
"""#
        arg <PATH>
    }'
@usage 'flag "-c --clear" help="Clear the screen before each run" value_optional=#true default_missing=clear help_heading=Output {
        long_help #"""
Clear the screen before each run

If the default `clear` mode leaves output behind, use `--clear=reset`. Because the mode is optional, `mise watch --clear build` reads `build` as the mode: put `--clear` after the task name, as in `mise watch build --clear`, or write the mode with `=`.
"""#
        arg "[MODE]" required=#false var_min=0 var_max=1 {
            choices {
                choice clear
                choice reset
            }
        }
    }'
@usage 'flag "-o --on-busy-update" help="What to do when files change while the tasks are running" hide_default_value=#true default=do-nothing {
        long_help #"""
What to do when files change while the tasks are running

`do-nothing` (the default) ignores the change, so files the tasks write do not trigger another run. `queue` runs the tasks again when the current run finishes. `restart` stops the running tasks and starts them again. `signal` sends the `--signal` signal and keeps the tasks running, for programs that reload their configuration on a signal.
"""#
        arg <MODE> {
            choices {
                choice queue
                choice do-nothing
                choice restart
                choice signal
            }
        }
    }'
@usage 'flag "-r --restart" help="Restart the tasks if they are still running when files change" conflicts=--on-busy-update {
        long_help #"""
Restart the tasks if they are still running when files change

Same as `--on-busy-update=restart`.
"""#
    }'
@usage 'flag "-s --signal" help="Signal to send to the running tasks when files change" conflicts=--restart {
        long_help #"""
Signal to send to the running tasks when files change

Implies `--on-busy-update=signal`. Accepts the same forms as `--stop-signal`. Signals are not supported on Windows, where the tasks are always killed.
"""#
        arg <SIGNAL>
    }'
@usage 'flag --stop-signal help="Signal that stops the tasks before a restart (default on Unix: SIGTERM)" {
        long_help #"""
Signal that stops the tasks before a restart (default on Unix: SIGTERM)

Used by the `restart` and `signal` modes of `--on-busy-update` unless `--signal` is given. Accepts a full name (`SIGTERM`), a short name (`TERM`), or a number (`15`), in any case. If the tasks have not exited after `--stop-timeout`, they are killed. On Windows the tasks are always killed.
"""#
        arg <SIGNAL>
    }'
@usage 'flag --stop-timeout help="How long to wait for the tasks to stop before killing them (default: 10s)" hide_default_value=#true default="10s" {
        long_help #"""
How long to wait for the tasks to stop before killing them (default: 10s)

Takes a duration such as `5s` or `1min 20s`. Set it to 0 to kill the tasks right away. Has no effect on Windows, where the tasks are always killed.
"""#
        arg <TIMEOUT>
    }'
@usage 'flag --map-signal help="Translate a signal that watchexec receives into one it sends to the tasks" var=#true {
        long_help #"""
Translate a signal that watchexec receives into one it sends to the tasks

Takes two signal names separated by a colon, such as `TERM:INT`. Leave out the second name to discard the first signal (`TERM:`). A mapped SIGINT or SIGTERM no longer stops watching; `INT:INT` passes Ctrl-C to the tasks without stopping watchexec. Repeat the flag to map several signals.
"""#
        arg <SIGNAL:SIGNAL>
    }'
@usage 'flag "-d --debounce" help="How long to wait for more changes before running (default: 50ms)" hide_default_value=#true default="50ms" {
        long_help #"""
How long to wait for more changes before running (default: 50ms)

One save can produce several events, and a file can be written in pieces, so watchexec waits this long after an event before running the tasks. Takes a duration such as `500ms` or `2s`.
"""#
        arg <TIMEOUT>
    }'
@usage 'flag --stdin-quit help="Exit when stdin closes"'
@usage 'flag --no-vcs-ignore help="Do not apply Git and other version control ignore files" help_heading=Filtering {
        long_help #"""
Do not apply Git and other version control ignore files

Use it to watch files that Git ignores. A task can turn this on for itself with `watch = { no_vcs_ignore = true }`.
"""#
    }'
@usage 'flag --no-project-ignore help="Do not apply ignore files in the project, such as `.gitignore` and `.ignore`" help_heading=Filtering'
@usage 'flag --no-global-ignore help="Do not apply global ignore files, such as `~/.gitignore` and `~/.config/watchexec/ignore`" help_heading=Filtering'
@usage r#'flag --no-default-ignore help="Do not apply watchexec's built-in ignores" help_heading=Filtering {
        long_help #"""
Do not apply watchexec's built-in ignores

They cover editor swap files, `*.pyc`, `.DS_Store`, and version control directories such as `.git`.
"""#
    }'#
@usage 'flag --no-discover-ignore help="Do not look for ignore files at all" help_heading=Filtering {
        long_help #"""
Do not look for ignore files at all

Same as `--no-global-ignore --no-vcs-ignore --no-project-ignore`, but faster. Built-in ignores still apply.
"""#
    }'
@usage 'flag --ignore-nothing help="Ignore nothing" help_heading=Filtering {
        long_help #"""
Ignore nothing

Same as `--no-discover-ignore --no-default-ignore`. Patterns from `--ignore` and `--ignore-file` still apply.
"""#
    }'
@usage 'flag "-p --postpone" help="Wait for the first change before running the tasks"'
@usage 'flag --delay-run help="Wait this long after a change before running the tasks, e.g. 5s" {
        arg <DURATION>
    }'
@usage 'flag --poll help="Poll for changes instead of using native file watching" value_optional=#true default_missing="30s" {
        alias "--force-poll" hide=#true
        long_help #"""
Poll for changes instead of using native file watching

Use it on file systems where native events do not work, such as network shares. Takes an optional interval such as `2s` (default: 30s). Also accepted as `--force-poll`.
"""#
        arg "[INTERVAL]" required=#false var_min=0 var_max=1
    }'
@usage r#'flag --shell help="Use a different shell" help_heading=Command {
        long_help #"""
Use a different shell

By default, Watchexec will use '$SHELL' if it's defined or a default of 'sh' on Unix-likes, and either 'pwsh', 'powershell', or 'cmd' (CMD.EXE) on Windows, depending on what Watchexec detects is the running shell.

With this option, you can override that and use a different shell, for example one with more features or one which has your custom aliases and functions.

If the value has spaces, it is parsed as a command line, and the first word used as the shell program, with the rest as arguments to the shell.

The command is run with the '-c' flag (except for 'cmd' on Windows, where it's '/C').

The special value 'none' can be used to disable shell use entirely. In that case, the command provided to Watchexec will be parsed, with the first word being the executable and the rest being the arguments, and executed directly. Note that this parsing is rudimentary, and may not work as expected in all cases.

Using 'none' is a little more efficient and can enable a stricter interpretation of the input, but it also means that you can't use shell features like globbing, redirection, control flow, logic, or pipes.

Examples:

Use without shell:

  $ watchexec -n -- zsh -x -o shwordsplit scr

Use with powershell core:

  $ watchexec --shell=pwsh -- Test-Connection localhost

Use with CMD.exe:

  $ watchexec --shell=cmd -- dir

Use with a different unix shell:

  $ watchexec --shell=bash -- 'echo $BASH_VERSION'

Use with a unix shell and options:

  $ watchexec --shell='zsh -x -o shwordsplit' -- scr
"""#
        arg <SHELL>
    }'#
@usage r#'flag -n help="Shorthand for '--shell=none'" help_heading=Command'#
@usage r#'flag --emit-events-to help="Configure event emission" hide_default_value=#true help_heading=Command default=none {
        long_help #"""
Configure event emission

Watchexec can emit event information when running a command, which can be used by the child
process to target specific changed files.

One thing to take care with is assuming inherent behaviour where there is only chance.
Notably, it could appear as if the `RENAMED` variable contains both the original and the new
path being renamed. In previous versions, it would even appear on some platforms as if the
original always came before the new. However, none of this was true. It's impossible to
reliably and portably know which changed path is the old or new, "half" renames may appear
(only the original, only the new), "unknown" renames may appear (change was a rename, but
whether it was the old or new isn't known), rename events might split across two debouncing
boundaries, and so on.

This option controls where that information is emitted. It defaults to 'none', which doesn't
emit event information at all. The other options are 'environment' (deprecated), 'stdio',
'file', 'json-stdio', and 'json-file'.

The 'stdio' and 'file' modes are text-based: 'stdio' writes absolute paths to the stdin of
the command, one per line, each prefixed with `create:`, `remove:`, `rename:`, `modify:`,
or `other:`, then closes the handle; 'file' writes the same thing to a temporary file, and
its path is given with the $WATCHEXEC_EVENTS_FILE environment variable.

There are also two JSON modes, which are based on JSON objects and can represent the full
set of events Watchexec handles. Here's an example of a folder being created on Linux:

```json
  {
    "tags": [
      {
        "kind": "path",
        "absolute": "/home/user/your/new-folder",
        "filetype": "dir"
      },
      {
        "kind": "fs",
        "simple": "create",
        "full": "Create(Folder)"
      },
      {
        "kind": "source",
        "source": "filesystem"
      }
    ],
    "metadata": {
      "notify-backend": "inotify"
    }
  }
```

The fields are as follows:

  - `tags`, structured event data.
  - `tags[].kind`, which can be:
    * 'path', along with:
      + `absolute`, an absolute path.
      + `filetype`, a file type if known ('dir', 'file', 'symlink', 'other').
    * 'fs':
      + `simple`, the "simple" event type ('access', 'create', 'modify', 'remove', or 'other').
      + `full`, the "full" event type, which is too complex to fully describe here, but looks like 'General(Precise(Specific))'.
    * 'source', along with:
      + `source`, the source of the event ('filesystem', 'keyboard', 'mouse', 'os', 'time', 'internal').
    * 'keyboard', along with:
      + `keycode`. Currently only the value 'eof' is supported.
    * 'process', for events caused by processes:
      + `pid`, the process ID.
    * 'signal', for signals sent to Watchexec:
      + `signal`, the normalised signal name ('hangup', 'interrupt', 'quit', 'terminate', 'user1', 'user2').
    * 'completion', for when a command ends:
      + `disposition`, the exit disposition ('success', 'error', 'signal', 'stop', 'exception', 'continued').
      + `code`, the exit, signal, stop, or exception code.
  - `metadata`, additional information about the event.

The 'json-stdio' mode will emit JSON events to the standard input of the command, one per
line, then close stdin. The 'json-file' mode will create a temporary file, write the
events to it, and provide the path to the file with the $WATCHEXEC_EVENTS_FILE
environment variable.

Finally, the 'environment' mode was the default until 2.0. It sets environment variables
with the paths of the affected files, for filesystem events:

$WATCHEXEC_COMMON_PATH is set to the longest common path of all of the below variables,
and so should be prepended to each path to obtain the full/real path. Then:

  - $WATCHEXEC_CREATED_PATH is set when files/folders were created
  - $WATCHEXEC_REMOVED_PATH is set when files/folders were removed
  - $WATCHEXEC_RENAMED_PATH is set when files/folders were renamed
  - $WATCHEXEC_WRITTEN_PATH is set when files/folders were modified
  - $WATCHEXEC_META_CHANGED_PATH is set when files/folders' metadata were modified
  - $WATCHEXEC_OTHERWISE_CHANGED_PATH is set for every other kind of pathed event

Multiple paths are separated by the system path separator, ';' on Windows and ':' on unix.
Within each variable, paths are deduplicated and sorted in binary order (i.e. neither
Unicode nor locale aware).

This is the legacy mode, is deprecated, and will be removed in the future. The environment
is a very restricted space, while also limited in what it can usefully represent. Large
numbers of files will either cause the environment to be truncated, or may error or crash
the process entirely. The $WATCHEXEC_COMMON_PATH is also unintuitive, as demonstrated by the
multiple confused queries that have landed in my inbox over the years.
"""#
        required_if_eq "--only-emit-events" "true"
        arg <MODE> {
            choices {
                choice environment
                choice stdio
                choice file
                choice json-stdio
                choice json-file
                choice none
            }
        }
    }'#
@usage 'flag --only-emit-events help="Only emit events to stdout, run no commands." conflicts=--manual help_heading=Output {
        long_help #"""
Only emit events to stdout, run no commands.

This is a convenience option for using Watchexec as a file watcher, without running any commands. It is almost equivalent to using `cat` as the command, except that it will not spawn a new process for each event.

This option requires `--emit-events-to` to be set, and restricts the available modes to `stdio` and `json-stdio`, modifying their behaviour to write to stdout instead of the stdin of the command.
"""#
    }'
@usage r#'flag --watchexec-env help="Add env vars to the command" var=#true help_heading=Command {
        long_help #"""
Add env vars to the command

This is a convenience option for setting environment variables for the command, without setting them for the Watchexec process itself.

Use key=value syntax. Multiple variables can be set by repeating the option.

This is watchexec's '--env'. In mise, '-E'/'--env' selects the mise environment (`mise.<ENV>.toml`), as it does for every other command.
"""#
        arg "<KEY=VALUE>"
    }'#
@usage 'flag --wrap-process help="How to wrap the task process: group, session, or none" help_heading=Command {
        long_help #"""
How to wrap the task process: group, session, or none

By default watchexec uses a session on macOS, a process group on other Unix systems, and a Job Object on Windows. Some programs need a session, and some do not work in a process group; `none` runs the command directly. On Windows, `group` and `session` both use a Job Object.
"""#
        arg <MODE> {
            choices {
                choice group
                choice session
                choice none
            }
        }
    }'
@usage 'flag "-N --notify" help="Alert when commands start and end" help_heading=Output {
        long_help #"""
Alert when commands start and end

With this, Watchexec will emit a desktop notification when a command starts and ends, on supported platforms. On unsupported platforms, it may silently do nothing, or log a warning.
"""#
    }'
@usage 'flag --color help="When to use terminal colours" help_heading=Output default=auto {
        alias "--colour" hide=#true
        long_help #"""
When to use terminal colours

Setting the environment variable `NO_COLOR` to any value is equivalent to `--color=never`.
"""#
        arg <MODE> {
            choices {
                choice auto
                choice always
                choice never
            }
        }
    }'
@usage 'flag --timings help="Print how long the command took to run" help_heading=Output {
        long_help #"""
Print how long the command took to run

This may not be exactly accurate, as it includes some overhead from Watchexec itself. Use the `time` utility, high-precision timers, or benchmarking tools for more accurate results.
"""#
    }'
@usage r#'flag --watchexec-quiet help="Don't print starting and stopping messages" help_heading=Output {
        long_help #"""
Don't print starting and stopping messages

By default Watchexec will print a message when the command starts and stops. This option disables this behaviour, so only the command's output, warnings, and errors will be printed.

This is watchexec's '--quiet'. In mise, '-q'/'--quiet' quiets mise's own messages, as it does for every other command.
"""#
    }'#
@usage 'flag --bell help="Ring the terminal bell on command completion" help_heading=Output'
@usage r#'flag --project-origin help="Set the project origin" {
        long_help #"""
Set the project origin

Watchexec will attempt to discover the project's "origin" (or "root") by searching for a variety of markers, like files or directory patterns. It does its best but sometimes gets it it wrong, and you can override that with this option.

The project origin is used to determine the path of certain ignore files, which VCS is being used, the meaning of a leading '/' in filtering patterns, and maybe more in the future.

When set, Watchexec will also not bother searching, which can be significantly faster.

The directory must contain every watched task's sources, which mise makes relative to it.
"""#
        arg <DIRECTORY>
    }'#
@usage 'flag --workdir help="Has no effect: mise runs each task from its own `dir`" hide=#true {
        long_help #"""
Has no effect: mise runs each task from its own `dir`

Accepted so scripts that pass it keep working. Forwarding it would make the nested `mise run` look for tasks in that directory instead of this project.
"""#
        arg <DIRECTORY>
    }'
@usage 'flag "-e --exts" help="Only react to files with these extensions, e.g. js,ts" var=#true help_heading=Filtering {
        long_help #"""
Only react to files with these extensions, e.g. js,ts

Give extensions with or without the leading dot. Repeat the flag or separate extensions with commas.
"""#
        arg <EXTENSIONS> delimiter=,
    }'
@usage r#'flag "-f --filter" help="Only react to files that match this glob" var=#true help_heading=Filtering {
        long_help #"""
Only react to files that match this glob

Combined with the patterns mise derives from the tasks' `sources`. Repeat the flag for more patterns. Events that do not come from files, such as signals, pass through.
"""#
        arg <PATTERN>
    }'#
@usage r##'flag --filter-file help="Files to load filters from" var=#true hide_env=#true env=WATCHEXEC_FILTER_FILES help_heading=Filtering {
        long_help #"""
Files to load filters from

Provide a path to a file containing filters, one per line. Empty lines and lines starting with '#' are ignored. Uses the same pattern format as the '--filter' option.

This can also be used via the $WATCHEXEC_FILTER_FILES environment variable.
"""#
        arg <PATH> delimiter=:
    }'##
@usage r#'flag "-J --filter-prog" help="[experimental] Filter programs." var=#true help_heading=Filtering {
        long_help #"""
[experimental] Filter programs.

/!\ This option is EXPERIMENTAL and may change and/or vanish without notice.

Provide your own custom filter programs in jaq (similar to jq) syntax. Programs are given
an event in the same format as described in '--emit-events-to' and must return a boolean.
Invalid programs will make watchexec fail to start; use '-v' to see program runtime errors.

In addition to the jaq stdlib, watchexec adds some custom filter definitions:

  - 'path | file_meta' returns file metadata or null if the file does not exist.

  - 'path | file_size' returns the size of the file at path, or null if it does not exist.

  - 'path | file_read(bytes)' returns a string with the first n bytes of the file at path.
    If the file is smaller than n bytes, the whole file is returned. There is no filter to
    read the whole file at once to encourage limiting the amount of data read and processed.

  - 'string | hash', and 'path | file_hash' return the hash of the string or file at path.
    No guarantee is made about the algorithm used: treat it as an opaque value.

  - 'any | kv_store(key)', 'kv_fetch(key)', and 'kv_clear' provide a simple key-value store.
    Data is kept in memory only, there is no persistence. Consistency is not guaranteed.

  - 'any | printout', 'any | printerr', and 'any | log(level)' will print or log any given
    value to stdout, stderr, or the log (levels = error, warn, info, debug, trace), and
    pass the value through (so '[1] | log("debug") | .[]' will produce a '1' and log '[1]').

All filtering done with such programs, and especially those using kv or filesystem access,
is much slower than the other filtering methods. If filtering is too slow, events will back
up and stall watchexec. Take care when designing your filters.

If the argument to this option starts with an '@', the rest of the argument is taken to be
the path to a file containing a jaq program.

Jaq programs are run in order, after all other filters, and short-circuit: if a filter (jaq
or not) rejects an event, execution stops there, and no other filters are run. Additionally,
they stop after outputting the first value, so you'll want to use 'any' or 'all' when
iterating, otherwise only the first item will be processed, which can be quite confusing!

Find user-contributed programs or submit your own useful ones at
<https://github.com/watchexec/watchexec/discussions/592>.

## Examples:

Regexp ignore filter on paths:

  'all(.tags[] | select(.kind == "path"); .absolute | test("[.]test[.]js$")) | not'

Pass any event that creates a file:

  'any(.tags[] | select(.kind == "fs"); .simple == "create")'

Pass events that touch executable files:

  'any(.tags[] | select(.kind == "path" and .filetype == "file"); .absolute | file_meta | .executable)'

Ignore files that start with shebangs:

  'any(.tags[] | select(.kind == "path" and .filetype == "file"); .absolute | file_read(2) == "#!") | not'
"""#
        arg <EXPRESSION>
    }'#
@usage 'flag "-i --ignore" help="Ignore files that match this glob" var=#true help_heading=Filtering {
        long_help #"""
Ignore files that match this glob

Repeat the flag for more patterns. Events that do not come from files, such as signals, pass through.
"""#
        arg <PATTERN>
    }'
@usage 'flag --ignore-file help="Read ignore patterns from a file, one per line" var=#true hide_env=#true env=WATCHEXEC_IGNORE_FILES help_heading=Filtering {
        long_help #"""
Read ignore patterns from a file, one per line

Empty lines and lines that start with `#` are skipped. The patterns use the same format as `--ignore`. Also read from `$WATCHEXEC_IGNORE_FILES`.
"""#
        arg <PATH> delimiter=:
    }'
@usage r#'flag --fs-events help="Filesystem events to filter to" var=#true hide_default_value=#true help_heading=Filtering default=create,remove,rename,modify,metadata {
        long_help #"""
Filesystem events to filter to

This is a quick filter to only emit events for the given types of filesystem changes. Choose from 'access', 'create', 'remove', 'rename', 'modify', 'metadata'. Multiple types can be given by repeating the option or by separating them with commas. By default, this is all types except for 'access'.

This may apply filtering at the kernel level when possible, which can be more efficient, but may be more confusing when reading the logs.
"""#
        arg <EVENTS> delimiter=, {
            choices {
                choice access
                choice create
                choice remove
                choice rename
                choice modify
                choice metadata
            }
        }
    }'#
@usage r#'flag --no-meta help="Don't emit fs events for metadata changes" conflicts=--fs-events help_heading=Filtering {
        long_help #"""
Don't emit fs events for metadata changes

This is a shorthand for '--fs-events create,remove,rename,modify'. Using it alongside the '--fs-events' option is non-sensical and not allowed.
"""#
    }'#
@usage r#'flag --print-events help="Print the events that trigger each run" help_heading=Debugging {
        long_help #"""
Print the events that trigger each run

Use it to check which files `--watch`, `--filter`, and the tasks' `sources` are reacting to.
"""#
    }'#
@usage r#'flag --manual help="Show the manual page" help_heading=Debugging {
        long_help #"""
Show the manual page

This shows the manual page for Watchexec, if the output is a terminal and the 'man' program is available. If not, the manual page is printed to stdout in ROFF format (suitable for writing to a watchexec.1 file).
"""#
    }'#
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[TASK]" help="Task to watch (default: `default`); separate several tasks with `:::`" required=#false'
@usage 'arg "[ARGS]…" help="Arguments for the task; `:::` starts the next task" required=#false double_dash=automatic var=#true'
@usage 'example "mise watch build" help="Run build and rerun it whenever its sources change"'
@usage 'example "mise watch build --clear" help="Clear the screen before each run"'
@usage 'example "mise watch serve --watch src --exts rs --restart" help="Start an API server and restart it when Rust files in ./src change"'
@usage 'example "mise watch test -- --verbose" help="Pass arguments after -- to the task"'
@usage 'complete path type=path'
@usage 'complete directory type=dir'
export def "mise watch" [
    task?: string@"nus complete",                                                 # Task to watch (default: `default`); separate several tasks with `:::`
    ...args: string,                                                              # Arguments for the task; `:::` starts the next task
    --cd (-C): path@"nus complete",                                               # Run as if mise were started in DIR
    --env_ (-E): list<string>,                                                    # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                                                          # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                                                                 # Suppress non-error messages
    --shell: string,                                                              # Use a different shell
    --verbose (-v): int,                                                          # Show extra output (use -vv for even more)
    --yes (-y),                                                                   # Answer yes to all confirmation prompts
    --raw,                                                                        # Connect tasks and install commands directly to the terminal
    --locked,                                                                     # Require download URLs from the lockfile when installing
    --silent,                                                                     # Suppress all task output and mise non-error messages
    --timings,                                                                    # Print how long the command took to run
    --glob (-g): list<string>,                                                    # Globs to watch instead of the tasks' sources
    --skip-deps,                                                                  # Run and watch only the named tasks, not the tasks they depend on
    --watch (-w): list<path>@"nus complete",                                      # Watch a file or directory
    --watch-non-recursive (-W): list<path>@"nus complete",                        # Watch a directory without recursing into it
    --watch-file (-F): path@"nus complete",                                       # Read paths to watch from a file, one per line
    --clear (-c): string@[clear reset],                                           # Clear the screen before each run
    --on-busy-update (-o): string@[queue do-nothing restart signal],              # What to do when files change while the tasks are running
    --restart (-r),                                                               # Restart the tasks if they are still running when files change
    --signal (-s): string,                                                        # Signal to send to the running tasks when files change
    --stop-signal: string,                                                        # Signal that stops the tasks before a restart (default on Unix: SIGTERM)
    --stop-timeout: string,                                                       # How long to wait for the tasks to stop before killing them (default: 10s)
    --map-signal: list<string>,                                                   # Translate a signal that watchexec receives into one it sends to the tasks
    --debounce (-d): string,                                                      # How long to wait for more changes before running (default: 50ms)
    --stdin-quit,                                                                 # Exit when stdin closes
    --no-vcs-ignore,                                                              # Do not apply Git and other version control ignore files
    --no-project-ignore,                                                          # Do not apply ignore files in the project, such as `.gitignore` and `.ignore`
    --no-global-ignore,                                                           # Do not apply global ignore files, such as `~/.gitignore` and `~/.config/watchexec/ignore`
    --no-default-ignore,                                                          # Do not apply watchexec's built-in ignores
    --no-discover-ignore,                                                         # Do not look for ignore files at all
    --ignore-nothing,                                                             # Ignore nothing
    --postpone (-p),                                                              # Wait for the first change before running the tasks
    --delay-run: string,                                                          # Wait this long after a change before running the tasks, e.g. 5s
    --poll: string,                                                               # Poll for changes instead of using native file watching
    --n (-n),                                                                     # Shorthand for '--shell=none'
    --emit-events-to: string@[environment stdio file json-stdio json-file none],  # Configure event emission
    --only-emit-events,                                                           # Only emit events to stdout, run no commands.
    --watchexec-env: list<string>,                                                # Add env vars to the command
    --wrap-process: string@[group session none],                                  # How to wrap the task process: group, session, or none
    --notify (-N),                                                                # Alert when commands start and end
    --color: string@[auto always never],                                          # When to use terminal colours
    --watchexec-quiet,                                                            # Don't print starting and stopping messages
    --bell,                                                                       # Ring the terminal bell on command completion
    --project-origin: path@"nus complete",                                        # Set the project origin
    --exts (-e): list<string>,                                                    # Only react to files with these extensions, e.g. js,ts
    --filter (-f): list<string>,                                                  # Only react to files that match this glob
    --filter-file: list<path>@"nus complete",                                     # Files to load filters from
    --filter-prog (-J): list<string>,                                             # [experimental] Filter programs.
    --ignore (-i): list<string>,                                                  # Ignore files that match this glob
    --ignore-file: list<path>@"nus complete",                                     # Read ignore patterns from a file, one per line
    --fs-events: list<string>@[access create remove rename modify metadata],      # Filesystem events to filter to
    --no-meta,                                                                    # Don't emit fs events for metadata changes
    --print-events,                                                               # Print the events that trigger each run
    --manual,                                                                     # Show the manual page
]: nothing -> string {
    ^mise watch ...(nus argv [$task ...$args] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --shell: $shell
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --timings: $timings
        --glob: $glob
        --skip-deps: $skip_deps
        --watch: $watch
        --watch-non-recursive: $watch_non_recursive
        --watch-file: $watch_file
        --clear: $clear
        --on-busy-update: $on_busy_update
        --restart: $restart
        --signal: $signal
        --stop-signal: $stop_signal
        --stop-timeout: $stop_timeout
        --map-signal: $map_signal
        --debounce: $debounce
        --stdin-quit: $stdin_quit
        --no-vcs-ignore: $no_vcs_ignore
        --no-project-ignore: $no_project_ignore
        --no-global-ignore: $no_global_ignore
        --no-default-ignore: $no_default_ignore
        --no-discover-ignore: $no_discover_ignore
        --ignore-nothing: $ignore_nothing
        --postpone: $postpone
        --delay-run: $delay_run
        --poll: $poll
        -n: $n
        --emit-events-to: $emit_events_to
        --only-emit-events: $only_emit_events
        --watchexec-env: $watchexec_env
        --wrap-process: $wrap_process
        --notify: $notify
        --color: $color
        --watchexec-quiet: $watchexec_quiet
        --bell: $bell
        --project-origin: $project_origin
        --exts: $exts
        --filter: $filter
        --filter-file: $filter_file
        --filter-prog: $filter_prog
        --ignore: $ignore
        --ignore-file: $ignore_file
        --fs-events: $fs_events
        --no-meta: $no_meta
        --print-events: $print_events
        --manual: $manual
    })
}

# Show the install directory of a tool version
#
# Fails if no matching version is installed.
@usage 'long_help #"""
Show the install directory of a tool version

Fails if no matching version is installed.
"""#'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg <TOOL@VERSION> help="Tool to look up, such as ruby@3" help_long=#"""
Tool to look up, such as ruby@3

With a version prefix, shows the newest installed version that matches it. Otherwise, shows the active installed version.
"""#'
@usage 'arg "[ASDF_VERSION]" help=#"""
the version prefix to use when querying the latest version
same as the first argument after the "@"
used for asdf compatibility
"""# required=#false hide=#true'
@usage 'example #"""
mise where node@20
~/.local/share/mise/installs/node/20.0.0
"""# help="Show the newest installed node 20.x"'
@usage 'example #"""
mise where node
~/.local/share/mise/installs/node/20.0.0
"""# help="Show the active node, or the newest installed node if no config requests one"'
export def "mise where" [
    tool_version: string@"nus complete",  # Tool to look up, such as ruby@3
    asdf_version?: string,                # the version prefix to use when querying the latest version same as the first argument after the "@" used for asdf compatibility
    --cd (-C): path@"nus complete",       # Run as if mise were started in DIR
    --env_ (-E): list<string>,            # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                  # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                         # Suppress non-error messages
    --verbose (-v): int,                  # Show extra output (use -vv for even more)
    --yes (-y),                           # Answer yes to all confirmation prompts
    --raw,                                # Connect tasks and install commands directly to the terminal
    --locked,                             # Require download URLs from the lockfile when installing
    --silent,                             # Suppress all task output and mise non-error messages
]: nothing -> string {
    ^mise where ...(nus argv [$tool_version $asdf_version] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --verbose: $verbose
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
    })
}

# Show the path a tool's executable resolves to
#
# Prints the real path of the executable mise would run for BIN_NAME in the
# current directory, bypassing shims. Use `--version` or `--plugin` to see
# which tool version provides it.
@usage r#'long_help #"""
Show the path a tool's executable resolves to

Prints the real path of the executable mise would run for BIN_NAME in the
current directory, bypassing shims. Use `--version` or `--plugin` to see
which tool version provides it.
"""#'#
@usage 'flag "-t --tool" help="Look in a specific tool version, such as `mise which npm --tool=node@20`" {
        arg <TOOL@VERSION>
    }'
@usage 'flag --complete hide=#true'
@usage 'flag --plugin help="Show the name of the tool that provides the executable" conflicts=--version'
@usage 'flag --version help="Show the version instead of the path" conflicts=--plugin'
@usage 'flag "-h --help" help="Print help" action=help builtin=#true'
@usage 'arg "[BIN_NAME]" help="The executable to look up" required=#false required_unless=--complete'
@usage 'example #"""
mise which node
~/.local/share/mise/installs/node/20.0.0/bin/node
"""# help="Show the path of the node executable"'
@usage 'example #"""
mise which node --plugin
node
"""# help="Show the tool that provides it"'
@usage 'example #"""
mise which node --version
20.0.0
"""# help="Show the version that provides it"'
export def "mise which" [
    bin_name?: string@"nus complete",    # The executable to look up
    --cd (-C): path@"nus complete",      # Run as if mise were started in DIR
    --env_ (-E): list<string>,           # Load the `mise.<ENV>.toml` config files (same as MISE_ENV)
    --jobs (-j): string,                 # How many jobs to run in parallel; defaults to the `jobs` setting
    --quiet (-q),                        # Suppress non-error messages
    --tool (-t): string@"nus complete",  # Look in a specific tool version, such as `mise which npm --tool=node@20`
    --verbose (-v): int,                 # Show extra output (use -vv for even more)
    --version,                           # Show the version instead of the path
    --yes (-y),                          # Answer yes to all confirmation prompts
    --raw,                               # Connect tasks and install commands directly to the terminal
    --locked,                            # Require download URLs from the lockfile when installing
    --silent,                            # Suppress all task output and mise non-error messages
    --plugin,                            # Show the name of the tool that provides the executable
]: nothing -> string {
    ^mise which ...(nus argv [$bin_name] {
        --cd: $cd
        --env: $env_
        --jobs: $jobs
        --quiet: $quiet
        --tool: $tool
        --verbose: $verbose
        --version: $version
        --yes: $yes
        --raw: $raw
        --locked: $locked
        --silent: $silent
        --plugin: $plugin
    })
}
