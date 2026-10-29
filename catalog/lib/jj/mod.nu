alias "attr usage" = echo

# A value as an argv word: a datetime in ISO 8601, anything else as Nushell writes it.
def "nusage word" []: any -> string {
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
def "nusage argv" [positionals: list<any>, flags: record, scoped: record = {}]: nothing -> list<string> {
    let scoped = $scoped | nusage flag-words
    let words = $positionals | compact | each { nusage word }
    let instances = if ($words | is-empty) {
        $scoped
    } else {
        $words | each {|word| $scoped ++ [$word] } | flatten
    }
    $instances ++ ($flags | nusage flag-words)
}

def "nusage flag-words" []: record -> list<string> {
    $in | transpose name value | each {|flag|
        match ($flag.value | describe --detailed | get type) {
            bool => (if $flag.value { [$flag.name] } else { [] })
            int => (0..<$flag.value | each { $flag.name })
            list => ($flag.value | each {|value| [$flag.name ($value | nusage word)] } | flatten)
            nothing => []
            _ => [$flag.name ($flag.value | nusage word)]
        }
    } | flatten
}

# Completions from usage's own completer, against the spec this module was generated
# from, with the words typed so far. Nothing when the `usage` CLI is not installed.
def "nusage complete" [place: record] {
    const spec = (path self | path dirname | path join "jj.usage.kdl")
    if (which usage | is-empty) {
        return []
    }
    let name = $place.command | first
    let command = if $name == "main" { [jj] } else { $name | split row " " }
    let words = $place.command | skip 1
    (^usage complete-word -f $spec --shell nu -- ...$command ...$words | complete).stdout
    | lines
    | each {|line| $line | split column "	" value description | into record }
}

# A binary's output decoded as the module's closure decodes it. When that fails and the
# `nusage` this module was generated with is on PATH, the output is held to the schema the
# spec declares, line by line with `--lines`, so the error names what does not match it
# rather than what failed to convert; what failed to convert follows, as the inner error.
# The error is the decoding's own when the output matches or there is no `nusage` to ask,
# and the inner one under why the output could not be held to its schema when the check
# did not run.
def "nusage decoded" [
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
        let checked = $text | ^nusage validate $file - ...$flags | complete
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
                    msg: $"the output could not be held to its schema: nusage validate exited ($checked.exit_code)\n($checked.stderr | str trim)"
                }
            }
        }
    }
}

# Jujutsu (An experimental VCS)
#
# To get started, see the tutorial at [`jj help -k tutorial`][tutorial].
#
# [tutorial]: https://docs.jj-vcs.dev/latest/tutorial/
@usage 'version "0.46.0"'
@usage 'unknown_flags error'
@usage 'disable_help_subcommand #true'
@usage 'usage "Usage: jj [OPTIONS] [COMMAND]"'
@usage 'flag "-R --repository" help="Path to repository to operate on" global=#true help_heading="Global Options" {
    long_help #"""
Path to repository to operate on

By default, Jujutsu searches for the closest .jj/ directory in an ancestor of the current working directory.
"""#
    arg <REPOSITORY>
}'
@usage r#'flag --ignore-working-copy help="Don't snapshot the working copy, and don't update it" global=#true help_heading="Global Options" {
    long_help #"""
Don't snapshot the working copy, and don't update it

By default, Jujutsu snapshots the working copy at the beginning of every command. The working copy is also updated at the end of the command, if the command modified the working-copy commit (`@`). If you want to avoid snapshotting the working copy and instead see a possibly stale working-copy commit, you can use `--ignore-working-copy`. This may be useful e.g. in a command prompt, especially if you have another process that commits the working copy.

Loading the repository at a specific operation with `--at-operation` implies `--ignore-working-copy`.
"""#
}'#
@usage r#'flag --no-integrate-operation help="Run the command as usual but don't integrate any operations" global=#true help_heading="Global Options" {
    long_help #"""
Run the command as usual but don't integrate any operations

When this option is given, the operations will still be created as usual but they will not be integrated to the operation log. The working copy will also not be updated.

The command will print the resulting operation ID. You can pass that to e.g. `jj --at-op` to inspect the resulting repo state, or you can pass it to `jj op restore` to restore the repo to that state. You can also pass the ID to `jj op integrate` to integrate the operation.

Note that this does *not* prevent side effects outside the repo. For example, `jj git push --no-integrate-operation` will still perform the push.
"""#
}'#
@usage 'flag --ignore-immutable help="Allow rewriting immutable commits" global=#true help_heading="Global Options" {
    long_help #"""
Allow rewriting immutable commits

By default, Jujutsu prevents rewriting commits in the configured set of immutable commits. This option disables that check and lets you rewrite any commit but the root commit.

This option only affects the check. It does not affect the `immutable_heads()` revset or the `immutable` template keyword.
"""#
}'
@usage r#'flag "--at-operation --at-op" help="Operation to load the repo at" global=#true help_heading="Global Options" {
    long_help #"""
Operation to load the repo at

Operation to load the repo at. By default, Jujutsu loads the repo at the most recent operation, or at the merge of the divergent operations if any.

You can use `--at-op=<operation ID>` to see what the repo looked like at an earlier operation. For example `jj --at-op=<operation ID> st` will show you what `jj st` would have shown you when the given operation had just finished. `--at-op=@` is pretty much the same as the default except that divergent operations will never be merged.

Use `jj op log` to find the operation ID you want. Any unambiguous prefix of the operation ID is enough.

When loading the repo at an earlier operation, the working copy will be ignored, as if `--ignore-working-copy` had been specified.

It is possible to run mutating commands when loading the repo at an earlier operation. Doing that is equivalent to having run concurrent commands starting at the earlier operation. There's rarely a reason to do that, but it is possible.
"""#
    arg <AT_OPERATION>
}'#
@usage 'flag --debug help="Enable debug logging" global=#true help_heading="Global Options"'
@usage 'flag --color help="When to colorize output" global=#true help_heading="Global Options" {
    arg <WHEN> {
        choices always never debug auto
    }
}'
@usage r#'flag --quiet help="Silence non-primary command output" global=#true help_heading="Global Options" {
    long_help #"""
Silence non-primary command output

For example, `jj file list` will still list files, but it won't tell you if the working copy was snapshotted or if descendants were rebased.

Warnings and errors will still be printed.
"""#
}'#
@usage 'flag --no-pager help="Disable the pager" global=#true help_heading="Global Options"'
@usage r#'flag --config help="Additional configuration options (can be repeated)" var=#true global=#true help_heading="Global Options" {
    long_help #"""
Additional configuration options (can be repeated)

The name should be specified as TOML dotted keys. The value should be specified as a TOML expression. If string value isn't enclosed by any TOML constructs (such as array notation), quotes can be omitted.
"""#
    arg "<NAME=VALUE>…" var=#true
}'#
@usage 'flag --config-file help="Additional configuration files (can be repeated)" var=#true global=#true help_heading="Global Options" {
    arg <PATH>… var=#true
}'
@usage 'complete repository type=dir'
@usage 'complete path type=path'
export def main [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Abandon a revision
#
# Abandon a revision, rebasing descendants onto its parent(s). The behavior is similar to `jj restore --changes-in`; the difference is that `jj abandon` gives you a new change, while `jj restore` updates the existing change.
#
# If a working-copy commit gets abandoned, it will be given a new, empty commit. This is true in general; it is not specific to this command.
@usage 'long_help #"""
Abandon a revision

Abandon a revision, rebasing descendants onto its parent(s). The behavior is similar to `jj restore --changes-in`; the difference is that `jj abandon` gives you a new change, while `jj restore` updates the existing change.

If a working-copy commit gets abandoned, it will be given a new, empty commit. This is true in general; it is not specific to this command.
"""#'
@usage 'flag -r var=#true hide=#true {
        arg <REVSETS>… var=#true
    }'
@usage 'flag --retain-bookmarks help="Do not delete bookmarks pointing to the revisions to abandon" {
        long_help #"""
Do not delete bookmarks pointing to the revisions to abandon

Bookmarks will be moved to the parent revisions instead.
"""#
    }'
@usage 'flag --restore-descendants help="Do not modify the content of the children of the abandoned commits"'
@usage 'arg "[REVSETS]…" help="The revision(s) to abandon (default: @) [aliases: -r]" required=#false var=#true var_min=1'
export def "jj abandon" [
    ...revsets: string,                           # The revision(s) to abandon (default: @) [aliases: -r]
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --retain-bookmarks,                           # Do not delete bookmarks pointing to the revisions to abandon
    --restore-descendants,                        # Do not modify the content of the children of the abandoned commits
]: nothing -> string {
    ^jj abandon ...(nusage argv [...$revsets] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --retain-bookmarks: $retain_bookmarks
        --restore-descendants: $restore_descendants
    })
}

# Move changes from a revision into the stack of mutable revisions
#
# This command splits changes in the source revision and moves each change to the closest mutable ancestor where the corresponding lines were modified last. If the destination revision cannot be determined unambiguously, the change will be left in the source revision.
#
# With the `--interactive` option, only the selected changes will be considered for absorption. This allows picking specific hunks to absorb (which may then be distributed across multiple ancestors). The `--tool` option can be used to select a different diff editor.
#
# The source revision will be abandoned if all changes are absorbed into the destination revisions, and if the source revision has no description.
#
# The modification made by `jj absorb` can be reviewed by `jj op show -p`.
@usage 'long_help #"""
Move changes from a revision into the stack of mutable revisions

This command splits changes in the source revision and moves each change to the closest mutable ancestor where the corresponding lines were modified last. If the destination revision cannot be determined unambiguously, the change will be left in the source revision.

With the `--interactive` option, only the selected changes will be considered for absorption. This allows picking specific hunks to absorb (which may then be distributed across multiple ancestors). The `--tool` option can be used to select a different diff editor.

The source revision will be abandoned if all changes are absorbed into the destination revisions, and if the source revision has no description.

The modification made by `jj absorb` can be reviewed by `jj op show -p`.
"""#'
@usage 'flag "-f --from" help="Source revision to absorb from" default=@ {
        arg <REVSET>
    }'
@usage 'flag "-t --into --to" help="Destination revisions to absorb into" var=#true default="mutable()" {
        long_help #"""
Destination revisions to absorb into

Only ancestors of the source revision will be considered.
"""#
        arg <REVSETS>… var=#true
    }'
@usage 'flag "-i --interactive" help="Interactively choose which parts to absorb"'
@usage 'flag --tool help="Specify diff editor to be used (implies --interactive)" {
        arg <NAME>
    }'
@usage 'arg "[FILESETS]…" help="Move only changes to these paths (instead of all paths)" required=#false var=#true var_min=1'
@usage 'complete filesets type=path'
export def "jj absorb" [
    ...filesets: path@"nusage complete",          # Move only changes to these paths (instead of all paths)
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --from (-f): string,                          # Source revision to absorb from
    --into (-t): list<string>,                    # Destination revisions to absorb into
    --interactive (-i),                           # Interactively choose which parts to absorb
    --tool: string,                               # Specify diff editor to be used (implies --interactive)
]: nothing -> string {
    ^jj absorb ...(nusage argv [...$filesets] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --from: $from
        --into: $into
        --interactive: $interactive
        --tool: $tool
    })
}

# Interactively arrange the commit graph
@usage 'flag -r var=#true hide=#true {
        arg <REVSETS>… var=#true
    }'
@usage 'arg "[REVSETS]…" help="The revisions to arrange [aliases: -r]" help_long=#"""
The revisions to arrange [aliases: -r]

If no revisions are specified, this defaults to the `revsets.arrange` setting.
"""# required=#false var=#true var_min=1'
export def "jj arrange" [
    ...revsets: string,                           # The revisions to arrange [aliases: -r]
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj arrange ...(nusage argv [...$revsets] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Find a bad revision by bisection
export def "jj bisect" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj bisect ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Run a given command to find the first bad revision
#
# Uses binary search to find the first "bad" revision. Revisions are evaluated
# by running the given command (see the documentation for `<COMMAND>` for
# details).
#
# It is assumed that if a given revision is "bad", then all its descendants
# in the input range are also "bad". Pass `--find-good` to invert this
# assumption: if a given revision is "good", all of its descendants are
# assumed to be "good". `jj bisect run` will then look for the first "good"
# revision.
#
# Hint: You can pass your shell as the command, then run manual tests in a
# script. When you're done, make sure to exit the shell with an appropriate
# error code depending on the desired outcome (e.g., `exit 0` to mark the
# revision as "good").
#
# Example: To run `cargo test` with the changes from revision `xyz` applied:
# ```shell
# jj bisect run --range v1.0..main -- bash -c "jj duplicate xyz -B @ &&
# cargo test"
# ```
@usage r#'long_help #"""
Run a given command to find the first bad revision

Uses binary search to find the first "bad" revision. Revisions are evaluated
by running the given command (see the documentation for `<COMMAND>` for
details).

It is assumed that if a given revision is "bad", then all its descendants
in the input range are also "bad". Pass `--find-good` to invert this
assumption: if a given revision is "good", all of its descendants are
assumed to be "good". `jj bisect run` will then look for the first "good"
revision.

Hint: You can pass your shell as the command, then run manual tests in a
script. When you're done, make sure to exit the shell with an appropriate
error code depending on the desired outcome (e.g., `exit 0` to mark the
revision as "good").

Example: To run `cargo test` with the changes from revision `xyz` applied:
```shell
jj bisect run --range v1.0..main -- bash -c "jj duplicate xyz -B @ &&
cargo test"
```
"""#'#
@usage 'flag "-r --range" help="Range of revisions to bisect (can be repeated)" required=#true var=#true {
            long_help #"""
Range of revisions to bisect (can be repeated)

This is typically a range like `v1.0..main`. The heads of the range are assumed to be bad. Ancestors of the range that are not also in the range are assumed to be good.

The union of all given ranges are used as the input for the bisection.
"""#
            arg <REVSETS>… var=#true
        }'
@usage 'flag --command help="Deprecated. Use positional arguments instead" hide=#true conflicts=COMMAND {
            arg <COMMAND>
        }'
@usage r#'flag --find-good help="Find the first good revision instead" default="false" {
            long_help #"""
Find the first good revision instead

Normally, `jj bisect run` looks for a revision in the provided `REVSETS` that's bad and whose parents are good. With `--find-good`, `jj bisect run` instead finds a commit that's good and whose parents are bad.

`COMMAND` is still expected to exit with code 0 if and only if the revision is good.
"""#
        }'#
@usage 'flag --trust-endpoints help="Skip the pre-bisection checks" {
            long_help #"""
Skip the pre-bisection checks

By default, `COMMAND` will be run on every revision `jj bisect run` assumes to be good or bad before bisection actually begins, as detailed under the documentation for `COMMAND`. This flag disables these checks.
"""#
        }'
@usage r#'arg "[COMMAND]" help="Command to run to determine the status of a revision" help_long=#"""
Command to run to determine the status of a revision

Each revision being checked will be directly edited (will become the current working copy) before running this command. The exit status of the command will be used to mark revisions as "good" or "bad": status 0 means "good", 125 means to skip the revision, 127 (command not found) will abort the bisection, and any other non-zero exit status means the revision is "bad".

In order for bisection to be meaningful, `COMMAND` must succeed for every revision in `heads(REVSETS)`, and it must fail for every revision in `parents(connected(REVSETS)) ~ connected(REVSETS)`; if you are using `--find-good`, these checks are reversed. (Visit <https://docs.jj-vcs.dev/latest/revsets/> for more information about the jj revset language.)

The target's commit ID is available to the command in the `$JJ_BISECT_TARGET` environment variable.
"""# required=#false'#
@usage 'arg "[ARGS]…" help="Arguments to pass to the command" help_long=#"""
Arguments to pass to the command

Hint: Use a `--` separator to allow passing arguments starting with `-`. For example: `jj bisect run --range=... -- test -f some-file`.
"""# required=#false var=#true var_min=1'
export def "jj bisect run" [
    command?: string,                             # Command to run to determine the status of a revision
    ...args: string,                              # Arguments to pass to the command
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --range (-r): list<string>,                   # Range of revisions to bisect (can be repeated)
    --find-good,                                  # Find the first good revision instead
    --trust-endpoints,                            # Skip the pre-bisection checks
]: nothing -> string {
    ^jj bisect run ...(nusage argv [$command ...$args] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --range: $range
        --find-good: $find_good
        --trust-endpoints: $trust_endpoints
    })
}

# Manage bookmarks [default alias: b]
#
# See [`jj help -k bookmarks`][bookmarks] for more information.
#
# [bookmarks]: https://docs.jj-vcs.dev/latest/bookmarks
@usage 'long_help #"""
Manage bookmarks [default alias: b]

See [`jj help -k bookmarks`][bookmarks] for more information.

[bookmarks]: https://docs.jj-vcs.dev/latest/bookmarks
"""#'
export def "jj bookmark" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj bookmark ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Advance the closest bookmarks to a target revision
#
# The target `--to` defaults to `revsets.bookmark-advance-to` (which defaults to `@`).
#
# The bookmarks to advance are determined by `revsets.bookmark-advance-from` (which defaults to `heads(::to & bookmarks())`).
#
# Note that the from revset has access to `to`.
#
# Positional bookmark name arguments can target specific bookmarks to advance to the target, in this case the default from revset is ignored.
#
# Example:
#
# `jj bookmark advance --to x` - Does the equivalent of `jj bookmark move --from 'heads(::x & bookmarks())' --to x`.
@usage 'alias a'
@usage r#'long_help #"""
Advance the closest bookmarks to a target revision

The target `--to` defaults to `revsets.bookmark-advance-to` (which defaults to `@`).

The bookmarks to advance are determined by `revsets.bookmark-advance-from` (which defaults to `heads(::to & bookmarks())`).

Note that the from revset has access to `to`.

Positional bookmark name arguments can target specific bookmarks to advance to the target, in this case the default from revset is ignored.

Example:

`jj bookmark advance --to x` - Does the equivalent of `jj bookmark move --from 'heads(::x & bookmarks())' --to x`.
"""#'#
@usage 'flag "-t --to" help="Move bookmarks to this revision" {
            long_help #"""
Move bookmarks to this revision

Defaults to `revsets.bookmark-advance-to`.
"""#
            arg <REVSET>
        }'
@usage 'arg "[NAMES]…" help="Move bookmarks matching the given name patterns" help_long=#"""
Move bookmarks matching the given name patterns

By default, the specified pattern matches bookmark names with glob syntax. You can also use other [string pattern syntax].

[string pattern syntax]: https://docs.jj-vcs.dev/latest/revsets/#string-patterns
"""# required=#false var=#true var_min=1'
export def "jj bookmark advance" [
    ...names: string,                             # Move bookmarks matching the given name patterns
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --to (-t): string,                            # Move bookmarks to this revision
]: nothing -> string {
    ^jj bookmark advance ...(nusage argv [...$names] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --to: $to
    })
}

# Create a new bookmark
@usage 'alias c'
@usage r#'flag "-r --revision --to" help="The bookmark's target revision" default=@ {
            arg <REVSET>
        }'#
@usage 'arg <NAMES>… help="The bookmarks to create" var=#true var_min=1'
export def "jj bookmark create" [
    ...names: string,                             # The bookmarks to create
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --revision (-r): string,                      # The bookmark's target revision
]: nothing -> string {
    ^jj bookmark create ...(nusage argv [...$names] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --revision: $revision
    })
}

# Delete an existing bookmark and propagate the deletion to remotes on the next push
#
# Revisions referred to by the deleted bookmarks are not abandoned. To delete revisions as well as bookmarks, use `jj abandon`. For example, `jj abandon main..<bookmark>` will abandon revisions belonging to the `<bookmark>` branch (relative to the `main` branch.)
#
# If you don't want the deletion of the local bookmark to propagate to any tracked remote bookmarks, use `jj bookmark forget` instead.
@usage 'alias d'
@usage r#'long_help #"""
Delete an existing bookmark and propagate the deletion to remotes on the next push

Revisions referred to by the deleted bookmarks are not abandoned. To delete revisions as well as bookmarks, use `jj abandon`. For example, `jj abandon main..<bookmark>` will abandon revisions belonging to the `<bookmark>` branch (relative to the `main` branch.)

If you don't want the deletion of the local bookmark to propagate to any tracked remote bookmarks, use `jj bookmark forget` instead.
"""#'#
@usage 'arg <NAMES>… help="The bookmarks to delete" help_long=#"""
The bookmarks to delete

By default, the specified pattern matches bookmark names with glob syntax. You can also use other [string pattern syntax].

[string pattern syntax]: https://docs.jj-vcs.dev/latest/revsets/#string-patterns
"""# var=#true var_min=1'
export def "jj bookmark delete" [
    ...names: string,                             # The bookmarks to delete
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj bookmark delete ...(nusage argv [...$names] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Forget a bookmark without marking it as a deletion to be pushed
#
# If a local bookmark is forgotten, any corresponding remote bookmarks will become untracked to ensure that the forgotten bookmark will not impact remotes on future pushes.
@usage 'alias f'
@usage 'long_help #"""
Forget a bookmark without marking it as a deletion to be pushed

If a local bookmark is forgotten, any corresponding remote bookmarks will become untracked to ensure that the forgotten bookmark will not impact remotes on future pushes.
"""#'
@usage 'flag --include-remotes help="When forgetting a local bookmark, also forget any corresponding remote bookmarks" {
            long_help #"""
When forgetting a local bookmark, also forget any corresponding remote bookmarks

A forgotten remote bookmark will not impact remotes on future pushes. It will be recreated on future fetches if it still exists on the remote. If there is a corresponding Git-tracking remote bookmark, it will also be forgotten.
"""#
        }'
@usage 'arg <NAMES>… help="The bookmarks to forget" help_long=#"""
The bookmarks to forget

By default, the specified pattern matches bookmark names with glob syntax. You can also use other [string pattern syntax].

[string pattern syntax]: https://docs.jj-vcs.dev/latest/revsets/#string-patterns
"""# var=#true var_min=1'
export def "jj bookmark forget" [
    ...names: string,                             # The bookmarks to forget
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --include-remotes,                            # When forgetting a local bookmark, also forget any corresponding remote bookmarks
]: nothing -> string {
    ^jj bookmark forget ...(nusage argv [...$names] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --include-remotes: $include_remotes
    })
}

# List bookmarks and their targets
#
# By default, a tracked remote bookmark will be included only if its target is different from the local target. An untracked remote bookmark won't be listed. For a conflicted bookmark (both local and remote), old target revisions are preceded by a "-" and new target revisions are preceded by a "+".
#
# See [`jj help -k bookmarks`][bookmarks] for more information.
#
# [bookmarks]: https://docs.jj-vcs.dev/latest/bookmarks
@usage 'alias l'
@usage r#'long_help #"""
List bookmarks and their targets

By default, a tracked remote bookmark will be included only if its target is different from the local target. An untracked remote bookmark won't be listed. For a conflicted bookmark (both local and remote), old target revisions are preceded by a "-" and new target revisions are preceded by a "+".

See [`jj help -k bookmarks`][bookmarks] for more information.

[bookmarks]: https://docs.jj-vcs.dev/latest/bookmarks
"""#'#
@usage 'flag "-a --all-remotes" help="Show all tracked and untracked remote bookmarks including the ones whose targets are synchronized with the local bookmarks" {
            alias "--all" hide=#true
        }'
@usage 'flag --remote help="Show all tracked and untracked remote bookmarks belonging to this remote" var=#true conflicts=--all-remotes {
            long_help #"""
Show all tracked and untracked remote bookmarks belonging to this remote

Can be combined with `--tracked` or `--conflicted` to filter the bookmarks shown (can be repeated.)

By default, the specified pattern matches remote names with glob syntax. You can also use other [string pattern syntax].

[string pattern syntax]: https://docs.jj-vcs.dev/latest/revsets/#string-patterns
"""#
            arg <REMOTE>… var=#true
        }'
@usage 'flag "-t --tracked" help="Show tracked remote bookmarks only" conflicts=--all-remotes {
            long_help #"""
Show tracked remote bookmarks only

This omits local Git-tracking bookmarks by default.
"""#
        }'
@usage 'flag "-c --conflicted" help="Show conflicted bookmarks only" conflicts=--all-remotes'
@usage r#'flag "-r --revision" help="Show bookmarks whose local targets are in the given revisions" var=#true {
            alias "--revisions" hide=#true
            long_help #"""
Show bookmarks whose local targets are in the given revisions

Note that `-r deleted_bookmark` will not work since `deleted_bookmark` wouldn't have a local target.
"""#
            arg <REVSETS>… var=#true
        }'#
@usage 'flag "-T --template" help="Render each bookmark using the given template" {
            long_help #"""
Render each bookmark using the given template

All 0-argument methods of the [`CommitRef` type][CommitRef] are available as keywords in the template expression. See [`jj help -k templates`][templates] for more information.

The default template can be set by the `templates.bookmark_list` setting.

[CommitRef]: https://docs.jj-vcs.dev/latest/templates/#commitref-type

[templates]: https://docs.jj-vcs.dev/latest/templates/
"""#
            arg <TEMPLATE>
        }'
@usage 'flag --sort help="Sort bookmarks based on the given key (or multiple keys)" var=#true {
            long_help #"""
Sort bookmarks based on the given key (or multiple keys)

Suffix the key with `-` to sort in descending order of the value (e.g. `--sort name-`). Note that when using multiple keys, the first key is the most significant.

This defaults to the `ui.bookmark-list-sort-keys` setting.
"""#
            arg <SORT_KEY>… var=#true delimiter=, {
                choices name name- author-name author-name- author-email author-email- author-date author-date- committer-name committer-name- committer-email committer-email- committer-date committer-date-
            }
        }'
@usage 'arg "[NAMES]…" help="Show bookmarks whose local name matches" help_long=#"""
Show bookmarks whose local name matches

By default, the specified pattern matches bookmark names with glob syntax. You can also use other [string pattern syntax].

[string pattern syntax]: https://docs.jj-vcs.dev/latest/revsets/#string-patterns
"""# required=#false var=#true var_min=1'
@usage 'output "json" framing="jsonl" { schema "{\n  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",\n  \"title\": \"A bookmark or a tag, one line of `jj bookmark list` or `jj tag list`\",\n  \"type\": \"object\",\n  \"required\": [\n    \"name\",\n    \"target\"\n  ],\n  \"additionalProperties\": false,\n  \"properties\": {\n    \"name\": {\n      \"type\": \"string\"\n    },\n    \"remote\": {\n      \"type\": \"string\"\n    },\n    \"target\": {\n      \"$ref\": \"#/$defs/target\"\n    },\n    \"tracking_target\": {\n      \"$ref\": \"#/$defs/target\"\n    }\n  },\n  \"$defs\": {\n    \"target\": {\n      \"type\": \"array\",\n      \"minItems\": 1,\n      \"items\": {\n        \"anyOf\": [\n          {\n            \"type\": \"string\",\n            \"pattern\": \"^[0-9a-f]+$\"\n          },\n          {\n            \"type\": \"null\"\n          }\n        ]\n      }\n    }\n  }\n}\n" }'
export def "jj bookmark list" [
    ...names: string,                                                                                                                                                                                               # Show bookmarks whose local name matches
    --repository (-R): path@"nusage complete",                                                                                                                                                                      # Path to repository to operate on
    --ignore-working-copy,                                                                                                                                                                                          # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                                                                                                                                                                                       # Run the command as usual but don't integrate any operations
    --ignore-immutable,                                                                                                                                                                                             # Allow rewriting immutable commits
    --at-operation: string,                                                                                                                                                                                         # Operation to load the repo at
    --debug,                                                                                                                                                                                                        # Enable debug logging
    --color: string@[always never debug auto],                                                                                                                                                                      # When to colorize output
    --quiet,                                                                                                                                                                                                        # Silence non-primary command output
    --no-pager,                                                                                                                                                                                                     # Disable the pager
    --config: list<string>,                                                                                                                                                                                         # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",                                                                                                                                                                    # Additional configuration files (can be repeated)
    --all-remotes (-a),                                                                                                                                                                                             # Show all tracked and untracked remote bookmarks including the ones whose targets are synchronized with the local bookmarks
    --remote: list<string>,                                                                                                                                                                                         # Show all tracked and untracked remote bookmarks belonging to this remote
    --tracked (-t),                                                                                                                                                                                                 # Show tracked remote bookmarks only
    --conflicted (-c),                                                                                                                                                                                              # Show conflicted bookmarks only
    --revision (-r): list<string>,                                                                                                                                                                                  # Show bookmarks whose local targets are in the given revisions
    --sort: list<string>@[name name- author-name author-name- author-email author-email- author-date author-date- committer-name committer-name- committer-email committer-email- committer-date committer-date-],  # Sort bookmarks based on the given key (or multiple keys)
]: nothing -> table<name: string, remote: oneof<string, nothing>, target: list<oneof<string, nothing>>, tracking_target: oneof<list<oneof<string, nothing>>, nothing>> {
    let text = ^jj bookmark list --template "json(self) ++ \"\\n\"" ...(nusage argv [...$names] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --all-remotes: $all_remotes
        --remote: $remote
        --tracked: $tracked
        --conflicted: $conflicted
        --revision: $revision
        --sort: $sort
    })
    nusage decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"title\":\"A bookmark or a tag, one line of `jj bookmark list` or `jj tag list`\",\"type\":\"object\",\"required\":[\"name\",\"target\"],\"additionalProperties\":false,\"properties\":{\"name\":{\"type\":\"string\"},\"remote\":{\"type\":\"string\"},\"target\":{\"$ref\":\"#/$defs/target\"},\"tracking_target\":{\"$ref\":\"#/$defs/target\"}},\"$defs\":{\"target\":{\"type\":\"array\",\"minItems\":1,\"items\":{\"anyOf\":[{\"type\":\"string\",\"pattern\":\"^[0-9a-f]+$\"},{\"type\":\"null\"}]}}}}" { from json --objects | default null remote | default null tracking_target } --lines
}

# Move existing bookmarks to target revision
#
# Unlike `jj bookmark set`, this command cannot create new bookmarks.
#
# If bookmark names are given, the specified bookmarks will be updated to point to the target revision.
#
# If `--from` options are given, bookmarks currently pointing to the specified revisions will be updated. The bookmarks can also be filtered by names.
@usage 'alias m'
@usage 'long_help #"""
Move existing bookmarks to target revision

Unlike `jj bookmark set`, this command cannot create new bookmarks.

If bookmark names are given, the specified bookmarks will be updated to point to the target revision.

If `--from` options are given, bookmarks currently pointing to the specified revisions will be updated. The bookmarks can also be filtered by names.
"""#'
@usage 'flag "-f --from" help="Move bookmarks from the given revisions" var=#true {
            arg <REVSETS>… var=#true
        }'
@usage 'flag "-t --to" help="Move bookmarks to this revision" default=@ {
            arg <REVSET>
        }'
@usage 'flag "-B --allow-backwards" help="Allow moving bookmarks backwards or sideways"'
@usage 'arg "[NAMES]…" help="Move bookmarks matching the given name patterns" help_long=#"""
Move bookmarks matching the given name patterns

By default, the specified pattern matches bookmark names with glob syntax. You can also use other [string pattern syntax].

[string pattern syntax]: https://docs.jj-vcs.dev/latest/revsets/#string-patterns
"""# required=#false var=#true var_min=1'
export def "jj bookmark move" [
    ...names: string,                             # Move bookmarks matching the given name patterns
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --from (-f): list<string>,                    # Move bookmarks from the given revisions
    --to (-t): string,                            # Move bookmarks to this revision
    --allow-backwards (-B),                       # Allow moving bookmarks backwards or sideways
]: nothing -> string {
    ^jj bookmark move ...(nusage argv [...$names] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --from: $from
        --to: $to
        --allow-backwards: $allow_backwards
    })
}

# Rename `old` bookmark name to `new` bookmark name
#
# The new bookmark name points at the same commit as the old bookmark name.
@usage 'alias r'
@usage 'long_help #"""
Rename `old` bookmark name to `new` bookmark name

The new bookmark name points at the same commit as the old bookmark name.
"""#'
@usage 'flag --overwrite-existing help="Allow renaming even if the new bookmark name already exists"'
@usage 'arg <OLD> help="The old name of the bookmark"'
@usage 'arg <NEW> help="The new name of the bookmark"'
export def "jj bookmark rename" [
    old: string,                                  # The old name of the bookmark
    new: string,                                  # The new name of the bookmark
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --overwrite-existing,                         # Allow renaming even if the new bookmark name already exists
]: nothing -> string {
    ^jj bookmark rename ...(nusage argv [$old $new] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --overwrite-existing: $overwrite_existing
    })
}

# Create a new bookmark, or update an existing one by name
#
# If you want to move bookmarks based on their current location rather than by name, use `jj bookmark move --from <REVSETS>`.
@usage 'alias s'
@usage 'long_help #"""
Create a new bookmark, or update an existing one by name

If you want to move bookmarks based on their current location rather than by name, use `jj bookmark move --from <REVSETS>`.
"""#'
@usage r#'flag "-r --revision --to" help="The bookmark's target revision" default=@ {
            arg <REVSET>
        }'#
@usage 'flag "-B --allow-backwards" help="Allow moving the bookmark backwards or sideways"'
@usage 'arg <NAMES>… help="The bookmarks to update" var=#true var_min=1'
export def "jj bookmark set" [
    ...names: string,                             # The bookmarks to update
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --revision (-r): string,                      # The bookmark's target revision
    --allow-backwards (-B),                       # Allow moving the bookmark backwards or sideways
]: nothing -> string {
    ^jj bookmark set ...(nusage argv [...$names] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --revision: $revision
        --allow-backwards: $allow_backwards
    })
}

# Start tracking given remote bookmarks
#
# A tracked remote bookmark will be imported as a local bookmark of the same name. Changes to it will propagate to the existing local bookmark on future pulls.
@usage 'alias t'
@usage 'long_help #"""
Start tracking given remote bookmarks

A tracked remote bookmark will be imported as a local bookmark of the same name. Changes to it will propagate to the existing local bookmark on future pulls.
"""#'
@usage 'flag --remote help="Remote names to track" var=#true {
            long_help #"""
Remote names to track

By default, the specified pattern matches remote names with glob syntax. You can also use other [string pattern syntax].

If no remote names are given, all remote bookmarks matching the bookmark names will be tracked.

[string pattern syntax]: https://docs.jj-vcs.dev/latest/revsets/#string-patterns
"""#
            arg <REMOTE>… var=#true
        }'
@usage 'arg "<BOOKMARK[@REMOTE]>…" help="Bookmark name patterns or remote bookmark symbols to track" help_long=#"""
Bookmark name patterns or remote bookmark symbols to track

`BOOKMARK` matches bookmark names using glob syntax by default. You can also use other [string pattern syntax].

`BOOKMARK@REMOTE` resolves to a remote bookmark exactly.

[string pattern syntax]: https://docs.jj-vcs.dev/latest/revsets/#string-patterns
"""# var=#true var_min=1'
export def "jj bookmark track" [
    ...bookmark_remote: string,                   # Bookmark name patterns or remote bookmark symbols to track
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --remote: list<string>,                       # Remote names to track
]: nothing -> string {
    ^jj bookmark track ...(nusage argv [...$bookmark_remote] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --remote: $remote
    })
}

# Stop tracking given remote bookmarks
#
# An untracked remote bookmark is just a pointer to the last-fetched remote bookmark. It won't be imported as a local bookmark on future pulls.
#
# If you want to forget a local bookmark while also untracking the corresponding remote bookmarks, use `jj bookmark forget` instead.
@usage r#'long_help #"""
Stop tracking given remote bookmarks

An untracked remote bookmark is just a pointer to the last-fetched remote bookmark. It won't be imported as a local bookmark on future pulls.

If you want to forget a local bookmark while also untracking the corresponding remote bookmarks, use `jj bookmark forget` instead.
"""#'#
@usage 'flag --remote help="Remote names to untrack" var=#true {
            long_help #"""
Remote names to untrack

By default, the specified pattern matches remote names with glob syntax. You can also use other [string pattern syntax].

If no remote names are given, all remote bookmarks matching the bookmark names will be untracked.

[string pattern syntax]: https://docs.jj-vcs.dev/latest/revsets/#string-patterns
"""#
            arg <REMOTE>… var=#true
        }'
@usage 'arg "<BOOKMARK[@REMOTE]>…" help="Bookmark name patterns or remote bookmark symbols to untrack" help_long=#"""
Bookmark name patterns or remote bookmark symbols to untrack

`BOOKMARK` matches bookmark names using glob syntax by default. You can also use other [string pattern syntax].

`BOOKMARK@REMOTE` resolves to a remote bookmark exactly.

[string pattern syntax]: https://docs.jj-vcs.dev/latest/revsets/#string-patterns
"""# var=#true var_min=1'
export def "jj bookmark untrack" [
    ...bookmark_remote: string,                   # Bookmark name patterns or remote bookmark symbols to untrack
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --remote: list<string>,                       # Remote names to untrack
]: nothing -> string {
    ^jj bookmark untrack ...(nusage argv [...$bookmark_remote] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --remote: $remote
    })
}

# Update the description and create a new change on top [default alias: ci]
#
# When called without path arguments or `--interactive`, `jj commit` is equivalent to `jj describe` followed by `jj new`.
#
# When using `--interactive` or path arguments, the selected changes stay in the current commit while the remaining changes are moved to a new working-copy commit on top. This is very similar to `jj split`. Differences include:
#
# * `jj commit` is not interactive by default (it selects all changes).
#
# * `jj commit` doesn't have a `-r` option. It always acts on the working-copy commit (@).
#
# * `jj split` (without `-o`/`-A`/`-B`) will move bookmarks forward from the old change to the child change. `jj commit` doesn't move bookmarks forward.
#
# * `jj split` allows you to move the selected changes to a different destination with `-o`/`-A`/`-B`.
@usage r#'long_help #"""
Update the description and create a new change on top [default alias: ci]

When called without path arguments or `--interactive`, `jj commit` is equivalent to `jj describe` followed by `jj new`.

When using `--interactive` or path arguments, the selected changes stay in the current commit while the remaining changes are moved to a new working-copy commit on top. This is very similar to `jj split`. Differences include:

* `jj commit` is not interactive by default (it selects all changes).

* `jj commit` doesn't have a `-r` option. It always acts on the working-copy commit (@).

* `jj split` (without `-o`/`-A`/`-B`) will move bookmarks forward from the old change to the child change. `jj commit` doesn't move bookmarks forward.

* `jj split` allows you to move the selected changes to a different destination with `-o`/`-A`/`-B`.
"""#'#
@usage 'flag "-i --interactive" help="Interactively choose which changes to include in the current commit"'
@usage 'flag --tool help="Specify diff editor to be used (implies --interactive)" {
        arg <NAME>
    }'
@usage r#'flag "-m --message" help="The change description to use (don't open editor)" var=#true {
        arg <MESSAGE>… var=#true
    }'#
@usage 'flag --editor help="Open an editor to edit the change description" {
        long_help #"""
Open an editor to edit the change description

Forces an editor to open when using `--message` to allow the message to be edited afterwards.
"""#
    }'
@usage 'arg "[FILESETS]…" help="Put these paths in the current commit" required=#false var=#true var_min=1'
@usage 'complete filesets type=path'
export def "jj commit" [
    ...filesets: path@"nusage complete",          # Put these paths in the current commit
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --interactive (-i),                           # Interactively choose which changes to include in the current commit
    --tool: string,                               # Specify diff editor to be used (implies --interactive)
    --message (-m): list<string>,                 # The change description to use (don't open editor)
    --editor,                                     # Open an editor to edit the change description
]: nothing -> string {
    ^jj commit ...(nusage argv [...$filesets] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --interactive: $interactive
        --tool: $tool
        --message: $message
        --editor: $editor
    })
}

# Manage config options
#
# Operates on jj configuration, which comes from the config file and environment variables.
#
# See [`jj help -k config`][config] to know more about file locations, supported config options, and other details about `jj config`.
#
# [config]: https://docs.jj-vcs.dev/latest/config/
@usage 'long_help #"""
Manage config options

Operates on jj configuration, which comes from the config file and environment variables.

See [`jj help -k config`][config] to know more about file locations, supported config options, and other details about `jj config`.

[config]: https://docs.jj-vcs.dev/latest/config/
"""#'
export def "jj config" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj config ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Start an editor on a jj config file
#
# Creates the file if it doesn't already exist regardless of what the editor does.
@usage 'alias e'
@usage r#'long_help #"""
Start an editor on a jj config file.

Creates the file if it doesn't already exist regardless of what the editor does.
"""#'#
@usage 'flag --user help="Target the user-level config"'
@usage 'flag --repo help="Target the repo-level config"'
@usage 'flag --workspace help="Target the workspace-level config"'
@usage 'flag --file help="Target the config file specified by the given path" {
            long_help #"""
Target the config file specified by the given path

The path must point to a valid configuration file location recognized by Jujutsu (such as a user/repo/workspace config, a file inside a `conf.d/` directory, or any file loaded via system configs, `$JJ_CONFIG`, or `--config-file`).

Unlike the global `--config-file` option (which loads an extra config file when running commands), this option specifies which file to inspect, edit, or modify on disk.

If the file does not exist, commands like `set` and `edit` will create it and any missing parent directories.
"""#
            arg <PATH>
        }'
@usage 'group config_target "--user" "--repo" "--workspace" "--file" required=#true'
@usage 'complete path type=path'
export def "jj config edit" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --user,                                       # Target the user-level config
    --repo,                                       # Target the repo-level config
    --workspace,                                  # Target the workspace-level config
    --file: path@"nusage complete",               # Target the config file specified by the given path
]: nothing -> string {
    ^jj config edit ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --user: $user
        --repo: $repo
        --workspace: $workspace
        --file: $file
    })
}

# Find and optionally delete repo-level config directories whose repo path no longer exists
export def "jj config gc" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj config gc ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Get the value of a given config option.
#
# Unlike `jj config list`, the result of `jj config get` is printed without
# extra formatting and therefore is usable in scripting. For example:
#
# $ jj config list user.name
# user.name="Martin von Zweigbergk"
# $ jj config get user.name
# Martin von Zweigbergk
@usage 'alias g'
@usage 'long_help #"""
Get the value of a given config option.

Unlike `jj config list`, the result of `jj config get` is printed without
extra formatting and therefore is usable in scripting. For example:

$ jj config list user.name
user.name="Martin von Zweigbergk"
$ jj config get user.name
Martin von Zweigbergk
"""#'
@usage 'arg <NAME>'
export def "jj config get" [
    name: string,
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj config get ...(nusage argv [$name] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# List variables set in config files, along with their values
@usage 'alias l'
@usage 'flag --include-defaults help="Whether to explicitly include built-in default values in the list" {
            conflicts "--user" "--repo" "--workspace"
        }'
@usage 'flag --include-overridden help="Allow printing overridden values"'
@usage 'flag --user help="Target the user-level config"'
@usage 'flag --repo help="Target the repo-level config"'
@usage 'flag --workspace help="Target the workspace-level config"'
@usage r#'flag "-T --template" help="Render each variable using the given template" {
            long_help #"""
Render each variable using the given template

The following keywords are available in the template expression:

* `name: String`: Config name, in [TOML's "dotted key" format].
* `value: ConfigValue`: Value to be formatted in TOML syntax.
* `overridden: Boolean`: True if the value is shadowed by other.
* `source: String`: Source of the value.
* `path: Option<FsPath>`: Path to the config file.

Can be overridden by the `templates.config_list` setting. To
see a detailed config list, use the `builtin_config_list_detailed`
template.

See [`jj help -k templates`][templates] for more information.

[TOML's "dotted key" format]: https://toml.io/en/v1.0.0#keys

[templates]: https://docs.jj-vcs.dev/latest/templates/
"""#
            arg <TEMPLATE>
        }'#
@usage 'arg "[NAME]" help="An optional name of a specific config option to look up" required=#false'
@usage 'group config_level "--user" "--repo" "--workspace"'
@usage 'output "json" framing="jsonl" { schema "{\n  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",\n  \"title\": \"A configuration value, one line of `jj config list`\",\n  \"type\": \"object\",\n  \"required\": [\n    \"name\",\n    \"value\",\n    \"source\",\n    \"path\",\n    \"is_overridden\"\n  ],\n  \"additionalProperties\": false,\n  \"properties\": {\n    \"name\": {\n      \"type\": \"string\"\n    },\n    \"value\": {\n      \"description\": \"Any TOML value; a TOML datetime is {\\\"$__toml_private_datetime\\\": \\\"...\\\"}\"\n    },\n    \"source\": {\n      \"enum\": [\n        \"default\",\n        \"system\",\n        \"env\",\n        \"user\",\n        \"repo\",\n        \"workspace\",\n        \"cli\"\n      ]\n    },\n    \"path\": {\n      \"type\": [\n        \"string\",\n        \"null\"\n      ]\n    },\n    \"is_overridden\": {\n      \"type\": \"boolean\"\n    }\n  }\n}\n" }'
export def "jj config list" [
    name?: string,                                # An optional name of a specific config option to look up
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --include-defaults,                           # Whether to explicitly include built-in default values in the list
    --include-overridden,                         # Allow printing overridden values
    --user,                                       # Target the user-level config
    --repo,                                       # Target the repo-level config
    --workspace,                                  # Target the workspace-level config
]: nothing -> table<name: string, value: any, source: string, path: oneof<string, nothing>, is_overridden: bool> {
    let text = ^jj config list --template "json(self) ++ \"\\n\"" ...(nusage argv [$name] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --include-defaults: $include_defaults
        --include-overridden: $include_overridden
        --user: $user
        --repo: $repo
        --workspace: $workspace
    })
    nusage decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"title\":\"A configuration value, one line of `jj config list`\",\"type\":\"object\",\"required\":[\"name\",\"value\",\"source\",\"path\",\"is_overridden\"],\"additionalProperties\":false,\"properties\":{\"name\":{\"type\":\"string\"},\"value\":{\"description\":\"Any TOML value; a TOML datetime is {\\\"$__toml_private_datetime\\\": \\\"...\\\"}\"},\"source\":{\"enum\":[\"default\",\"system\",\"env\",\"user\",\"repo\",\"workspace\",\"cli\"]},\"path\":{\"type\":[\"string\",\"null\"]},\"is_overridden\":{\"type\":\"boolean\"}}}" { from json --objects } --lines
}

# Print the paths to the config files
#
# A config file at that path may or may not exist.
#
# If `--repo` or `--workspace` is specified and the config file does not exist, jj will generate a new config directory for this repo/workspace and print the path to the config file in that directory.
#
# See `jj config edit` if you'd like to immediately edit a file.
@usage 'alias p'
@usage r#'long_help #"""
Print the paths to the config files

A config file at that path may or may not exist.

If `--repo` or `--workspace` is specified and the config file does not exist, jj will generate a new config directory for this repo/workspace and print the path to the config file in that directory.

See `jj config edit` if you'd like to immediately edit a file.
"""#'#
@usage 'flag --user help="Target the user-level config"'
@usage 'flag --repo help="Target the repo-level config"'
@usage 'flag --workspace help="Target the workspace-level config"'
@usage 'group config_level "--user" "--repo" "--workspace" required=#true'
export def "jj config path" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --user,                                       # Target the user-level config
    --repo,                                       # Target the repo-level config
    --workspace,                                  # Target the workspace-level config
]: nothing -> string {
    ^jj config path ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --user: $user
        --repo: $repo
        --workspace: $workspace
    })
}

# Update a config file to set the given option to a given value
@usage 'alias s'
@usage 'flag --user help="Target the user-level config"'
@usage 'flag --repo help="Target the repo-level config"'
@usage 'flag --workspace help="Target the workspace-level config"'
@usage 'flag --file help="Target the config file specified by the given path" {
            long_help #"""
Target the config file specified by the given path

The path must point to a valid configuration file location recognized by Jujutsu (such as a user/repo/workspace config, a file inside a `conf.d/` directory, or any file loaded via system configs, `$JJ_CONFIG`, or `--config-file`).

Unlike the global `--config-file` option (which loads an extra config file when running commands), this option specifies which file to inspect, edit, or modify on disk.

If the file does not exist, commands like `set` and `edit` will create it and any missing parent directories.
"""#
            arg <PATH>
        }'
@usage 'arg <NAME>'
@usage r#'arg <VALUE> help="New value to set" help_long=#"""
New value to set

The value should be specified as a TOML expression. If string value isn't enclosed by any TOML constructs (such as apostrophes or array notation), quotes can be omitted. Note that the value may also need shell quoting. TOML multi-line strings can be useful if the value contains apostrophes. For example, to set `foo.bar` to the string "{don't}" use `jj config set --user foo.bar "'''{don't}'''"`. This is valid in both Bash and Fish.

Alternative, e.g. to avoid dealing with shell quoting, use `jj config edit` to edit the TOML file directly.
"""#'#
@usage 'group config_target "--user" "--repo" "--workspace" "--file" required=#true'
@usage 'complete path type=path'
export def "jj config set" [
    name: string,
    value: string,                                # New value to set
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --user,                                       # Target the user-level config
    --repo,                                       # Target the repo-level config
    --workspace,                                  # Target the workspace-level config
    --file: path@"nusage complete",               # Target the config file specified by the given path
]: nothing -> string {
    ^jj config set ...(nusage argv [$name $value] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --user: $user
        --repo: $repo
        --workspace: $workspace
        --file: $file
    })
}

# Update a config file to unset the given option
@usage 'alias u'
@usage 'flag --user help="Target the user-level config"'
@usage 'flag --repo help="Target the repo-level config"'
@usage 'flag --workspace help="Target the workspace-level config"'
@usage 'flag --file help="Target the config file specified by the given path" {
            long_help #"""
Target the config file specified by the given path

The path must point to a valid configuration file location recognized by Jujutsu (such as a user/repo/workspace config, a file inside a `conf.d/` directory, or any file loaded via system configs, `$JJ_CONFIG`, or `--config-file`).

Unlike the global `--config-file` option (which loads an extra config file when running commands), this option specifies which file to inspect, edit, or modify on disk.

If the file does not exist, commands like `set` and `edit` will create it and any missing parent directories.
"""#
            arg <PATH>
        }'
@usage 'arg <NAME>'
@usage 'group config_target "--user" "--repo" "--workspace" "--file" required=#true'
@usage 'complete path type=path'
export def "jj config unset" [
    name: string,
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --user,                                       # Target the user-level config
    --repo,                                       # Target the repo-level config
    --workspace,                                  # Target the workspace-level config
    --file: path@"nusage complete",               # Target the config file specified by the given path
]: nothing -> string {
    ^jj config unset ...(nusage argv [$name] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --user: $user
        --repo: $repo
        --workspace: $workspace
        --file: $file
    })
}

# Converge divergent changes
#
# Attempts to resolve divergence by replacing two or more visible revisions for a given change with a single revision. `jj converge` evaluates the revset(s) given by the `--revisions` arg (or the `revsets.converge` setting if none are specified) and groups the resulting revisions by change ID. Change IDs with more than one revision are divergent.
#
# If there is no divergence it returns successfully. If there is more than one divergent change it prompts the user to choose one. The command then applies heuristics to try to automatically come up with a good solution (i.e. a new revision) that replaces the divergent revisions. If the heuristics are inconclusive `jj converge` falls back to prompting the user. Use `--no-interactive` to print a warning instead of prompting the user.
#
# The user may be prompted for any of the following: to merge revision descriptions, to choose parents for the solution, and/or (very rarely) to choose a revision author.
#
# When a solution is found, the new revision replaces the divergent revisions of the specific change ID (but only those matching the revsets; if there are other visible revisions for the same change ID outside the revset, those will remain and you will still have divergence, though it will be reduced). Descendants of the divergent revisions are rebased onto the solution, and local bookmarks pointing to any divergent revision are updated to point to the solution.
#
# Note that there may be file conflicts in the solution whether or not there were conflicts to begin with.
#
# The modifications made by `jj converge` can be reviewed by `jj op show -p`. You can inspect the change evolution with `jj evolog`. If not satisfied with the result you can run `jj undo`.
@usage 'long_help #"""
Converge divergent changes

Attempts to resolve divergence by replacing two or more visible revisions for a given change with a single revision. `jj converge` evaluates the revset(s) given by the `--revisions` arg (or the `revsets.converge` setting if none are specified) and groups the resulting revisions by change ID. Change IDs with more than one revision are divergent.

If there is no divergence it returns successfully. If there is more than one divergent change it prompts the user to choose one. The command then applies heuristics to try to automatically come up with a good solution (i.e. a new revision) that replaces the divergent revisions. If the heuristics are inconclusive `jj converge` falls back to prompting the user. Use `--no-interactive` to print a warning instead of prompting the user.

The user may be prompted for any of the following: to merge revision descriptions, to choose parents for the solution, and/or (very rarely) to choose a revision author.

When a solution is found, the new revision replaces the divergent revisions of the specific change ID (but only those matching the revsets; if there are other visible revisions for the same change ID outside the revset, those will remain and you will still have divergence, though it will be reduced). Descendants of the divergent revisions are rebased onto the solution, and local bookmarks pointing to any divergent revision are updated to point to the solution.

Note that there may be file conflicts in the solution whether or not there were conflicts to begin with.

The modifications made by `jj converge` can be reviewed by `jj op show -p`. You can inspect the change evolution with `jj evolog`. If not satisfied with the result you can run `jj undo`.
"""#'
@usage 'flag "-r --revision" help="The search space to look for divergent revisions" var=#true {
        alias "--revisions" hide=#true
        long_help #"""
The search space to look for divergent revisions

If no revisions are specified, this defaults to the `revsets.converge` setting.
"""#
        arg <REVSETS>… var=#true
    }'
@usage 'flag --no-interactive help="Do not prompt the user for help resolving divergence" conflicts=--interactive {
        long_help #"""
Do not prompt the user for help resolving divergence

If the command cannot solve divergence automatically it will print a warning and exit without making any changes (divergence will still be present).
"""#
    }'
@usage 'flag "-i --interactive" help="No-op flag to pair with --no-interactive" hide=#true'
export def "jj converge" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --revision (-r): list<string>,                # The search space to look for divergent revisions
    --no-interactive,                             # Do not prompt the user for help resolving divergence
]: nothing -> string {
    ^jj converge ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --revision: $revision
        --no-interactive: $no_interactive
    })
}

# Update the change description or other metadata [default alias: desc]
#
# Starts an editor to let you edit the description of changes. Set `ui.editor` to customize your editor. See `jj help -k config` or the [editor docs] for more information on how the editor is chosen.
#
# [editor docs]: https://docs.jj-vcs.dev/latest/config/#editor
@usage 'long_help #"""
Update the change description or other metadata [default alias: desc]

Starts an editor to let you edit the description of changes. Set `ui.editor` to customize your editor. See `jj help -k config` or the [editor docs] for more information on how the editor is chosen.

[editor docs]: https://docs.jj-vcs.dev/latest/config/#editor
"""#'
@usage 'flag -r var=#true hide=#true {
        arg <REVSETS>… var=#true
    }'
@usage r#'flag "-m --message" help="The change description to use (don't open editor)" var=#true conflicts=--stdin {
        long_help #"""
The change description to use (don't open editor)

If multiple revisions are specified, the same description will be used for all of them.
"""#
        arg <MESSAGE>… var=#true
    }'#
@usage 'flag --stdin help="Read the change description from stdin" {
        long_help #"""
Read the change description from stdin

If multiple revisions are specified, the same description will be used for all of them.
"""#
    }'
@usage 'flag --editor help="Open an editor to edit the change description" {
        long_help #"""
Open an editor to edit the change description

Forces an editor to open when using `--stdin` or `--message` to allow the message to be edited afterwards.
"""#
    }'
@usage 'arg "[REVSETS]…" help="The revision(s) whose description to edit (default: @) [aliases: -r]" required=#false var=#true var_min=1'
export def "jj describe" [
    ...revsets: string,                           # The revision(s) whose description to edit (default: @) [aliases: -r]
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --message (-m): list<string>,                 # The change description to use (don't open editor)
    --stdin,                                      # Read the change description from stdin
    --editor,                                     # Open an editor to edit the change description
]: nothing -> string {
    ^jj describe ...(nusage argv [...$revsets] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --message: $message
        --stdin: $stdin
        --editor: $editor
    })
}

# Compare file contents between two revisions
#
# With the `-r` option, shows the changes compared to the parent revision. If there are several parent revisions (i.e., the given revision is a merge), then they will be merged and the changes from the result to the given revision will be shown.
#
# With the `--from` and/or `--to` options, shows the difference from/to the given revisions. If either is left out, it defaults to the working-copy commit. For example, `jj diff --from main` shows the changes from "main" (perhaps a bookmark name) to the working-copy commit.
#
# If no option is specified, it defaults to `-r @`.
@usage 'long_help #"""
Compare file contents between two revisions

With the `-r` option, shows the changes compared to the parent revision. If there are several parent revisions (i.e., the given revision is a merge), then they will be merged and the changes from the result to the given revision will be shown.

With the `--from` and/or `--to` options, shows the difference from/to the given revisions. If either is left out, it defaults to the working-copy commit. For example, `jj diff --from main` shows the changes from "main" (perhaps a bookmark name) to the working-copy commit.

If no option is specified, it defaults to `-r @`.
"""#'
@usage r#'flag "-r --revisions" help="Show changes in these revisions" var=#true {
        alias "--revision" hide=#true
        long_help #"""
Show changes in these revisions

If there are multiple revisions, then the total diff for all of them will be shown. For example, if you have a linear chain of revisions A..D, then `jj diff -r B::D` equals `jj diff --from A --to D`. Multiple heads and/or roots are supported, but gaps in the revset are not supported (e.g. `jj diff -r 'A|C'` in a linear chain A..C).

If a revision is a merge commit, this shows changes *from* the automatic merge of the contents of all of its parents *to* the contents of the revision itself.

If none of `-r`, `-f`, or `-t` is provided, then the default is `-r @`.
"""#
        arg <REVSETS>… var=#true
    }'#
@usage 'flag "-f --from" help="Show changes from this revision" conflicts=--revisions {
        long_help #"""
Show changes from this revision

If none of `-r`, `-f`, or `-t` is provided, then the default is `-r @`.
"""#
        arg <REVSET>
    }'
@usage 'flag "-t --to" help="Show changes to this revision" conflicts=--revisions {
        long_help #"""
Show changes to this revision

If none of `-r`, `-f`, or `-t` is provided, then the default is `-r @`.
"""#
        arg <REVSET>
    }'
@usage 'flag "-T --template" help="Render each file diff entry using the given template" help_heading="Diff Formatting Options" {
        long_help #"""
Render each file diff entry using the given template

All 0-argument methods of the [`TreeDiffEntry` type][TreeDiffEntry] are available as keywords in the template expression. See [`jj help -k templates`][templates] for more information.

[TreeDiffEntry]: https://docs.jj-vcs.dev/latest/templates/#treediffentry-type

[templates]: https://docs.jj-vcs.dev/latest/templates/
"""#
        conflicts "--summary" "--stat" "--types" "--name-only" "--git" "--color-words" "--tool"
        arg <TEMPLATE>
    }'
@usage 'flag "-s --summary" help="For each path, show only whether it was modified, added, or deleted" help_heading="Diff Formatting Options"'
@usage 'flag --stat help="Show a histogram of the changes" help_heading="Diff Formatting Options"'
@usage r#'flag --types help="For each path, show only its type before and after" help_heading="Diff Formatting Options" {
        long_help #"""
For each path, show only its type before and after

The diff is shown as two letters. The first letter indicates the type before and the second letter indicates the type after. '-' indicates that the path was not present, 'F' represents a regular file, `L' represents a symlink, 'C' represents a conflict, and 'G' represents a Git submodule.
"""#
    }'#
@usage r#'flag --name-only help="For each path, show only its path" help_heading="Diff Formatting Options" {
        long_help #"""
For each path, show only its path

Typically useful for shell commands like: `jj diff -r @- --name-only | xargs perl -pi -e's/OLD/NEW/g`
"""#
    }'#
@usage 'flag --git help="Show a Git-format diff" help_heading="Diff Formatting Options"'
@usage 'flag --color-words help="Show a word-level diff with changes indicated only by color" help_heading="Diff Formatting Options"'
@usage 'flag --tool help="Generate diff by external command" help_heading="Diff Formatting Options" {
        long_help #"""
Generate diff by external command

A builtin format can also be specified as `:<name>`. For example, `--tool=:git` is equivalent to `--git`.
"""#
        arg <TOOL>
    }'
@usage 'flag --context help="Number of lines of context to show" help_heading="Diff Formatting Options" {
        arg <CONTEXT>
    }'
@usage 'flag "-w --ignore-all-space" help="Ignore whitespace when comparing lines" help_heading="Diff Formatting Options"'
@usage 'flag "-b --ignore-space-change" help="Ignore changes in amount of whitespace when comparing lines" conflicts=--ignore-all-space help_heading="Diff Formatting Options"'
@usage 'arg "[FILESETS]…" help="Restrict the diff to these paths" required=#false var=#true var_min=1'
@usage 'group short-format "--summary" "--stat" "--types" "--name-only"'
@usage 'group long-format "--git" "--color-words"'
@usage 'complete filesets type=path'
export def "jj diff" [
    ...filesets: path@"nusage complete",          # Restrict the diff to these paths
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --revisions (-r): list<string>,               # Show changes in these revisions
    --from (-f): string,                          # Show changes from this revision
    --to (-t): string,                            # Show changes to this revision
    --template (-T): string,                      # Render each file diff entry using the given template
    --summary (-s),                               # For each path, show only whether it was modified, added, or deleted
    --stat,                                       # Show a histogram of the changes
    --types,                                      # For each path, show only its type before and after
    --name-only,                                  # For each path, show only its path
    --git,                                        # Show a Git-format diff
    --color-words,                                # Show a word-level diff with changes indicated only by color
    --tool: string,                               # Generate diff by external command
    --context: string,                            # Number of lines of context to show
    --ignore-all-space (-w),                      # Ignore whitespace when comparing lines
    --ignore-space-change (-b),                   # Ignore changes in amount of whitespace when comparing lines
]: nothing -> string {
    ^jj diff ...(nusage argv [...$filesets] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --revisions: $revisions
        --from: $from
        --to: $to
        --template: $template
        --summary: $summary
        --stat: $stat
        --types: $types
        --name-only: $name_only
        --git: $git
        --color-words: $color_words
        --tool: $tool
        --context: $context
        --ignore-all-space: $ignore_all_space
        --ignore-space-change: $ignore_space_change
    })
}

# Touch up the content changes in a revision with a diff editor
#
# With the `-r` option, starts a [diff editor] on the changes in the revision.
#
# With the `--from` and/or `--to` options, starts a [diff editor] comparing the "from" revision to the "to" revision.
#
# [diff editor]: https://docs.jj-vcs.dev/latest/config/#editing-diffs
#
# Edit the right side of the diff until it looks the way you want. Once you close the editor, the revision specified with `-r` or `--to` will be updated. Unless `--restore-descendants` is used, descendants will be rebased on top as usual, which may result in conflicts.
#
# See `jj restore` if you want to move entire files from one revision to another. For moving changes between revisions, see `jj squash -i`.
@usage 'long_help #"""
Touch up the content changes in a revision with a diff editor

With the `-r` option, starts a [diff editor] on the changes in the revision.

With the `--from` and/or `--to` options, starts a [diff editor] comparing the "from" revision to the "to" revision.

[diff editor]: https://docs.jj-vcs.dev/latest/config/#editing-diffs

Edit the right side of the diff until it looks the way you want. Once you close the editor, the revision specified with `-r` or `--to` will be updated. Unless `--restore-descendants` is used, descendants will be rebased on top as usual, which may result in conflicts.

See `jj restore` if you want to move entire files from one revision to another. For moving changes between revisions, see `jj squash -i`.
"""#'
@usage 'flag "-r --revision" help="The revision to touch up" {
        long_help #"""
The revision to touch up

Defaults to @ if neither --to nor --from are specified.
"""#
        arg <REVSET>
    }'
@usage 'flag "-f --from" help="Show changes from this revision" conflicts=--revision {
        long_help #"""
Show changes from this revision

Defaults to @ if --to is specified.
"""#
        arg <REVSET>
    }'
@usage 'flag "-t --to" help="Edit changes in this revision" conflicts=--revision {
        long_help #"""
Edit changes in this revision

Defaults to @ if --from is specified.
"""#
        arg <REVSET>
    }'
@usage 'flag --tool help="Specify diff editor to be used" {
        arg <NAME>
    }'
@usage 'flag --restore-descendants help="Preserve the content (not the diff) when rebasing descendants" {
        long_help #"""
Preserve the content (not the diff) when rebasing descendants

When rebasing a descendant on top of the rewritten revision, its diff compared to its parent(s) is normally preserved, i.e. the same way that descendants are always rebased. This flag makes it so the content/state is preserved instead of preserving the diff.
"""#
    }'
@usage 'arg "[FILESETS]…" help="Edit only these paths (unmatched paths will remain unchanged)" required=#false var=#true var_min=1'
@usage 'complete filesets type=path'
export def "jj diffedit" [
    ...filesets: path@"nusage complete",          # Edit only these paths (unmatched paths will remain unchanged)
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --revision (-r): string,                      # The revision to touch up
    --from (-f): string,                          # Show changes from this revision
    --to (-t): string,                            # Edit changes in this revision
    --tool: string,                               # Specify diff editor to be used
    --restore-descendants,                        # Preserve the content (not the diff) when rebasing descendants
]: nothing -> string {
    ^jj diffedit ...(nusage argv [...$filesets] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --revision: $revision
        --from: $from
        --to: $to
        --tool: $tool
        --restore-descendants: $restore_descendants
    })
}

# Create new changes with the same content as existing ones
#
# When none of the `--onto`, `--insert-after`, or `--insert-before` arguments are provided, commits will be duplicated onto their existing parents or onto other newly duplicated commits.
#
# When any of the `--onto`, `--insert-after`, or `--insert-before` arguments are provided, the roots of the specified commits will be duplicated onto the destination indicated by the arguments. Other specified commits will be duplicated onto these newly duplicated commits. If the `--insert-after` or `--insert-before` arguments are provided, the new children indicated by the arguments will be rebased onto the heads of the specified commits.
#
# By default, the duplicated commits retain the descriptions of the originals. This can be customized with the `templates.duplicate_description` setting.
@usage 'long_help #"""
Create new changes with the same content as existing ones

When none of the `--onto`, `--insert-after`, or `--insert-before` arguments are provided, commits will be duplicated onto their existing parents or onto other newly duplicated commits.

When any of the `--onto`, `--insert-after`, or `--insert-before` arguments are provided, the roots of the specified commits will be duplicated onto the destination indicated by the arguments. Other specified commits will be duplicated onto these newly duplicated commits. If the `--insert-after` or `--insert-before` arguments are provided, the new children indicated by the arguments will be rebased onto the heads of the specified commits.

By default, the duplicated commits retain the descriptions of the originals. This can be customized with the `templates.duplicate_description` setting.
"""#'
@usage 'flag -r var=#true hide=#true {
        arg <REVSETS>… var=#true
    }'
@usage 'flag "-o -d --onto --destination" help="The revision(s) to duplicate onto (can be repeated to create a merge commit)" var=#true {
        arg <REVSETS>… var=#true
    }'
@usage 'flag "-A --insert-after --after" help="The revision(s) to insert after (can be repeated to create a merge commit)" var=#true conflicts=--onto {
        arg <REVSETS>… var=#true
    }'
@usage 'flag "-B --insert-before --before" help="The revision(s) to insert before (can be repeated to create a merge commit)" var=#true conflicts=--onto {
        arg <REVSETS>… var=#true
    }'
@usage 'arg "[REVSETS]…" help="The revision(s) to duplicate (default: @) [aliases: -r]" required=#false var=#true var_min=1'
export def "jj duplicate" [
    ...revsets: string,                           # The revision(s) to duplicate (default: @) [aliases: -r]
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --onto (-o): list<string>,                    # The revision(s) to duplicate onto (can be repeated to create a merge commit)
    --insert-after (-A): list<string>,            # The revision(s) to insert after (can be repeated to create a merge commit)
    --insert-before (-B): list<string>,           # The revision(s) to insert before (can be repeated to create a merge commit)
]: nothing -> string {
    ^jj duplicate ...(nusage argv [...$revsets] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --onto: $onto
        --insert-after: $insert_after
        --insert-before: $insert_before
    })
}

# Sets the specified revision as the working-copy revision
#
# Note: it is [generally recommended] to instead use `jj new` and `jj squash`.
#
# [generally recommended]: https://docs.jj-vcs.dev/latest/FAQ#how-do-i-resume-working-on-an-existing-change
@usage 'long_help #"""
Sets the specified revision as the working-copy revision

Note: it is [generally recommended] to instead use `jj new` and `jj squash`.

[generally recommended]: https://docs.jj-vcs.dev/latest/FAQ#how-do-i-resume-working-on-an-existing-change
"""#'
@usage 'flag -r hide=#true {
        arg <REVSET>
    }'
@usage 'arg "[REVSET]" help="The commit to edit [aliases: -r]" required=#false'
export def "jj edit" [
    revset?: string,                              # The commit to edit [aliases: -r]
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj edit ...(nusage argv [$revset] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Show how a change has evolved over time
#
# Lists the previous commits which a change has pointed to. The current commit of a change evolves when the change is updated, rebased, etc.
@usage 'alias evolution-log'
@usage 'alias obslog hide=#true'
@usage 'long_help #"""
Show how a change has evolved over time

Lists the previous commits which a change has pointed to. The current commit of a change evolves when the change is updated, rebased, etc.
"""#'
@usage 'flag "-r --revisions" help="Follow changes from these revisions" var=#true default=@ {
        alias "--revision" hide=#true
        arg <REVSETS>… var=#true
    }'
@usage 'flag "-n --limit" help="Limit number of revisions to show" {
        long_help #"""
Limit number of revisions to show

Applied after revisions are reordered topologically, but before being reversed.
"""#
        arg <LIMIT>
    }'
@usage 'flag --reversed help="Show revisions in the opposite order (older revisions first)"'
@usage 'flag "-G --no-graph" help="Show a flat list of revisions instead of a graph"'
@usage 'flag "-T --template" help="Render each revision using the given template" {
        long_help #"""
Render each revision using the given template

All 0-argument methods of the [`CommitEvolutionEntry` type][CommitEvolutionEntry] are available as keywords in the template expression. See [`jj help -k templates`][templates] for more information.

If not specified, this defaults to the `templates.evolog` setting.

[CommitEvolutionEntry]: https://docs.jj-vcs.dev/latest/templates/#commitevolutionentry-type

[templates]: https://docs.jj-vcs.dev/latest/templates/
"""#
        arg <TEMPLATE>
    }'
@usage 'flag "-p --patch" help="Show patch compared to the previous version of this change" {
        long_help #"""
Show patch compared to the previous version of this change

If the previous version has different parents, it will be temporarily rebased to the parents of the new version, so the diff is not contaminated by unrelated changes.
"""#
    }'
@usage 'flag "-s --summary" help="For each path, show only whether it was modified, added, or deleted" help_heading="Diff Formatting Options"'
@usage 'flag --stat help="Show a histogram of the changes" help_heading="Diff Formatting Options"'
@usage r#'flag --types help="For each path, show only its type before and after" help_heading="Diff Formatting Options" {
        long_help #"""
For each path, show only its type before and after

The diff is shown as two letters. The first letter indicates the type before and the second letter indicates the type after. '-' indicates that the path was not present, 'F' represents a regular file, `L' represents a symlink, 'C' represents a conflict, and 'G' represents a Git submodule.
"""#
    }'#
@usage r#'flag --name-only help="For each path, show only its path" help_heading="Diff Formatting Options" {
        long_help #"""
For each path, show only its path

Typically useful for shell commands like: `jj diff -r @- --name-only | xargs perl -pi -e's/OLD/NEW/g`
"""#
    }'#
@usage 'flag --git help="Show a Git-format diff" help_heading="Diff Formatting Options"'
@usage 'flag --color-words help="Show a word-level diff with changes indicated only by color" help_heading="Diff Formatting Options"'
@usage 'flag --tool help="Generate diff by external command" help_heading="Diff Formatting Options" {
        long_help #"""
Generate diff by external command

A builtin format can also be specified as `:<name>`. For example, `--tool=:git` is equivalent to `--git`.
"""#
        arg <TOOL>
    }'
@usage 'flag --context help="Number of lines of context to show" help_heading="Diff Formatting Options" {
        arg <CONTEXT>
    }'
@usage 'flag --ignore-all-space help="Ignore whitespace when comparing lines" help_heading="Diff Formatting Options"'
@usage 'flag --ignore-space-change help="Ignore changes in amount of whitespace when comparing lines" conflicts=--ignore-all-space help_heading="Diff Formatting Options"'
@usage 'group short-format "--summary" "--stat" "--types" "--name-only"'
@usage 'group long-format "--git" "--color-words"'
@usage 'output "json" framing="jsonl" { schema "{\n  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",\n  \"title\": \"An entry of `jj evolog`: the commit, and the operation that wrote it, if recorded\",\n  \"type\": \"object\",\n  \"required\": [\n    \"commit\",\n    \"operation\"\n  ],\n  \"additionalProperties\": false,\n  \"properties\": {\n    \"commit\": {\n      \"$ref\": \"#/$defs/commit\"\n    },\n    \"operation\": {\n      \"anyOf\": [\n        {\n          \"$ref\": \"#/$defs/operation\"\n        },\n        {\n          \"type\": \"null\"\n        }\n      ]\n    }\n  },\n  \"$defs\": {\n    \"commit_id\": {\n      \"type\": \"string\",\n      \"pattern\": \"^[0-9a-f]+$\"\n    },\n    \"signature\": {\n      \"type\": \"object\",\n      \"required\": [\n        \"name\",\n        \"email\",\n        \"timestamp\"\n      ],\n      \"additionalProperties\": false,\n      \"properties\": {\n        \"name\": {\n          \"type\": \"string\"\n        },\n        \"email\": {\n          \"type\": \"string\"\n        },\n        \"timestamp\": {\n          \"type\": \"string\",\n          \"format\": \"date-time\"\n        }\n      }\n    },\n    \"commit\": {\n      \"type\": \"object\",\n      \"required\": [\n        \"commit_id\",\n        \"parents\",\n        \"change_id\",\n        \"description\",\n        \"author\",\n        \"committer\"\n      ],\n      \"additionalProperties\": false,\n      \"properties\": {\n        \"commit_id\": {\n          \"$ref\": \"#/$defs/commit_id\"\n        },\n        \"parents\": {\n          \"type\": \"array\",\n          \"items\": {\n            \"$ref\": \"#/$defs/commit_id\"\n          }\n        },\n        \"change_id\": {\n          \"type\": \"string\",\n          \"pattern\": \"^[k-z]+$\"\n        },\n        \"description\": {\n          \"type\": \"string\"\n        },\n        \"author\": {\n          \"$ref\": \"#/$defs/signature\"\n        },\n        \"committer\": {\n          \"$ref\": \"#/$defs/signature\"\n        }\n      }\n    },\n    \"operation\": {\n      \"type\": \"object\",\n      \"required\": [\n        \"id\",\n        \"parents\",\n        \"time\",\n        \"description\",\n        \"hostname\",\n        \"username\",\n        \"is_snapshot\",\n        \"workspace_name\",\n        \"attributes\"\n      ],\n      \"additionalProperties\": false,\n      \"properties\": {\n        \"id\": {\n          \"type\": \"string\",\n          \"pattern\": \"^[0-9a-f]+$\"\n        },\n        \"parents\": {\n          \"type\": \"array\",\n          \"items\": {\n            \"type\": \"string\",\n            \"pattern\": \"^[0-9a-f]+$\"\n          }\n        },\n        \"time\": {\n          \"type\": \"object\",\n          \"required\": [\n            \"start\",\n            \"end\"\n          ],\n          \"additionalProperties\": false,\n          \"properties\": {\n            \"start\": {\n              \"type\": \"string\",\n              \"format\": \"date-time\"\n            },\n            \"end\": {\n              \"type\": \"string\",\n              \"format\": \"date-time\"\n            }\n          }\n        },\n        \"description\": {\n          \"type\": \"string\"\n        },\n        \"hostname\": {\n          \"type\": \"string\"\n        },\n        \"username\": {\n          \"type\": \"string\"\n        },\n        \"is_snapshot\": {\n          \"type\": \"boolean\"\n        },\n        \"workspace_name\": {\n          \"type\": [\n            \"string\",\n            \"null\"\n          ]\n        },\n        \"attributes\": {\n          \"type\": \"object\",\n          \"additionalProperties\": {\n            \"type\": \"string\"\n          }\n        }\n      }\n    }\n  }\n}\n" }'
export def "jj evolog" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --revisions (-r): list<string>,               # Follow changes from these revisions
    --limit (-n): string,                         # Limit number of revisions to show
    --reversed,                                   # Show revisions in the opposite order (older revisions first)
    --patch (-p),                                 # Show patch compared to the previous version of this change
    --summary (-s),                               # For each path, show only whether it was modified, added, or deleted
    --stat,                                       # Show a histogram of the changes
    --types,                                      # For each path, show only its type before and after
    --name-only,                                  # For each path, show only its path
    --git,                                        # Show a Git-format diff
    --color-words,                                # Show a word-level diff with changes indicated only by color
    --tool: string,                               # Generate diff by external command
    --context: string,                            # Number of lines of context to show
    --ignore-all-space,                           # Ignore whitespace when comparing lines
    --ignore-space-change,                        # Ignore changes in amount of whitespace when comparing lines
]: nothing -> table<commit: record<commit_id: string, parents: list<string>, change_id: string, description: string, author: record<name: string, email: string, timestamp: datetime>, committer: record<name: string, email: string, timestamp: datetime>>, operation: oneof<record<id: string, parents: list<string>, time: record<start: datetime, end: datetime>, description: string, hostname: string, username: string, is_snapshot: bool, workspace_name: oneof<string, nothing>, attributes: record>, nothing>> {
    let text = ^jj evolog --no-graph --template "json(self) ++ \"\\n\"" ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --revisions: $revisions
        --limit: $limit
        --reversed: $reversed
        --patch: $patch
        --summary: $summary
        --stat: $stat
        --types: $types
        --name-only: $name_only
        --git: $git
        --color-words: $color_words
        --tool: $tool
        --context: $context
        --ignore-all-space: $ignore_all_space
        --ignore-space-change: $ignore_space_change
    })
    nusage decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"title\":\"An entry of `jj evolog`: the commit, and the operation that wrote it, if recorded\",\"type\":\"object\",\"required\":[\"commit\",\"operation\"],\"additionalProperties\":false,\"properties\":{\"commit\":{\"$ref\":\"#/$defs/commit\"},\"operation\":{\"anyOf\":[{\"$ref\":\"#/$defs/operation\"},{\"type\":\"null\"}]}},\"$defs\":{\"commit_id\":{\"type\":\"string\",\"pattern\":\"^[0-9a-f]+$\"},\"signature\":{\"type\":\"object\",\"required\":[\"name\",\"email\",\"timestamp\"],\"additionalProperties\":false,\"properties\":{\"name\":{\"type\":\"string\"},\"email\":{\"type\":\"string\"},\"timestamp\":{\"type\":\"string\",\"format\":\"date-time\"}}},\"commit\":{\"type\":\"object\",\"required\":[\"commit_id\",\"parents\",\"change_id\",\"description\",\"author\",\"committer\"],\"additionalProperties\":false,\"properties\":{\"commit_id\":{\"$ref\":\"#/$defs/commit_id\"},\"parents\":{\"type\":\"array\",\"items\":{\"$ref\":\"#/$defs/commit_id\"}},\"change_id\":{\"type\":\"string\",\"pattern\":\"^[k-z]+$\"},\"description\":{\"type\":\"string\"},\"author\":{\"$ref\":\"#/$defs/signature\"},\"committer\":{\"$ref\":\"#/$defs/signature\"}}},\"operation\":{\"type\":\"object\",\"required\":[\"id\",\"parents\",\"time\",\"description\",\"hostname\",\"username\",\"is_snapshot\",\"workspace_name\",\"attributes\"],\"additionalProperties\":false,\"properties\":{\"id\":{\"type\":\"string\",\"pattern\":\"^[0-9a-f]+$\"},\"parents\":{\"type\":\"array\",\"items\":{\"type\":\"string\",\"pattern\":\"^[0-9a-f]+$\"}},\"time\":{\"type\":\"object\",\"required\":[\"start\",\"end\"],\"additionalProperties\":false,\"properties\":{\"start\":{\"type\":\"string\",\"format\":\"date-time\"},\"end\":{\"type\":\"string\",\"format\":\"date-time\"}}},\"description\":{\"type\":\"string\"},\"hostname\":{\"type\":\"string\"},\"username\":{\"type\":\"string\"},\"is_snapshot\":{\"type\":\"boolean\"},\"workspace_name\":{\"type\":[\"string\",\"null\"]},\"attributes\":{\"type\":\"object\",\"additionalProperties\":{\"type\":\"string\"}}}}}}" { from json --objects | into datetime commit.author.timestamp | into datetime commit.committer.timestamp | update operation {|row| if $row.operation == null { null } else { $row.operation | into datetime time.start } } | update operation {|row| if $row.operation == null { null } else { $row.operation | into datetime time.end } } } --lines
}

# File operations
export def "jj file" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj file ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Show the source change for each line of the target file
#
# Annotates a revision line by line. Each line includes the source change that introduced the associated line. A path to the desired file must be provided.
@usage 'long_help #"""
Show the source change for each line of the target file.

Annotates a revision line by line. Each line includes the source change that introduced the associated line. A path to the desired file must be provided.
"""#'
@usage 'flag "-r --revision" help="an optional revision to start at" {
            arg <REVSET>
        }'
@usage 'flag "-T --template" help="Render each line using the given template" {
            long_help #"""
Render each line using the given template

All 0-argument methods of the [`AnnotationLine` type][AnnotationLine] are available as keywords in the template expression. See [`jj help -k templates`][templates] for more information.

If not specified, this defaults to the `templates.file_annotate` setting.

[AnnotationLine]: https://docs.jj-vcs.dev/latest/templates/#annotationline-type

[templates]: https://docs.jj-vcs.dev/latest/templates/
"""#
            arg <TEMPLATE>
        }'
@usage 'arg <PATH> help="the file to annotate"'
@usage 'complete path type=path'
export def "jj file annotate" [
    path: path@"nusage complete",                 # the file to annotate
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --revision (-r): string,                      # an optional revision to start at
    --template (-T): string,                      # Render each line using the given template
]: nothing -> string {
    ^jj file annotate ...(nusage argv [$path] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --revision: $revision
        --template: $template
    })
}

# Sets or removes the executable bit for paths in the repo
#
# Unlike the POSIX `chmod`, `jj file chmod` also works on Windows, on conflicted files, and on arbitrary revisions.
@usage 'long_help #"""
Sets or removes the executable bit for paths in the repo

Unlike the POSIX `chmod`, `jj file chmod` also works on Windows, on conflicted files, and on arbitrary revisions.
"""#'
@usage 'flag "-r --revision" help="The revision to update" default=@ {
            arg <REVSET>
        }'
@usage 'arg <MODE> {
            choices {
                choice n help="Make a path non-executable (alias: normal)" {
                    alias normal hide=#true
                }
                choice x help="Make a path executable (alias: executable)" {
                    alias executable hide=#true
                }
            }
        }'
@usage 'arg <FILESETS>… help="Paths to change the executable bit for" var=#true var_min=1'
@usage 'complete filesets type=path'
export def "jj file chmod" [
    mode: string@[n x],
    ...filesets: path@"nusage complete",          # Paths to change the executable bit for
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --revision (-r): string,                      # The revision to update
]: nothing -> string {
    ^jj file chmod ...(nusage argv [$mode ...$filesets] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --revision: $revision
    })
}

# Delete files from the given revision
#
# Removes all files matched by the given filesets from the specified revision. Descendants are rebased on top of the rewritten commit.
@usage 'long_help #"""
Delete files from the given revision

Removes all files matched by the given filesets from the specified revision. Descendants are rebased on top of the rewritten commit.
"""#'
@usage 'flag "-r --revision" help="The revision to delete the files in" default=@ {
            arg <REVSET>
        }'
@usage 'flag --restore-descendants help="Preserve the content (not the diff) when rebasing descendants"'
@usage 'arg <FILESETS>… help="Files or directories to delete (filesets are accepted)" var=#true var_min=1'
@usage 'complete filesets type=path'
export def "jj file delete" [
    ...filesets: path@"nusage complete",          # Files or directories to delete (filesets are accepted)
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --revision (-r): string,                      # The revision to delete the files in
    --restore-descendants,                        # Preserve the content (not the diff) when rebasing descendants
]: nothing -> string {
    ^jj file delete ...(nusage argv [...$filesets] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --revision: $revision
        --restore-descendants: $restore_descendants
    })
}

# Edit the contents of a file in a revision
#
# The file is opened with the contents from the given revision. After the editor exits, the file is saved back to the revision and descendants are rebased on top of the updated commit.
#
# If the file does not yet exist in the revision, a new file will be created.
#
# If the file is conflicted, the conflict markers are materialized in the editor. Editing the conflict markers can resolve the conflict.
@usage 'long_help #"""
Edit the contents of a file in a revision

The file is opened with the contents from the given revision. After the editor exits, the file is saved back to the revision and descendants are rebased on top of the updated commit.

If the file does not yet exist in the revision, a new file will be created.

If the file is conflicted, the conflict markers are materialized in the editor. Editing the conflict markers can resolve the conflict.
"""#'
@usage 'flag "-r --revision" help="The revision to edit the file in" default=@ {
            arg <REVSET>
        }'
@usage 'flag --restore-descendants help="Preserve the content (not the diff) when rebasing descendants"'
@usage 'arg <FILE> help="The file to edit"'
@usage 'complete file type=path'
export def "jj file edit" [
    file: path@"nusage complete",                 # The file to edit
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --revision (-r): string,                      # The revision to edit the file in
    --restore-descendants,                        # Preserve the content (not the diff) when rebasing descendants
]: nothing -> string {
    ^jj file edit ...(nusage argv [$file] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --revision: $revision
        --restore-descendants: $restore_descendants
    })
}

# List files in a revision
@usage 'flag "-r --revision" help="The revision to list files in" default=@ {
            arg <REVSET>
        }'
@usage 'flag "-T --template" help="Render each file entry using the given template" {
            long_help #"""
Render each file entry using the given template

All 0-argument methods of the [`TreeEntry` type][TreeEntry] are available as keywords in the template expression. See [`jj help -k templates`][templates] for more information.

The default template can be set by the `templates.file_list` setting.

[TreeEntry]: https://docs.jj-vcs.dev/latest/templates/#treeentry-type

[templates]: https://docs.jj-vcs.dev/latest/templates/
"""#
            arg <TEMPLATE>
        }'
@usage 'arg "[FILESETS]…" help="Only list files matching these prefixes (instead of all files)" required=#false var=#true var_min=1'
@usage 'complete filesets type=path'
export def "jj file list" [
    ...filesets: path@"nusage complete",          # Only list files matching these prefixes (instead of all files)
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --revision (-r): string,                      # The revision to list files in
    --template (-T): string,                      # Render each file entry using the given template
]: nothing -> string {
    ^jj file list ...(nusage argv [...$filesets] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --revision: $revision
        --template: $template
    })
}

# Search for content in files
#
# Prints each line that matches the specified pattern, prefixed by the file path. Use `--name-only` to print only the file paths.
#
# This is an early version of the command. It does not search files concurrently.
@usage 'long_help #"""
Search for content in files

Prints each line that matches the specified pattern, prefixed by the file path. Use `--name-only` to print only the file paths.

This is an early version of the command. It does not search files concurrently.
"""#'
@usage 'flag "-r --revision" help="The revision to search files in" default=@ {
            arg <REVSET>
        }'
@usage r#'flag "-p --pattern" help="The pattern to search for in a single line" required=#true {
            long_help #"""
The pattern to search for in a single line

It is a [string pattern syntax] like `kind:pattern`.  The kind defaults to regex when omitted.

If it is a glob pattern, the whole line must match the pattern, so you may want to pass something like `--pattern 'glob:*foo*'`.

[string pattern syntax]: https://docs.jj-vcs.dev/latest/revsets/#string-patterns
"""#
            arg <PATTERN>
        }'#
@usage 'flag --name-only help="Print only the paths of files that contain a match, not the matched lines" conflicts=--line-number'
@usage 'flag "-n --line-number" help="Prefix each matched line with its 1-based line number within the file"'
@usage 'arg "[FILESETS]…" help="Only search files matching these prefixes (instead of all files)" required=#false var=#true var_min=1'
@usage 'complete filesets type=path'
export def "jj file search" [
    ...filesets: path@"nusage complete",          # Only search files matching these prefixes (instead of all files)
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --revision (-r): string,                      # The revision to search files in
    --pattern (-p): string,                       # The pattern to search for in a single line
    --name-only,                                  # Print only the paths of files that contain a match, not the matched lines
    --line-number (-n),                           # Prefix each matched line with its 1-based line number within the file
]: nothing -> string {
    ^jj file search ...(nusage argv [...$filesets] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --revision: $revision
        --pattern: $pattern
        --name-only: $name_only
        --line-number: $line_number
    })
}

# Print contents of files in a revision
#
# If the given path is a directory, files in the directory will be visited recursively.
@usage 'long_help #"""
Print contents of files in a revision

If the given path is a directory, files in the directory will be visited recursively.
"""#'
@usage 'flag "-r --revision" help="The revision to get the file contents from" default=@ {
            arg <REVSET>
        }'
@usage 'flag "-T --template" help="Render each file metadata using the given template" {
            long_help #"""
Render each file metadata using the given template

All 0-argument methods of the [`TreeEntry` type][TreeEntry] are available as keywords in the template expression. See [`jj help -k templates`][templates] for more information.

If not specified, this defaults to the `templates.file_show` setting.

[TreeEntry]: https://docs.jj-vcs.dev/latest/templates/#treeentry-type

[templates]: https://docs.jj-vcs.dev/latest/templates/
"""#
            arg <TEMPLATE>
        }'
@usage 'arg <FILESETS>… help="Paths to print" var=#true var_min=1'
@usage 'complete filesets type=path'
export def "jj file show" [
    ...filesets: path@"nusage complete",          # Paths to print
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --revision (-r): string,                      # The revision to get the file contents from
    --template (-T): string,                      # Render each file metadata using the given template
]: nothing -> string {
    ^jj file show ...(nusage argv [...$filesets] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --revision: $revision
        --template: $template
    })
}

# Start tracking specified paths in the working copy
#
# Without arguments, all paths that are not ignored will be tracked.
#
# By default, new files in the working copy are automatically tracked, so this command has no effect. You can configure which paths to automatically track by setting `snapshot.auto-track` (e.g. to `"none()"` or `"glob:**/*.rs"`). Files that don't match the pattern can be manually tracked using this command. The default pattern is `all()`.
@usage r#'long_help #"""
Start tracking specified paths in the working copy

Without arguments, all paths that are not ignored will be tracked.

By default, new files in the working copy are automatically tracked, so this command has no effect. You can configure which paths to automatically track by setting `snapshot.auto-track` (e.g. to `"none()"` or `"glob:**/*.rs"`). Files that don't match the pattern can be manually tracked using this command. The default pattern is `all()`.
"""#'#
@usage r#'flag --include-ignored help="Track paths even if they're ignored or too large" {
            long_help #"""
Track paths even if they're ignored or too large

By default, `jj file track` will not track files that are ignored by .gitignore or exceed the maximum file size. This flag overrides those restrictions, explicitly tracking the specified paths.
"""#
        }'#
@usage 'arg <FILESETS>… help="Paths to track" var=#true var_min=1'
@usage 'complete filesets type=path'
export def "jj file track" [
    ...filesets: path@"nusage complete",          # Paths to track
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --include-ignored,                            # Track paths even if they're ignored or too large
]: nothing -> string {
    ^jj file track ...(nusage argv [...$filesets] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --include-ignored: $include_ignored
    })
}

# Stop tracking specified paths in the working copy
@usage 'arg <FILESETS>… help="Paths to untrack. They must already be ignored" help_long=#"""
Paths to untrack. They must already be ignored.

The paths could be ignored via a .gitignore or .git/info/exclude (in colocated workspaces).
"""# var=#true var_min=1'
@usage 'complete filesets type=path'
export def "jj file untrack" [
    ...filesets: path@"nusage complete",          # Paths to untrack. They must already be ignored
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj file untrack ...(nusage argv [...$filesets] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Update files with formatting fixes or other changes
#
# The primary use case for this command is to apply the results of automatic
# code formatting tools to revisions that may not be properly formatted yet.
# It can also be used to modify files with other tools like `sed` or `sort`.
#
# The modification made by `jj fix` can be reviewed by `jj op show -p`.
#
# ### How it works
#
# The changed files in the given revisions will be updated with any fixes
# determined by passing their file content through any external tools the user
# has configured for those files. Descendants will also be updated by passing
# their versions of the same files through the same tools, which will ensure
# that the fixes are not lost. This will never result in new conflicts. Files
# with existing conflicts will be updated on all sides of the conflict, which
# can potentially increase or decrease the number of conflict markers.
#
# ### Deduplication
#
# When fixing multiple commits, if the same file content appears at the same
# path in different commits, the tool is run only once and the result is
# reused. This means that tools used with `jj fix` must produce deterministic
# output.
#
# ### Configuration
#
# See `jj help -k config` chapter `Code formatting and other file content
# transformations` to understand how to configure your tools.
#
# ### Execution example
#
# Let's consider the following configuration. We have two code formatters
# (`clang-format` and `black`), which apply to three different file extensions
# (`.cc`, `.h`, and `.py`):
#
# ```toml
# [fix.tools.clang-format]
# command = ["/usr/bin/clang-format", "--assume-filename=$path"]
# patterns = ["glob:'**/*.cc'",
#             "glob:'**/*.h'"]
#
# [fix.tools.black]
# command = ["/usr/bin/black", "-", "--stdin-filename=$path"]
# patterns = ["glob:'**/*.py'"]
# ```
#
# Now, let's see what would happen to the following history, when executing
# `jj fix`.
#
# ```text
# C (mutable)
# |  Modifies file: foo.py
# |
# B @ (working copy - mutable)
# |  Modifies file: README.md
# |
# A (mutable)
# |  Modifies files: src/bar.cc and src/bar.h
# |
# X (immutable)
# ```
#
# By default, `jj fix` will modify revisions that match the revset
# `reachable(@, mutable())` (see `jj help -k revsets`), which corresponds to
# the revisions `A`, `B` and `C` here.
#
# The following operations will then happen:
#
# - For revision `A`, the contents from this revision for files `src/bar.cc`
#   and `src/bar.h` will be provided to `clang-format`, and the resulting
#   output will be used to recreate revision `A`, which we will call `A'`. All
#   other files are untouched.
# - For revision `B`, the same thing happens for files `src/bar.cc` and
#   `src/bar.h`. Their contents from revision `B` will go through
#   `clang-format`. The file `README.md`, same as all other files, is
#   untouched as no pattern matches it. We obtain revision `B'`.
# - For revision `C`, the files `src/bar.cc` and `src/bar.h` go through
#   `clang-format` and the file `foo.py` is fixed using `black`. All other
#   files are untouched. We obtain revision `C'`.
#
# ```text
# C (mutable)                    /-> C'
# |  src/bar.cc -> clang-format -|   |
# |  src/bar.h --> clang-format -|   |
# |  foo.py -----> black --------|   |
# |  * --------------------------/   |
# |                                  |
# B @ (working copy - mutable)   /-> B' @
# |  src/bar.cc -> clang-format -|   |
# |  src/bar.h --> clang-format -|   |
# |  * --------------------------|   |
# |                                  |
# A (mutable)                    /-> A'
# |  src/bar.cc -> clang-format -|   |
# |  src/bar.h --> clang-format -|   |
# |  * --------------------------/   |
# |                                  |
# X (immutable)                      X
# ```
#
# The revisions are now all correctly formatted according to the
# configuration.
@usage r#'long_help #"""
Update files with formatting fixes or other changes

The primary use case for this command is to apply the results of automatic
code formatting tools to revisions that may not be properly formatted yet.
It can also be used to modify files with other tools like `sed` or `sort`.

The modification made by `jj fix` can be reviewed by `jj op show -p`.

### How it works

The changed files in the given revisions will be updated with any fixes
determined by passing their file content through any external tools the user
has configured for those files. Descendants will also be updated by passing
their versions of the same files through the same tools, which will ensure
that the fixes are not lost. This will never result in new conflicts. Files
with existing conflicts will be updated on all sides of the conflict, which
can potentially increase or decrease the number of conflict markers.

### Deduplication

When fixing multiple commits, if the same file content appears at the same
path in different commits, the tool is run only once and the result is
reused. This means that tools used with `jj fix` must produce deterministic
output.

### Configuration

See `jj help -k config` chapter `Code formatting and other file content
transformations` to understand how to configure your tools.

### Execution example

Let's consider the following configuration. We have two code formatters
(`clang-format` and `black`), which apply to three different file extensions
(`.cc`, `.h`, and `.py`):

```toml
[fix.tools.clang-format]
command = ["/usr/bin/clang-format", "--assume-filename=$path"]
patterns = ["glob:'**/*.cc'",
            "glob:'**/*.h'"]

[fix.tools.black]
command = ["/usr/bin/black", "-", "--stdin-filename=$path"]
patterns = ["glob:'**/*.py'"]
```

Now, let's see what would happen to the following history, when executing
`jj fix`.

```text
C (mutable)
|  Modifies file: foo.py
|
B @ (working copy - mutable)
|  Modifies file: README.md
|
A (mutable)
|  Modifies files: src/bar.cc and src/bar.h
|
X (immutable)
```

By default, `jj fix` will modify revisions that match the revset
`reachable(@, mutable())` (see `jj help -k revsets`), which corresponds to
the revisions `A`, `B` and `C` here.

The following operations will then happen:

- For revision `A`, the contents from this revision for files `src/bar.cc`
  and `src/bar.h` will be provided to `clang-format`, and the resulting
  output will be used to recreate revision `A`, which we will call `A'`. All
  other files are untouched.
- For revision `B`, the same thing happens for files `src/bar.cc` and
  `src/bar.h`. Their contents from revision `B` will go through
  `clang-format`. The file `README.md`, same as all other files, is
  untouched as no pattern matches it. We obtain revision `B'`.
- For revision `C`, the files `src/bar.cc` and `src/bar.h` go through
  `clang-format` and the file `foo.py` is fixed using `black`. All other
  files are untouched. We obtain revision `C'`.

```text
C (mutable)                    /-> C'
|  src/bar.cc -> clang-format -|   |
|  src/bar.h --> clang-format -|   |
|  foo.py -----> black --------|   |
|  * --------------------------/   |
|                                  |
B @ (working copy - mutable)   /-> B' @
|  src/bar.cc -> clang-format -|   |
|  src/bar.h --> clang-format -|   |
|  * --------------------------|   |
|                                  |
A (mutable)                    /-> A'
|  src/bar.cc -> clang-format -|   |
|  src/bar.h --> clang-format -|   |
|  * --------------------------/   |
|                                  |
X (immutable)                      X
```

The revisions are now all correctly formatted according to the
configuration.
"""#'#
@usage 'flag "-s --source" help="Fix files in the specified revision(s) and their descendants. If no revisions are specified, this defaults to the `revsets.fix` setting, or `reachable(@, mutable())` if it is not set" var=#true {
        arg <REVSETS>… var=#true
    }'
@usage 'flag --include-unchanged-files help="Fix unchanged files in addition to changed ones. If no paths are specified, all files in the repo will be fixed"'
@usage r#'flag "-a --all-lines" help="Format all lines instead of only modified lines" {
        long_help #"""
Format all lines instead of only modified lines.

If the formatter doesn't support formatting only modified lines, then this option has no effect since the formatter always formats all lines.
"""#
    }'#
@usage 'arg "[FILESETS]…" help="Fix only these paths" required=#false var=#true var_min=1'
@usage 'complete filesets type=path'
export def "jj fix" [
    ...filesets: path@"nusage complete",          # Fix only these paths
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --source (-s): list<string>,                  # Fix files in the specified revision(s) and their descendants. If no revisions are specified, this defaults to the `revsets.fix` setting, or `reachable(@, mutable())` if it is not set
    --include-unchanged-files,                    # Fix unchanged files in addition to changed ones. If no paths are specified, all files in the repo will be fixed
    --all-lines (-a),                             # Format all lines instead of only modified lines
]: nothing -> string {
    ^jj fix ...(nusage argv [...$filesets] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --source: $source
        --include-unchanged-files: $include_unchanged_files
        --all-lines: $all_lines
    })
}

# Interact with Gerrit Code Review
export def "jj gerrit" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj gerrit ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Upload changes to Gerrit for code review, or update existing changes
#
# Uploading a set of revisions to Gerrit creates a single "change" for each
# revision included in the revset and all their mutable ancestors. These
# changes will then be available for review on your Gerrit instance.
#
# If a change already exists for a given revision (i.e. it contains the
# same `Change-Id`), this command will update the contents of the existing
# change to match.
#
# Note: Any commit in the given revset that does not have a `Change-Id`
# trailer will have one generated based on the Jujutsu change ID. This trailer
# is only added to the uploaded commit, which means the resulting commit ID
# uploaded to Gerrit may not match your local commit ID. As a result, you may
# encounter divergence when you fetch a merged change into your local repo. To
# address this, you can abandon your local change or rebase it on top of trunk
# with `jj rebase --skip-emptied ...`, which will resolve the divergence.
# Alternatively, you can add the following to your Jujutsu config to add
# `Change-Id` trailers to your local commits automatically before `jj gerrit
# upload` does:
# ```toml
# [templates]
# commit_trailers = '''
# if(
#   !trailers.contains_key("Change-Id"),
#   format_gerrit_change_id_trailer(self)
# )
# '''
# ```
#
# Also see the [Jujutsu docs on Gerrit].
#
# [Jujutsu docs on Gerrit]: https://docs.jj-vcs.dev/latest/gerrit
@usage r#'long_help #"""
Upload changes to Gerrit for code review, or update existing changes

Uploading a set of revisions to Gerrit creates a single "change" for each
revision included in the revset and all their mutable ancestors. These
changes will then be available for review on your Gerrit instance.

If a change already exists for a given revision (i.e. it contains the
same `Change-Id`), this command will update the contents of the existing
change to match.

Note: Any commit in the given revset that does not have a `Change-Id`
trailer will have one generated based on the Jujutsu change ID. This trailer
is only added to the uploaded commit, which means the resulting commit ID
uploaded to Gerrit may not match your local commit ID. As a result, you may
encounter divergence when you fetch a merged change into your local repo. To
address this, you can abandon your local change or rebase it on top of trunk
with `jj rebase --skip-emptied ...`, which will resolve the divergence.
Alternatively, you can add the following to your Jujutsu config to add
`Change-Id` trailers to your local commits automatically before `jj gerrit
upload` does:
```toml
[templates]
commit_trailers = '''
if(
  !trailers.contains_key("Change-Id"),
  format_gerrit_change_id_trailer(self)
)
'''
```

Also see the [Jujutsu docs on Gerrit].

[Jujutsu docs on Gerrit]: https://docs.jj-vcs.dev/latest/gerrit
"""#'#
@usage r#'flag "-r --revision" help="The revisions to upload to Gerrit" var=#true {
            long_help #"""
The revisions to upload to Gerrit

All mutable ancestors of specified revisions will also be pushed. This means that `jj gerrit upload -r foo` is equivalent to `jj gerrit upload -r 'mutable()::foo'`.

If this is not provided, `@` will be uploaded if it has a description, and `@-` will be uploaded otherwise.
"""#
            arg <REVSETS>… var=#true
        }'#
@usage 'flag "-b --remote-branch" help="The location where your changes are intended to land" {
            long_help #"""
The location where your changes are intended to land

This should be a branch on the remote. The default is the `gerrit.default-remote-branch` setting.
"""#
            arg <REMOTE_BRANCH>
        }'
@usage 'flag --remote help="The Gerrit remote to push to" {
            long_help #"""
The Gerrit remote to push to

This can point to any configured Git remote, or can be a full SSH URL. The default is the `gerrit.default-remote` setting.
"""#
            arg <REMOTE>
        }'
@usage 'flag "-n --dry-run" help="Only display what will change on the remote; do not push changes to Gerrit"'
@usage 'flag --reviewer help="Add these emails as a reviewer (can be repeated)" var=#true {
            arg <REVIEWER>… var=#true
        }'
@usage 'flag --cc help="CC these emails on the change (can be repeated)" var=#true {
            arg <CC>… var=#true
        }'
@usage 'flag "-l --label" help="Add the following labels configured by Gerrit (can be repeated)" var=#true {
            long_help #"""
Add the following labels configured by Gerrit (can be repeated)

Each label can have a suffix of the value to set, such as "+2". The
default is "+1" if no value is set.

Note that Gerrit silently ignores labels not present on your Gerrit
host.

Examples:
- `--label=Commit-Queue` will set the `Commit-Queue` label to +1.
- `--label=Commit-Queue+2` will set it to +2.
"""#
            arg <LABEL>… var=#true
        }'
@usage 'flag --topic help="Apply a topic to the change" {
            long_help #"""
Apply a topic to the change

Changes can be grouped by topic, and Gerrit can be configured to submit all changes in a topic together in a single click.

See https://gerrit-review.googlesource.com/Documentation/intro-user.html#topics.
"""#
            arg <TOPIC>
        }'
@usage 'flag --hashtag help="Apply a hashtag to the change (can be repeated)" var=#true {
            long_help #"""
Apply a hashtag to the change (can be repeated)

Hashtags are freeform strings associated with a change, like on social media platforms. Similar to topics, hashtags can be used to group related changes together, and to search using the `hashtag:` operator. Unlike topics, a change can have multiple hashtags, and they are only used for informational grouping. Changes with the same hashtags are not necessarily submitted together.

See https://gerrit-review.googlesource.com/Documentation/intro-user.html#hashtags.
"""#
            arg <HASHTAG>… var=#true
        }'
@usage 'flag "-m --message" help="The description for the patch set" {
            arg <MESSAGE>
        }'
@usage r#'flag --edit help="Push the change as a change edit" {
            long_help #"""
Push the change as a change edit

To push a change edit the underlying change needs to already exist on the Gerrit server. Change edits don't immediately create a new patch set, but need to be published from the web UI first. There can only be one edit for each change. Pushing a new change edit will replace the previous one.
"""#
        }'#
@usage 'flag --wip help="Mark the change as WIP (work in progress)" {
            long_help #"""
Mark the change as WIP (work in progress)

See https://gerrit-review.googlesource.com/Documentation/intro-user.html#wip.
"""#
        }'
@usage 'flag --ready help="Mark the change as ready (no longer work in progress)"'
@usage 'flag --private help="Mark the change as private" {
            long_help #"""
Mark the change as private

See https://gerrit-review.googlesource.com/Documentation/intro-user.html#private-changes.
"""#
        }'
@usage 'flag --remove-private help="Unmark the change as private"'
@usage 'flag --publish-comments help="Publish draft comments for the given change"'
@usage 'flag --no-publish-comments help="Do not publish draft comments for the given change" {
            long_help #"""
Do not publish draft comments for the given change

This is only useful if the user has configured Gerrit to publish comments by default.
"""#
        }'
@usage r#'flag --notify help="Who to email notifications to (defaults to all)" {
            arg <NOTIFY> {
                choices {
                    choice none help="No emails"
                    choice owner help="Only the change owner is notified"
                    choice owner-reviewers help="Only the change owner and reviewers will be notified"
                    choice all help="All relevant users, including owner, reviewers, cc'd, users that have starred the change, and users who have configured a watch on files in the change"
                }
            }
        }'#
@usage 'flag --submit help="Directly submit the changes, bypassing code review"'
@usage 'flag --skip-validation help="When --submit is provided, skip performing validations"'
@usage 'flag --merged help="Create a new change, even if the change has already been merged"'
@usage 'flag --ignore-attention-set help="Do not modify the attention set upon uploading"'
@usage 'flag --deadline help="The deadline after which the push should be aborted" {
            arg <DEADLINE>
        }'
@usage 'flag --custom help="Send the following custom keyed values to Gerrit (can be repeated)" var=#true {
            long_help #"""
Send the following custom keyed values to Gerrit (can be repeated)

See https://gerrit-review.googlesource.com/Documentation/user-upload.html#custom_keyed_values
"""#
            arg <CUSTOM>… var=#true
        }'
@usage 'flag "-o --option" help="Send a `git push -o` option (can be repeated)" var=#true {
            arg <OPTION>… var=#true
        }'
@usage 'flag --trace help="For debugging Gerrit" {
            long_help #"""
For debugging Gerrit

See https://gerrit-review.googlesource.com/Documentation/user-upload.html#trace
"""#
            arg <TRACE>
        }'
export def "jj gerrit upload" [
    --repository (-R): path@"nusage complete",          # Path to repository to operate on
    --ignore-working-copy,                              # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                           # Run the command as usual but don't integrate any operations
    --ignore-immutable,                                 # Allow rewriting immutable commits
    --at-operation: string,                             # Operation to load the repo at
    --debug,                                            # Enable debug logging
    --color: string@[always never debug auto],          # When to colorize output
    --quiet,                                            # Silence non-primary command output
    --no-pager,                                         # Disable the pager
    --config: list<string>,                             # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",        # Additional configuration files (can be repeated)
    --revision (-r): list<string>,                      # The revisions to upload to Gerrit
    --remote-branch (-b): string,                       # The location where your changes are intended to land
    --remote: string,                                   # The Gerrit remote to push to
    --dry-run (-n),                                     # Only display what will change on the remote; do not push changes to Gerrit
    --reviewer: list<string>,                           # Add these emails as a reviewer (can be repeated)
    --cc: list<string>,                                 # CC these emails on the change (can be repeated)
    --label (-l): list<string>,                         # Add the following labels configured by Gerrit (can be repeated)
    --topic: string,                                    # Apply a topic to the change
    --hashtag: list<string>,                            # Apply a hashtag to the change (can be repeated)
    --message (-m): string,                             # The description for the patch set
    --edit,                                             # Push the change as a change edit
    --wip,                                              # Mark the change as WIP (work in progress)
    --ready,                                            # Mark the change as ready (no longer work in progress)
    --private,                                          # Mark the change as private
    --remove-private,                                   # Unmark the change as private
    --publish-comments,                                 # Publish draft comments for the given change
    --no-publish-comments,                              # Do not publish draft comments for the given change
    --notify: string@[none owner owner-reviewers all],  # Who to email notifications to (defaults to all)
    --submit,                                           # Directly submit the changes, bypassing code review
    --skip-validation,                                  # When --submit is provided, skip performing validations
    --merged,                                           # Create a new change, even if the change has already been merged
    --ignore-attention-set,                             # Do not modify the attention set upon uploading
    --deadline: string,                                 # The deadline after which the push should be aborted
    --custom: list<string>,                             # Send the following custom keyed values to Gerrit (can be repeated)
    --option (-o): list<string>,                        # Send a `git push -o` option (can be repeated)
    --trace: string,                                    # For debugging Gerrit
]: nothing -> string {
    ^jj gerrit upload ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --revision: $revision
        --remote-branch: $remote_branch
        --remote: $remote
        --dry-run: $dry_run
        --reviewer: $reviewer
        --cc: $cc
        --label: $label
        --topic: $topic
        --hashtag: $hashtag
        --message: $message
        --edit: $edit
        --wip: $wip
        --ready: $ready
        --private: $private
        --remove-private: $remove_private
        --publish-comments: $publish_comments
        --no-publish-comments: $no_publish_comments
        --notify: $notify
        --submit: $submit
        --skip-validation: $skip_validation
        --merged: $merged
        --ignore-attention-set: $ignore_attention_set
        --deadline: $deadline
        --custom: $custom
        --option: $option
        --trace: $trace
    })
}

# Commands for working with Git remotes and the underlying Git repo
#
# See this [comparison], including a [table of commands].
#
# [comparison]: https://docs.jj-vcs.dev/latest/git-comparison/.
#
# [table of commands]: https://docs.jj-vcs.dev/latest/git-command-table
@usage 'long_help #"""
Commands for working with Git remotes and the underlying Git repo

See this [comparison], including a [table of commands].

[comparison]: https://docs.jj-vcs.dev/latest/git-comparison/.

[table of commands]: https://docs.jj-vcs.dev/latest/git-command-table
"""#'
export def "jj git" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj git ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Create a new repo backed by a clone of a Git repo
@usage 'flag --remote help="Name of the newly created remote" default=origin {
            arg <REMOTE_NAME>
        }'
@usage 'flag --colocate help="Colocate the Jujutsu repo with the git repo" {
            long_help #"""
Colocate the Jujutsu repo with the git repo

Specifies that the `jj` repo should also be a valid `git` repo, allowing the use of both `jj` and `git` commands in the same directory.

The repository will contain a `.git` dir in the top-level. Regular Git tools will be able to operate on the repo.

**This is the default**, and this option has no effect, unless the [git.colocate config] is set to `false`.

[git.colocate config]: https://docs.jj-vcs.dev/latest/config/#default-colocation
"""#
        }'
@usage 'flag --no-colocate help="Disable colocation of the Jujutsu repo with the git repo" conflicts=--colocate {
            long_help #"""
Disable colocation of the Jujutsu repo with the git repo

Prevent Git tools that are unaware of `jj` and regular Git commands from operating on the repo. The Git repository that stores most of the repo data will be hidden inside a sub-directory of the `.jj` directory.

See [colocation docs] for some minor advantages of non-colocated workspaces.

[colocation docs]: https://docs.jj-vcs.dev/latest/git-compatibility/#colocated-jujutsugit-workspaces
"""#
        }'
@usage 'flag --depth help="Create a shallow clone of the given depth" {
            arg <DEPTH>
        }'
@usage r#'flag "-b --branch" help="Name of the branch to fetch and use as the parent of the working-copy change (can be repeated)" var=#true {
            alias "--bookmark" hide=#true
            long_help #"""
Name of the branch to fetch and use as the parent of the working-copy change (can be repeated)

If not present, all branches are fetched and the repository's default branch is used as parent of the working-copy change.

By default, the specified pattern matches branch names with glob syntax, but only `*` is expanded. Other wildcard characters such as `?` are *not* supported. Patterns can be repeated or combined with [logical operators] to specify multiple branches, but only union and negative intersection are supported. If there are multiple matching branches, the first exact branch name is used as the working-copy parent.

Examples: `push-*`, `(push-* | foo/*) ~ foo/unwanted`

[logical operators]: https://docs.jj-vcs.dev/latest/revsets/#string-patterns
"""#
            arg <BRANCH>… var=#true
        }'#
@usage 'flag "-t --tag" help="Fetch only some of the tags (can be repeated)" var=#true {
            long_help #"""
Fetch only some of the tags (can be repeated)

By default, the specified pattern matches tag names with glob syntax, but only `*` is expanded. Other wildcard characters such as `?` are *not* supported. Patterns can be repeated or combined with [logical operators] to specify multiple tags, but only union and negative intersection are supported.

[logical operators]: https://docs.jj-vcs.dev/latest/revsets/#string-patterns
"""#
            arg <TAG>… var=#true
        }'
@usage r#'flag --object-hash help="Object hash algorithm for the local Git repository" {
            long_help #"""
Object hash algorithm for the local Git repository.

*Must* match the remote's hash algorithm, otherwise the operation will fail. Most existing repositories today still use the classic SHA-1 format, which is also the default if not configured otherwise by the [git.object-hash config].

See also Git's [hash-function-transition] document for an in-depth explanation of the migration towards stronger hash functions.

[git.object-hash config]: https://docs.jj-vcs.dev/latest/config/#default-object-hash-format [hash-function-transition]: https://git-scm.com/docs/hash-function-transition
"""#
            arg <OBJECT_HASH> {
                choices sha1 sha256
            }
        }'#
@usage 'arg <SOURCE> help="URL or path of the Git repo to clone" help_long=#"""
URL or path of the Git repo to clone

Local path will be resolved to absolute form.
"""#'
@usage r#'arg "[DESTINATION]" help="Specifies the target directory for the Jujutsu repository clone. If not provided, defaults to a directory named after the last component of the source URL. The full directory path will be created if it doesn't exist" required=#false'#
@usage 'complete source type=url'
@usage 'complete destination type=dir'
export def "jj git clone" [
    source: string@"nusage complete",             # URL or path of the Git repo to clone
    destination?: path@"nusage complete",         # Specifies the target directory for the Jujutsu repository clone. If not provided, defaults to a directory named after the last component of the source URL. The full directory path will be created if it doesn't exist
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --remote: string,                             # Name of the newly created remote
    --colocate,                                   # Colocate the Jujutsu repo with the git repo
    --no-colocate,                                # Disable colocation of the Jujutsu repo with the git repo
    --depth: string,                              # Create a shallow clone of the given depth
    --branch (-b): list<string>,                  # Name of the branch to fetch and use as the parent of the working-copy change (can be repeated)
    --tag (-t): list<string>,                     # Fetch only some of the tags (can be repeated)
    --object-hash: string@["sha1" "sha256"],      # Object hash algorithm for the local Git repository
]: nothing -> string {
    ^jj git clone ...(nusage argv [$source $destination] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --remote: $remote
        --colocate: $colocate
        --no-colocate: $no_colocate
        --depth: $depth
        --branch: $branch
        --tag: $tag
        --object-hash: $object_hash
    })
}

# Manage Jujutsu repository colocation with Git
export def "jj git colocation" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj git colocation ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Convert into a non-colocated Jujutsu/Git repository
#
# This moves the Git repository that is at the root of the Jujutsu workspace into the .jj directory. Once this is done you will no longer be able to use Git commands directly in the Jujutsu workspace.
@usage 'long_help #"""
Convert into a non-colocated Jujutsu/Git repository

This moves the Git repository that is at the root of the Jujutsu workspace into the .jj directory. Once this is done you will no longer be able to use Git commands directly in the Jujutsu workspace.
"""#'
export def "jj git colocation disable" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj git colocation disable ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Convert into a colocated Jujutsu/Git repository
#
# This moves the underlying Git repository that is found inside the .jj directory to the root of the Jujutsu workspace. This allows you to use Git commands directly in the Jujutsu workspace.
@usage 'long_help #"""
Convert into a colocated Jujutsu/Git repository

This moves the underlying Git repository that is found inside the .jj directory to the root of the Jujutsu workspace. This allows you to use Git commands directly in the Jujutsu workspace.
"""#'
export def "jj git colocation enable" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj git colocation enable ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Show the current colocation status
export def "jj git colocation status" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj git colocation status ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Update the underlying Git repo with changes made in the repo
#
# By default, this command does nothing in colocated workspaces because the export happens automatically. Use `--ignore-working-copy` to forcibly export changes.
@usage 'long_help #"""
Update the underlying Git repo with changes made in the repo

By default, this command does nothing in colocated workspaces because the export happens automatically. Use `--ignore-working-copy` to forcibly export changes.
"""#'
export def "jj git export" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj git export ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Fetch from a Git remote
#
# If no remotes are specified, fetches the remotes specified by the `git.fetch` setting. If that is not configured and there are multiple remotes, the remote named "origin" will be used.
#
# If no branches nor tags are specified, fetches bookmarks and tags specified by the `remotes.<name>.fetch-bookmarks`/`fetch-tags` settings. If `remotes.<name>.fetch-bookmarks` is not configured, the default fetch refspecs for the selected remotes are read from the Git configuration.
#
# Commits that are no longer reachable from any branch on the remote will be considered abandoned by the remote, and will be abandoned in the local repo to match the remote. Set `git.abandon-unreachable-commits` to `false` to disable this behavior.
#
# If a working-copy commit gets abandoned, it will be given a new, empty commit. This is true in general; it is not specific to this command.
@usage 'long_help #"""
Fetch from a Git remote

If no remotes are specified, fetches the remotes specified by the `git.fetch` setting. If that is not configured and there are multiple remotes, the remote named "origin" will be used.

If no branches nor tags are specified, fetches bookmarks and tags specified by the `remotes.<name>.fetch-bookmarks`/`fetch-tags` settings. If `remotes.<name>.fetch-bookmarks` is not configured, the default fetch refspecs for the selected remotes are read from the Git configuration.

Commits that are no longer reachable from any branch on the remote will be considered abandoned by the remote, and will be abandoned in the local repo to match the remote. Set `git.abandon-unreachable-commits` to `false` to disable this behavior.

If a working-copy commit gets abandoned, it will be given a new, empty commit. This is true in general; it is not specific to this command.
"""#'
@usage 'flag "-b --branch" help="Name of the branch to fetch (can be repeated)" var=#true {
            alias "--bookmark" hide=#true
            long_help #"""
Name of the branch to fetch (can be repeated)

By default, the specified pattern matches branch names with glob syntax, but only `*` is expanded. Other wildcard characters such as `?` are *not* supported. Patterns can be repeated or combined with [logical operators] to specify multiple branches, but only union and negative intersection are supported.

Examples: `push-*`, `(push-* | foo/*) ~ foo/unwanted`

[logical operators]: https://docs.jj-vcs.dev/latest/revsets/#string-patterns
"""#
            arg <BRANCH>… var=#true
        }'
@usage 'flag "-t --tag" help="Fetch only some of the tags (can be repeated)" var=#true {
            long_help #"""
Fetch only some of the tags (can be repeated)

By default, the specified pattern matches tag names with glob syntax, but only `*` is expanded. Other wildcard characters such as `?` are *not* supported. Patterns can be repeated or combined with [logical operators] to specify multiple tags, but only union and negative intersection are supported.

[logical operators]: https://docs.jj-vcs.dev/latest/revsets/#string-patterns
"""#
            arg <TAG>… var=#true
        }'
@usage 'flag --tracked help="Fetch only tracked bookmarks and tags" {
            long_help #"""
Fetch only tracked bookmarks and tags

This fetches only bookmarks and tags that are already tracked from the specified remote(s).
"""#
        }'
@usage r#'flag --remote help="The remote to fetch from (only named remotes are supported, can be repeated)" var=#true {
            long_help #"""
The remote to fetch from (only named remotes are supported, can be repeated)

By default, the specified pattern matches remote names with glob syntax, e.g. `--remote '*'`. You can also use other [string pattern syntax].

[string pattern syntax]: https://docs.jj-vcs.dev/latest/revsets/#string-patterns
"""#
            arg <REMOTE>… var=#true
        }'#
@usage 'flag --all-remotes help="Fetch from all remotes" conflicts=--remote'
export def "jj git fetch" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --branch (-b): list<string>,                  # Name of the branch to fetch (can be repeated)
    --tag (-t): list<string>,                     # Fetch only some of the tags (can be repeated)
    --tracked,                                    # Fetch only tracked bookmarks and tags
    --remote: list<string>,                       # The remote to fetch from (only named remotes are supported, can be repeated)
    --all-remotes,                                # Fetch from all remotes
]: nothing -> string {
    ^jj git fetch ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --branch: $branch
        --tag: $tag
        --tracked: $tracked
        --remote: $remote
        --all-remotes: $all_remotes
    })
}

# Update repo with changes made in the underlying Git repo
#
# Commits that are no longer reachable from any branch in the Git repo will be considered abandoned in the Git repo, and will be abandoned in the jj repo to match the Git repo. Set `git.abandon-unreachable-commits` to `false` to disable this behavior.
#
# If a working-copy commit gets abandoned, it will be given a new, empty commit. This is true in general; it is not specific to this command.
#
# By default, this command does nothing in colocated workspaces because the import happens automatically. Use `--ignore-working-copy` to forcibly import changes.
@usage 'long_help #"""
Update repo with changes made in the underlying Git repo

Commits that are no longer reachable from any branch in the Git repo will be considered abandoned in the Git repo, and will be abandoned in the jj repo to match the Git repo. Set `git.abandon-unreachable-commits` to `false` to disable this behavior.

If a working-copy commit gets abandoned, it will be given a new, empty commit. This is true in general; it is not specific to this command.

By default, this command does nothing in colocated workspaces because the import happens automatically. Use `--ignore-working-copy` to forcibly import changes.
"""#'
export def "jj git import" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj git import ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Create a new Git backed repo
#
# To use an existing Git repository as the backing store, run `jj git init` from that repository's root directory. This is the usual way to start using Jujutsu in an existing Git checkout. See [colocation docs].
#
# If the setting `git.colocate` has the value `false`, then new repositories will not be colocated. Pass `--colocate` to override this.
#
# [colocation docs]: https://docs.jj-vcs.dev/latest/git-compatibility/#creating-a-repo-backed-by-an-existing-git-repo
@usage r#'long_help #"""
Create a new Git backed repo.

To use an existing Git repository as the backing store, run `jj git init` from that repository's root directory. This is the usual way to start using Jujutsu in an existing Git checkout. See [colocation docs].

If the setting `git.colocate` has the value `false`, then new repositories will not be colocated. Pass `--colocate` to override this.

[colocation docs]: https://docs.jj-vcs.dev/latest/git-compatibility/#creating-a-repo-backed-by-an-existing-git-repo
"""#'#
@usage 'flag --colocate help="Colocate the workspace of the Jujutsu repo with the Git repo" conflicts=--git-repo {
            long_help #"""
Colocate the workspace of the Jujutsu repo with the Git repo

Specifies that the workspace of the `jj` repo should also be a valid `git` repo, allowing the use of both `jj` and `git` commands in the same directory. The workspace will contain a `.git` dir in the top-level, so regular Git tools will be able to operate on the repo.

**This is the default** (and this option has no effect) unless the [`git.colocate` config] is set to `false`.

The `--colocate` option is equivalent to `--git-repo=DESTINATION`. These options are mutually exclusive.

[`git.colocate` config]: https://docs.jj-vcs.dev/latest/config/#default-colocation
"""#
        }'
@usage 'flag --no-colocate help="Disable colocation for the workspace of the Jujutsu repo with the Git repo" conflicts=--colocate {
            long_help #"""
Disable colocation for the workspace of the Jujutsu repo with the Git repo

Prevent Git tools that are unaware of `jj` and regular Git commands from operating on the repo. The Git repository that stores most of the repo data will be hidden inside a sub-directory of the `.jj` directory.

See [colocation docs] for some minor advantages of non-colocated workspaces.

[colocation docs]: https://docs.jj-vcs.dev/latest/git-compatibility/#colocated-jujutsugit-workspaces
"""#
        }'
@usage r#'flag --object-hash help="Object hash algorithm for the newly created Git repository" conflicts=--git-repo {
            long_help #"""
Object hash algorithm for the newly created Git repository.

Corresponds to `git init`'s `--object-format` option. If not given, the [git.object-hash config] determines the default value.

Note that the object hash cannot currently be changed for an existing repo, and not all code forges support SHA-256 repositories yet. See also Git's [hash-function-transition] document for an in-depth explanation of the migration towards stronger hash functions.

[git.object-hash config]: https://docs.jj-vcs.dev/latest/config/#default-object-hash-format [hash-function-transition]: https://git-scm.com/docs/hash-function-transition
"""#
            arg <OBJECT_HASH> {
                choices sha1 sha256
            }
        }'#
@usage 'flag --git-repo help="Specifies a path to an **existing** git repository to be used as the backing git repo for the newly created `jj` repo" {
            long_help #"""
Specifies a path to an **existing** git repository to be used as the backing git repo for the newly created `jj` repo.

If the specified `--git-repo` path is the same as `DESTINATION`, then a [colocated workspace] will be created, and both `jj` and `git` commands will work on the repo. The `git.colocate` setting is ignored in this case.

If the specified `--git-repo` path is outside of the given `DESTINATION`, then the Jujutsa workspace will store a reference to the external Git repository (not a colocated workspace). This option is mutually exclusive with `--collate`.

[colocated workspace]: https://docs.jj-vcs.dev/latest/git-compatibility/#colocated-jujutsugit-workspaces
"""#
            conflicts "--colocate" "--object-hash"
            arg <GIT_REPO>
        }'
@usage 'arg "[DESTINATION]" help="The destination directory where the `jj` repo will be created. If the directory does not exist, it will be created. If no directory is given, the current directory is used" required=#false default=.'
@usage 'complete destination type=dir'
@usage 'complete git_repo type=dir'
export def "jj git init" [
    destination?: path@"nusage complete",         # The destination directory where the `jj` repo will be created. If the directory does not exist, it will be created. If no directory is given, the current directory is used
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --colocate,                                   # Colocate the workspace of the Jujutsu repo with the Git repo
    --no-colocate,                                # Disable colocation for the workspace of the Jujutsu repo with the Git repo
    --object-hash: string@["sha1" "sha256"],      # Object hash algorithm for the newly created Git repository
    --git-repo: path@"nusage complete",           # Specifies a path to an **existing** git repository to be used as the backing git repo for the newly created `jj` repo
]: nothing -> string {
    ^jj git init ...(nusage argv [$destination] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --colocate: $colocate
        --no-colocate: $no_colocate
        --object-hash: $object_hash
        --git-repo: $git_repo
    })
}

# Push to a Git remote
#
# By default, pushes tracking bookmarks and tags pointing to `remote_bookmarks(remote=<remote>)..@`. The default can be configured via `revsets.git-push`. Use `--bookmark`/`--tag` to push specific bookmarks or tags. Use `--all` to push all bookmarks and tags. Use `--change` to generate bookmark names based on the change IDs of specific commits.
#
# When pushing a bookmark or tag, the command pushes all commits in the range from the remote's current position up to and including its target commit. Any descendant commits beyond the reference are not pushed.
#
# If the local reference has changed from the last fetch, push will update the remote reference to the new position after passing safety checks. This is similar to `git push --force-with-lease` - the remote is updated only if its current state matches what Jujutsu last fetched.
#
# Unlike in Git, the remote to push to is not derived from the tracked remote bookmarks. Use `--remote` to select the remote Git repository by name. There is no option to push to multiple remotes.
#
# Before the command actually moves, creates, or deletes a remote bookmark, it makes several [safety checks]. If there is a problem, you may need to run `jj git fetch --remote <remote name>` and/or resolve some [bookmark conflicts].
#
# [safety checks]: https://docs.jj-vcs.dev/latest/bookmarks/#pushing-bookmarks-safety-checks
#
# [bookmark conflicts]: https://docs.jj-vcs.dev/latest/bookmarks/#conflicts
@usage r#'long_help #"""
Push to a Git remote

By default, pushes tracking bookmarks and tags pointing to `remote_bookmarks(remote=<remote>)..@`. The default can be configured via `revsets.git-push`. Use `--bookmark`/`--tag` to push specific bookmarks or tags. Use `--all` to push all bookmarks and tags. Use `--change` to generate bookmark names based on the change IDs of specific commits.

When pushing a bookmark or tag, the command pushes all commits in the range from the remote's current position up to and including its target commit. Any descendant commits beyond the reference are not pushed.

If the local reference has changed from the last fetch, push will update the remote reference to the new position after passing safety checks. This is similar to `git push --force-with-lease` - the remote is updated only if its current state matches what Jujutsu last fetched.

Unlike in Git, the remote to push to is not derived from the tracked remote bookmarks. Use `--remote` to select the remote Git repository by name. There is no option to push to multiple remotes.

Before the command actually moves, creates, or deletes a remote bookmark, it makes several [safety checks]. If there is a problem, you may need to run `jj git fetch --remote <remote name>` and/or resolve some [bookmark conflicts].

[safety checks]: https://docs.jj-vcs.dev/latest/bookmarks/#pushing-bookmarks-safety-checks

[bookmark conflicts]: https://docs.jj-vcs.dev/latest/bookmarks/#conflicts
"""#'#
@usage r#'flag --remote help="The remote(s) to push to (can be repeated)" var=#true {
            long_help #"""
The remote(s) to push to (can be repeated)

This defaults to the `git.push` setting. If that is not configured, and if there are multiple remotes, the remote named "origin" will be used.

By default, the specified pattern matches remote names with glob syntax, e.g., `--remote '*'`. You can also use other [string pattern syntax].

[string pattern syntax]: https://docs.jj-vcs.dev/latest/revsets/#string-patterns
"""#
            arg <REMOTE>… var=#true
        }'#
@usage r#'flag "-b --bookmark" help="Push only this bookmark, or bookmarks matching a pattern (can be repeated)" var=#true {
            alias "--branch" hide=#true
            long_help #"""
Push only this bookmark, or bookmarks matching a pattern (can be repeated)

If a bookmark isn't tracking anything yet, the remote bookmark will be tracked automatically.

By default, the specified pattern matches bookmark names with glob syntax. You can also use other [string pattern syntax].

[string pattern syntax]: https://docs.jj-vcs.dev/latest/revsets/#string-patterns
"""#
            arg <BOOKMARK>… var=#true
        }'#
@usage r#'flag "-t --tag" help="Push only this tag, or tags matching a pattern (can be repeated)" var=#true {
            long_help #"""
Push only this tag, or tags matching a pattern (can be repeated)

If a tag isn't tracking anything yet, the remote tag will be tracked automatically.

By default, the specified pattern matches tag names with glob syntax. You can also use other [string pattern syntax].

[string pattern syntax]: https://docs.jj-vcs.dev/latest/revsets/#string-patterns
"""#
            arg <TAG>… var=#true
        }'#
@usage 'flag --all help="Push all bookmarks and tags (including new ones)"'
@usage 'flag --tracked help="Push all tracked bookmarks and tags" {
            long_help #"""
Push all tracked bookmarks and tags

This usually means that the bookmark or tag was already pushed to or fetched from the [relevant remote].

[relevant remote]: https://docs.jj-vcs.dev/latest/bookmarks#remotes-and-tracked-bookmarks
"""#
        }'
@usage 'flag --deleted help="Push all deleted bookmarks and tags" {
            long_help #"""
Push all deleted bookmarks and tags

Only tracked bookmarks and tags can be successfully deleted on the remote. A warning will be printed if any untracked bookmarks or tags on the remote correspond to missing local bookmarks or tags.
"""#
        }'
@usage 'flag --allow-empty-description help="Allow pushing commits with empty descriptions"'
@usage 'flag --allow-private help="Allow pushing commits that are private" {
            long_help #"""
Allow pushing commits that are private

The set of private commits can be configured by the `git.private-commits` setting. The default is `none()`, meaning all commits are eligible to be pushed.
"""#
        }'
@usage 'flag --allow-conflicts help="Allow pushing commits that contain conflicts"'
@usage 'flag "-r --revision" help="Push bookmarks and tags pointing to these commits (can be repeated)" var=#true {
            alias "--revisions" hide=#true
            arg <REVSETS>… var=#true
        }'
@usage 'flag "-c --change" help="Push this commit by creating a bookmark (can be repeated)" var=#true {
            long_help #"""
Push this commit by creating a bookmark (can be repeated)

The created bookmark will be tracked automatically. Use the `templates.git_push_bookmark` setting to customize the generated bookmark name. The default is `"push-" ++ change_id.short()`.
"""#
            arg <REVSETS>… var=#true
        }'
@usage r#'flag --named help="Specify a new bookmark name and a revision to push under that name, e.g. '--named myfeature=@'" var=#true {
            long_help #"""
Specify a new bookmark name and a revision to push under that name, e.g. '--named myfeature=@'

Automatically tracks the bookmark if it is new.
"""#
            arg "<NAME=REVISION>…" var=#true
        }'#
@usage 'flag --dry-run help="Only display what will change on the remote"'
@usage 'flag "-o --option" help="Git push options" var=#true {
            arg <OPTION>… var=#true
        }'
export def "jj git push" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --remote: list<string>,                       # The remote(s) to push to (can be repeated)
    --bookmark (-b): list<string>,                # Push only this bookmark, or bookmarks matching a pattern (can be repeated)
    --tag (-t): list<string>,                     # Push only this tag, or tags matching a pattern (can be repeated)
    --all,                                        # Push all bookmarks and tags (including new ones)
    --tracked,                                    # Push all tracked bookmarks and tags
    --deleted,                                    # Push all deleted bookmarks and tags
    --allow-empty-description,                    # Allow pushing commits with empty descriptions
    --allow-private,                              # Allow pushing commits that are private
    --allow-conflicts,                            # Allow pushing commits that contain conflicts
    --revision (-r): list<string>,                # Push bookmarks and tags pointing to these commits (can be repeated)
    --change (-c): list<string>,                  # Push this commit by creating a bookmark (can be repeated)
    --named: list<string>,                        # Specify a new bookmark name and a revision to push under that name, e.g. '--named myfeature=@'
    --dry-run,                                    # Only display what will change on the remote
    --option (-o): list<string>,                  # Git push options
]: nothing -> string {
    ^jj git push ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --remote: $remote
        --bookmark: $bookmark
        --tag: $tag
        --all: $all
        --tracked: $tracked
        --deleted: $deleted
        --allow-empty-description: $allow_empty_description
        --allow-private: $allow_private
        --allow-conflicts: $allow_conflicts
        --revision: $revision
        --change: $change
        --named: $named
        --dry-run: $dry_run
        --option: $option
    })
}

# Manage Git remotes
#
# The Git repo will be a bare git repo stored inside the `.jj/` directory.
@usage 'long_help #"""
Manage Git remotes

The Git repo will be a bare git repo stored inside the `.jj/` directory.
"""#'
export def "jj git remote" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj git remote ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Add a Git remote
@usage 'flag --push-url help="The URL used for push" {
                long_help #"""
The URL used for push

Local path will be resolved to absolute form
"""#
                arg <PUSH_URL>
            }'
@usage r#'arg <REMOTE> help="The remote's name"'#
@usage r#'arg <URL> help="The remote's URL or path" help_long=#"""
The remote's URL or path

Local path will be resolved to absolute form.
"""#'#
@usage 'complete url type=url'
@usage 'complete push_url type=url'
export def "jj git remote add" [
    remote: string,                               # The remote's name
    url: string@"nusage complete",                # The remote's URL or path
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --push-url: string@"nusage complete",         # The URL used for push
]: nothing -> string {
    ^jj git remote add ...(nusage argv [$remote $url] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --push-url: $push_url
    })
}

# List Git remotes
export def "jj git remote list" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj git remote list ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Remove a Git remote and forget its bookmarks
@usage r#'arg <REMOTE> help="The remote's name"'#
export def "jj git remote remove" [
    remote: string,                               # The remote's name
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj git remote remove ...(nusage argv [$remote] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Rename a Git remote
@usage 'arg <OLD> help="The name of an existing remote"'
@usage 'arg <NEW> help="The desired name for `old`"'
export def "jj git remote rename" [
    old: string,                                  # The name of an existing remote
    new: string,                                  # The desired name for `old`
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj git remote rename ...(nusage argv [$old $new] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Set the URL of a Git remote
@usage 'flag --push help="The URL or path to push to" {
                long_help #"""
The URL or path to push to

Local path will be resolved to absolute form.
"""#
                arg <PUSH>
            }'
@usage 'flag --fetch help="The URL or path to fetch from" conflicts=URL {
                long_help #"""
The URL or path to fetch from

Local path will be resolved to absolute form.
"""#
                arg <FETCH>
            }'
@usage r#'arg <REMOTE> help="The remote's name"'#
@usage 'arg "[URL]" help="The URL or path to fetch from" help_long=#"""
The URL or path to fetch from

This is a short form, equivalent to using the explicit --fetch.

Local path will be resolved to absolute form.
"""# required=#false'
@usage 'complete url type=url'
@usage 'complete push type=url'
@usage 'complete fetch type=url'
export def "jj git remote set-url" [
    remote: string,                               # The remote's name
    url?: string@"nusage complete",               # The URL or path to fetch from
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --push: string@"nusage complete",             # The URL or path to push to
    --fetch: string@"nusage complete",            # The URL or path to fetch from
]: nothing -> string {
    ^jj git remote set-url ...(nusage argv [$remote $url] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --push: $push
        --fetch: $fetch
    })
}

# Show the underlying Git directory of a repository using the Git backend
export def "jj git root" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj git root ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Print this message or the help of the given subcommand(s)
@usage r#'flag "-k --keyword" help="Show help for keywords instead of commands" conflicts=COMMAND {
        arg <KEYWORD> {
            choices {
                choice bookmarks help="Named pointers to revisions (similar to Git's branches)"
                choice config help="How and where to set configuration options"
                choice filesets help="A functional language for selecting a set of files"
                choice glossary help="Definitions of various terms"
                choice revsets help="A functional language for selecting a set of revision"
                choice templates help="A functional language to customize command output"
                choice tutorial help="Show a tutorial to get started with jj"
            }
        }
    }'#
@usage 'arg "[COMMAND]…" help="Print help for the subcommand(s)" required=#false var=#true var_min=1'
export def "jj help" [
    ...command: string,                                                                      # Print help for the subcommand(s)
    --repository (-R): path@"nusage complete",                                               # Path to repository to operate on
    --ignore-working-copy,                                                                   # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                                                                # Run the command as usual but don't integrate any operations
    --ignore-immutable,                                                                      # Allow rewriting immutable commits
    --at-operation: string,                                                                  # Operation to load the repo at
    --debug,                                                                                 # Enable debug logging
    --color: string@[always never debug auto],                                               # When to colorize output
    --quiet,                                                                                 # Silence non-primary command output
    --no-pager,                                                                              # Disable the pager
    --config: list<string>,                                                                  # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",                                             # Additional configuration files (can be repeated)
    --keyword (-k): string@[bookmarks config filesets glossary revsets templates tutorial],  # Show help for keywords instead of commands
]: nothing -> string {
    ^jj help ...(nusage argv [...$command] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --keyword: $keyword
    })
}

# Show differences between the diffs of two revisions
#
# This is like running `jj diff -r` on each change, then comparing those results. It answers: "How do the modifications introduced by revision A differ from the modifications introduced by revision B?"
#
# For example, if two changes both add a feature but implement it differently, `jj interdiff --from @- --to other` shows what one implementation adds or removes that the other doesn't.
#
# A common use of this command is to compare how a change has changed since the last push to a remote:
#
# ```sh $ jj interdiff --from push-xyz@origin --to push-xyz ```
#
# This command is different from `jj diff --from A --to B`, which compares file contents directly. `interdiff` compares what the changes do in terms of their patches, rather than their file contents. This makes a difference when the two revisions have different parents: `jj diff --from A --to B` will include the changes between their parents while `jj interdiff --from A --to B` will not.
#
# Technically, this works by rebasing `--from` onto `--to`'s parents and comparing the result to `--to`.
#
# To see the changes throughout the whole evolution of a change instead of between just two revisions, use `jj evolog -p` instead.
@usage r#'long_help #"""
Show differences between the diffs of two revisions

This is like running `jj diff -r` on each change, then comparing those results. It answers: "How do the modifications introduced by revision A differ from the modifications introduced by revision B?"

For example, if two changes both add a feature but implement it differently, `jj interdiff --from @- --to other` shows what one implementation adds or removes that the other doesn't.

A common use of this command is to compare how a change has changed since the last push to a remote:

```sh $ jj interdiff --from push-xyz@origin --to push-xyz ```

This command is different from `jj diff --from A --to B`, which compares file contents directly. `interdiff` compares what the changes do in terms of their patches, rather than their file contents. This makes a difference when the two revisions have different parents: `jj diff --from A --to B` will include the changes between their parents while `jj interdiff --from A --to B` will not.

Technically, this works by rebasing `--from` onto `--to`'s parents and comparing the result to `--to`.

To see the changes throughout the whole evolution of a change instead of between just two revisions, use `jj evolog -p` instead.
"""#'#
@usage 'flag "-f --from" help="The first revision to compare (default: @)" {
        arg <REVSET>
    }'
@usage 'flag "-t --to" help="The second revision to compare (default: @)" {
        arg <REVSET>
    }'
@usage 'flag "-s --summary" help="For each path, show only whether it was modified, added, or deleted" help_heading="Diff Formatting Options"'
@usage 'flag --stat help="Show a histogram of the changes" help_heading="Diff Formatting Options"'
@usage r#'flag --types help="For each path, show only its type before and after" help_heading="Diff Formatting Options" {
        long_help #"""
For each path, show only its type before and after

The diff is shown as two letters. The first letter indicates the type before and the second letter indicates the type after. '-' indicates that the path was not present, 'F' represents a regular file, `L' represents a symlink, 'C' represents a conflict, and 'G' represents a Git submodule.
"""#
    }'#
@usage r#'flag --name-only help="For each path, show only its path" help_heading="Diff Formatting Options" {
        long_help #"""
For each path, show only its path

Typically useful for shell commands like: `jj diff -r @- --name-only | xargs perl -pi -e's/OLD/NEW/g`
"""#
    }'#
@usage 'flag --git help="Show a Git-format diff" help_heading="Diff Formatting Options"'
@usage 'flag --color-words help="Show a word-level diff with changes indicated only by color" help_heading="Diff Formatting Options"'
@usage 'flag --tool help="Generate diff by external command" help_heading="Diff Formatting Options" {
        long_help #"""
Generate diff by external command

A builtin format can also be specified as `:<name>`. For example, `--tool=:git` is equivalent to `--git`.
"""#
        arg <TOOL>
    }'
@usage 'flag --context help="Number of lines of context to show" help_heading="Diff Formatting Options" {
        arg <CONTEXT>
    }'
@usage 'flag "-w --ignore-all-space" help="Ignore whitespace when comparing lines" help_heading="Diff Formatting Options"'
@usage 'flag "-b --ignore-space-change" help="Ignore changes in amount of whitespace when comparing lines" conflicts=--ignore-all-space help_heading="Diff Formatting Options"'
@usage 'arg "[FILESETS]…" help="Restrict the diff to these paths" required=#false var=#true var_min=1'
@usage 'group short-format "--summary" "--stat" "--types" "--name-only"'
@usage 'group long-format "--git" "--color-words"'
@usage 'group to_diff "--from" "--to" required=#true multiple=#true'
@usage 'complete filesets type=path'
export def "jj interdiff" [
    ...filesets: path@"nusage complete",          # Restrict the diff to these paths
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --from (-f): string,                          # The first revision to compare (default: @)
    --to (-t): string,                            # The second revision to compare (default: @)
    --summary (-s),                               # For each path, show only whether it was modified, added, or deleted
    --stat,                                       # Show a histogram of the changes
    --types,                                      # For each path, show only its type before and after
    --name-only,                                  # For each path, show only its path
    --git,                                        # Show a Git-format diff
    --color-words,                                # Show a word-level diff with changes indicated only by color
    --tool: string,                               # Generate diff by external command
    --context: string,                            # Number of lines of context to show
    --ignore-all-space (-w),                      # Ignore whitespace when comparing lines
    --ignore-space-change (-b),                   # Ignore changes in amount of whitespace when comparing lines
]: nothing -> string {
    ^jj interdiff ...(nusage argv [...$filesets] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --from: $from
        --to: $to
        --summary: $summary
        --stat: $stat
        --types: $types
        --name-only: $name_only
        --git: $git
        --color-words: $color_words
        --tool: $tool
        --context: $context
        --ignore-all-space: $ignore_all_space
        --ignore-space-change: $ignore_space_change
    })
}

# Show revision history
#
# Renders a graphical view of the project's history, ordered with children before parents. By default, the output only includes mutable revisions, along with some additional revisions for context. Use `jj log -r ::` to see all revisions. See [`jj help -k revsets`][revsets] for information about the syntax.
#
# [revsets]: https://docs.jj-vcs.dev/latest/revsets/
#
# Spans of revisions that are not included in the graph by `--revision` are rendered as a synthetic node labeled "(elided revisions)".
#
# The working-copy commit is indicated by a `@` symbol in the graph. [Immutable revisions] have a `◆` symbol. Other commits have a `○` symbol. All of these symbols can be [customized][log node style].
#
# [Immutable revisions]: https://docs.jj-vcs.dev/latest/config/#set-of-immutable-commits
#
# [log node style]: https://docs.jj-vcs.dev/latest/config/#node-style
@usage r#'long_help #"""
Show revision history

Renders a graphical view of the project's history, ordered with children before parents. By default, the output only includes mutable revisions, along with some additional revisions for context. Use `jj log -r ::` to see all revisions. See [`jj help -k revsets`][revsets] for information about the syntax.

[revsets]: https://docs.jj-vcs.dev/latest/revsets/

Spans of revisions that are not included in the graph by `--revision` are rendered as a synthetic node labeled "(elided revisions)".

The working-copy commit is indicated by a `@` symbol in the graph. [Immutable revisions] have a `◆` symbol. Other commits have a `○` symbol. All of these symbols can be [customized][log node style].

[Immutable revisions]: https://docs.jj-vcs.dev/latest/config/#set-of-immutable-commits

[log node style]: https://docs.jj-vcs.dev/latest/config/#node-style
"""#'#
@usage 'flag "-r --revision" help="Which revisions to show" var=#true {
        alias "--revisions" hide=#true
        long_help #"""
Which revisions to show

If no paths nor revisions are specified, this defaults to the `revsets.log` setting.
"""#
        arg <REVSETS>… var=#true
    }'
@usage 'flag "-n --limit" help="Limit number of revisions to show" {
        long_help #"""
Limit number of revisions to show

Applied after revisions are filtered and reordered topologically, but before being reversed.
"""#
        arg <LIMIT>
    }'
@usage 'flag --reversed help="Show revisions in the opposite order (older revisions first)"'
@usage 'flag "-G --no-graph" help="Show a flat list of revisions instead of a graph"'
@usage 'flag "-T --template" help="Render each revision using the given template" {
        long_help #"""
Render each revision using the given template

Run `jj log -T` to list the built-in templates.

All 0-argument methods of the [`Commit` type][Commit] are available as keywords in the template expression. See [`jj help -k templates`][templates] for more information.

If not specified, this defaults to the `templates.log` setting.

[Commit]: https://docs.jj-vcs.dev/latest/templates/#commit-type

[templates]: https://docs.jj-vcs.dev/latest/templates/
"""#
        arg <TEMPLATE>
    }'
@usage 'flag "-p --patch" help="Show patch"'
@usage 'flag --count help="Print the number of commits instead of showing them" {
        conflicts "--summary" "--stat" "--types" "--name-only" "--git" "--color-words" "--tool" "--context" "--ignore-all-space" "--ignore-space-change" "--no-graph" "--patch" "--reversed" "--template"
    }'
@usage 'flag "-s --summary" help="For each path, show only whether it was modified, added, or deleted" help_heading="Diff Formatting Options"'
@usage 'flag --stat help="Show a histogram of the changes" help_heading="Diff Formatting Options"'
@usage r#'flag --types help="For each path, show only its type before and after" help_heading="Diff Formatting Options" {
        long_help #"""
For each path, show only its type before and after

The diff is shown as two letters. The first letter indicates the type before and the second letter indicates the type after. '-' indicates that the path was not present, 'F' represents a regular file, `L' represents a symlink, 'C' represents a conflict, and 'G' represents a Git submodule.
"""#
    }'#
@usage r#'flag --name-only help="For each path, show only its path" help_heading="Diff Formatting Options" {
        long_help #"""
For each path, show only its path

Typically useful for shell commands like: `jj diff -r @- --name-only | xargs perl -pi -e's/OLD/NEW/g`
"""#
    }'#
@usage 'flag --git help="Show a Git-format diff" help_heading="Diff Formatting Options"'
@usage 'flag --color-words help="Show a word-level diff with changes indicated only by color" help_heading="Diff Formatting Options"'
@usage 'flag --tool help="Generate diff by external command" help_heading="Diff Formatting Options" {
        long_help #"""
Generate diff by external command

A builtin format can also be specified as `:<name>`. For example, `--tool=:git` is equivalent to `--git`.
"""#
        arg <TOOL>
    }'
@usage 'flag --context help="Number of lines of context to show" help_heading="Diff Formatting Options" {
        arg <CONTEXT>
    }'
@usage 'flag --ignore-all-space help="Ignore whitespace when comparing lines" help_heading="Diff Formatting Options"'
@usage 'flag --ignore-space-change help="Ignore changes in amount of whitespace when comparing lines" conflicts=--ignore-all-space help_heading="Diff Formatting Options"'
@usage 'arg "[FILESETS]…" help="Show revisions modifying the given paths" required=#false var=#true var_min=1'
@usage 'group short-format "--summary" "--stat" "--types" "--name-only"'
@usage 'group long-format "--git" "--color-words"'
@usage 'complete filesets type=path'
@usage 'output "json" framing="jsonl" { schema "{\n  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",\n  \"title\": \"A commit, one line of `jj log`\",\n  \"$ref\": \"#/$defs/commit\",\n  \"$defs\": {\n    \"commit_id\": {\n      \"type\": \"string\",\n      \"pattern\": \"^[0-9a-f]+$\"\n    },\n    \"signature\": {\n      \"type\": \"object\",\n      \"required\": [\n        \"name\",\n        \"email\",\n        \"timestamp\"\n      ],\n      \"additionalProperties\": false,\n      \"properties\": {\n        \"name\": {\n          \"type\": \"string\"\n        },\n        \"email\": {\n          \"type\": \"string\"\n        },\n        \"timestamp\": {\n          \"type\": \"string\",\n          \"format\": \"date-time\"\n        }\n      }\n    },\n    \"commit\": {\n      \"type\": \"object\",\n      \"required\": [\n        \"commit_id\",\n        \"parents\",\n        \"change_id\",\n        \"description\",\n        \"author\",\n        \"committer\"\n      ],\n      \"additionalProperties\": false,\n      \"properties\": {\n        \"commit_id\": {\n          \"$ref\": \"#/$defs/commit_id\"\n        },\n        \"parents\": {\n          \"type\": \"array\",\n          \"items\": {\n            \"$ref\": \"#/$defs/commit_id\"\n          }\n        },\n        \"change_id\": {\n          \"type\": \"string\",\n          \"pattern\": \"^[k-z]+$\"\n        },\n        \"description\": {\n          \"type\": \"string\"\n        },\n        \"author\": {\n          \"$ref\": \"#/$defs/signature\"\n        },\n        \"committer\": {\n          \"$ref\": \"#/$defs/signature\"\n        }\n      }\n    }\n  }\n}\n" }'
export def "jj log" [
    ...filesets: path@"nusage complete",          # Show revisions modifying the given paths
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --revision (-r): list<string>,                # Which revisions to show
    --limit (-n): string,                         # Limit number of revisions to show
    --reversed,                                   # Show revisions in the opposite order (older revisions first)
    --patch (-p),                                 # Show patch
    --count,                                      # Print the number of commits instead of showing them
    --summary (-s),                               # For each path, show only whether it was modified, added, or deleted
    --stat,                                       # Show a histogram of the changes
    --types,                                      # For each path, show only its type before and after
    --name-only,                                  # For each path, show only its path
    --git,                                        # Show a Git-format diff
    --color-words,                                # Show a word-level diff with changes indicated only by color
    --tool: string,                               # Generate diff by external command
    --context: string,                            # Number of lines of context to show
    --ignore-all-space,                           # Ignore whitespace when comparing lines
    --ignore-space-change,                        # Ignore changes in amount of whitespace when comparing lines
]: nothing -> table<commit_id: string, parents: list<string>, change_id: string, description: string, author: record<name: string, email: string, timestamp: datetime>, committer: record<name: string, email: string, timestamp: datetime>> {
    let text = ^jj log --no-graph --template "json(self) ++ \"\\n\"" ...(nusage argv [...$filesets] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --revision: $revision
        --limit: $limit
        --reversed: $reversed
        --patch: $patch
        --count: $count
        --summary: $summary
        --stat: $stat
        --types: $types
        --name-only: $name_only
        --git: $git
        --color-words: $color_words
        --tool: $tool
        --context: $context
        --ignore-all-space: $ignore_all_space
        --ignore-space-change: $ignore_space_change
    })
    nusage decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"title\":\"A commit, one line of `jj log`\",\"$ref\":\"#/$defs/commit\",\"$defs\":{\"commit_id\":{\"type\":\"string\",\"pattern\":\"^[0-9a-f]+$\"},\"signature\":{\"type\":\"object\",\"required\":[\"name\",\"email\",\"timestamp\"],\"additionalProperties\":false,\"properties\":{\"name\":{\"type\":\"string\"},\"email\":{\"type\":\"string\"},\"timestamp\":{\"type\":\"string\",\"format\":\"date-time\"}}},\"commit\":{\"type\":\"object\",\"required\":[\"commit_id\",\"parents\",\"change_id\",\"description\",\"author\",\"committer\"],\"additionalProperties\":false,\"properties\":{\"commit_id\":{\"$ref\":\"#/$defs/commit_id\"},\"parents\":{\"type\":\"array\",\"items\":{\"$ref\":\"#/$defs/commit_id\"}},\"change_id\":{\"type\":\"string\",\"pattern\":\"^[k-z]+$\"},\"description\":{\"type\":\"string\"},\"author\":{\"$ref\":\"#/$defs/signature\"},\"committer\":{\"$ref\":\"#/$defs/signature\"}}}}}" { from json --objects | into datetime author.timestamp | into datetime committer.timestamp } --lines
}

# Modify the metadata of a revision without changing its content
#
# Whenever any metadata is updated, the committer name, email, and timestamp are also updated for all rebased commits. The name and email may come from the `JJ_USER` and `JJ_EMAIL` environment variables, as well as by passing `--config user.name` and `--config user.email`.
@usage 'long_help #"""
Modify the metadata of a revision without changing its content

Whenever any metadata is updated, the committer name, email, and timestamp are also updated for all rebased commits. The name and email may come from the `JJ_USER` and `JJ_EMAIL` environment variables, as well as by passing `--config user.name` and `--config user.email`.
"""#'
@usage 'flag -r var=#true hide=#true {
        arg <REVSETS>… var=#true
    }'
@usage 'flag --update-change-id help="Generate a new change-id" {
        long_help #"""
Generate a new change-id

This generates a new change-id for the revision.
"""#
    }'
@usage 'flag "-m --message" help="Update the change description" var=#true {
        long_help #"""
Update the change description

This updates the change description, without opening the editor.

Use `jj describe` if you want to use an editor.
"""#
        arg <MESSAGE>… var=#true
    }'
@usage 'flag --update-author-timestamp help="Update the author timestamp" {
        long_help #"""
Update the author timestamp

This updates the author date to the current time, without modifying the author.
"""#
    }'
@usage r#'flag --update-author help="Update the author to the configured user" {
        long_help #"""
Update the author to the configured user

This updates the author name and email. The author timestamp is not modified – use --update-author-timestamp to update the author timestamp.

You can use it in combination with the JJ_USER and JJ_EMAIL environment variables to set a different author:

$ JJ_USER='Foo Bar' JJ_EMAIL=foo@bar.com jj metaedit --update-author
"""#
    }'#
@usage 'flag --author help="Set author to the provided string" conflicts=--update-author {
        long_help #"""
Set author to the provided string

This changes author name and email while retaining author timestamp for non-discardable commits.

```shell $ jj metaedit --author "Foo Bar <foo@bar.com>" ```
"""#
        arg <AUTHOR>
    }'
@usage r#'flag --author-timestamp help="Set the author date to the given date" conflicts=--update-author-timestamp {
        long_help #"""
Set the author date to the given date

The date can either be human readable ([RFC2822], eg 'Sun, 23 Jan 2000 01:23:45 PST') or a time stamp ([RFC3339], eg '2000-01-23T01:23:45-08:00').

[RFC2822]: https://datatracker.ietf.org/doc/html/rfc2822

[RFC3339]: https://datatracker.ietf.org/doc/html/rfc3339
"""#
        arg <AUTHOR_TIMESTAMP>
    }'#
@usage r#'flag --force-rewrite help="Rewrite the commit, even if no other metadata changed" {
        long_help #"""
Rewrite the commit, even if no other metadata changed

This updates the committer timestamp to the current time, as well as the committer name and email.

Even if this option is not passed, the committer name, email, and timestamp will be updated if other metadata is updated. This option just forces every commit to be rewritten whether or not there are other changes.

You can use it in combination with the `JJ_USER` and `JJ_EMAIL` environment variables to set a different committer:

$ JJ_USER='Foo Bar' JJ_EMAIL=foo@bar.com jj metaedit --force-rewrite
"""#
    }'#
@usage 'arg "[REVSETS]…" help="The revision(s) to modify (default: @) [aliases: -r]" required=#false var=#true var_min=1'
export def "jj metaedit" [
    ...revsets: string,                           # The revision(s) to modify (default: @) [aliases: -r]
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --update-change-id,                           # Generate a new change-id
    --message (-m): list<string>,                 # Update the change description
    --update-author-timestamp,                    # Update the author timestamp
    --update-author,                              # Update the author to the configured user
    --author: string,                             # Set author to the provided string
    --author-timestamp: string,                   # Set the author date to the given date
    --force-rewrite,                              # Rewrite the commit, even if no other metadata changed
]: nothing -> string {
    ^jj metaedit ...(nusage argv [...$revsets] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --update-change-id: $update_change_id
        --message: $message
        --update-author-timestamp: $update_author_timestamp
        --update-author: $update_author
        --author: $author
        --author-timestamp: $author_timestamp
        --force-rewrite: $force_rewrite
    })
}

# Create a new, empty change and (by default) edit it in the working copy
#
# By default, `jj` will edit the new change, making the [working copy] represent the new commit. This can be avoided with `--no-edit`.
#
# Note that you can create a merge commit by specifying multiple revisions as argument. For example, `jj new @ main` will create a new commit with the working copy and the `main` bookmark as parents.
#
# [working copy]: https://docs.jj-vcs.dev/latest/working-copy/
@usage 'long_help #"""
Create a new, empty change and (by default) edit it in the working copy

By default, `jj` will edit the new change, making the [working copy] represent the new commit. This can be avoided with `--no-edit`.

Note that you can create a merge commit by specifying multiple revisions as argument. For example, `jj new @ main` will create a new commit with the working copy and the `main` bookmark as parents.

[working copy]: https://docs.jj-vcs.dev/latest/working-copy/
"""#'
@usage 'flag -o var=#true hide=#true {
        alias "-d" "-r" hide=#true
        arg <REVSETS>… var=#true
    }'
@usage 'flag "-m --message" help="The change description to use" var=#true {
        arg <MESSAGE>… var=#true
    }'
@usage 'flag --no-edit help="Do not edit the newly created change" conflicts=--edit'
@usage 'flag --edit help="No-op flag to pair with --no-edit" hide=#true'
@usage 'flag "-A --insert-after --after" help="Insert the new change after the given commit(s)" var=#true {
        long_help #"""
Insert the new change after the given commit(s)

Example: `jj new --insert-after A` creates a new change between `A` and
its children:

```text
                B   C
                 \ /
    B   C   =>    @
     \ /          |
      A           A
```

Specifying `--insert-after` multiple times will relocate all children of
the given commits.

Example: `jj new --insert-after A --insert-after X` creates a change
with `A` and `X` as parents, and rebases all children on top of the new
change:

```text
                B   Y
                 \ /
    B  Y    =>    @
    |  |         / \
    A  X        A   X
```
"""#
        arg <REVSETS>… var=#true
    }'
@usage 'flag "-B --insert-before --before" help="Insert the new change before the given commit(s)" var=#true {
        long_help #"""
Insert the new change before the given commit(s)

Example: `jj new --insert-before C` creates a new change between `C` and
its parents:

```text
                   C
                   |
      C     =>     @
     / \          / \
    A   B        A   B
```

`--insert-after` and `--insert-before` can be combined.

Example: `jj new --insert-after A --insert-before D`:

```text
    D            D
    |           / \
    C          |   C
    |    =>    @   |
    B          |   B
    |           \ /
    A            A
```

Similar to `--insert-after`, you can specify `--insert-before` multiple
times.
"""#
        arg <REVSETS>… var=#true
    }'
@usage 'arg "[REVSETS]…" help="Parent(s) of the new change [default: @] [aliases: -o, -r]" required=#false var=#true var_min=1'
export def "jj new" [
    ...revsets: string,                           # Parent(s) of the new change [default: @] [aliases: -o, -r]
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --message (-m): list<string>,                 # The change description to use
    --no-edit,                                    # Do not edit the newly created change
    --insert-after (-A): list<string>,            # Insert the new change after the given commit(s)
    --insert-before (-B): list<string>,           # Insert the new change before the given commit(s)
]: nothing -> string {
    ^jj new ...(nusage argv [...$revsets] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --message: $message
        --no-edit: $no_edit
        --insert-after: $insert_after
        --insert-before: $insert_before
    })
}

# Move the working-copy commit to the child revision
#
# The command creates a new empty working copy revision that is the child of a
# descendant `offset` revisions ahead of the parent of the current working
# copy.
#
# For example, when the offset is 1:
#
# ```text
# D        D @
# |        |/
# C @  =>  C
# |/       |
# B        B
# ```
#
# If `--edit` is passed, the working copy revision is changed to the child of
# the current working copy revision.
#
# ```text
# D        D
# |        |
# C        C
# |        |
# B   =>   @
# |        |
# @        A
# ```
@usage 'long_help #"""
Move the working-copy commit to the child revision

The command creates a new empty working copy revision that is the child of a
descendant `offset` revisions ahead of the parent of the current working
copy.

For example, when the offset is 1:

```text
D        D @
|        |/
C @  =>  C
|/       |
B        B
```

If `--edit` is passed, the working copy revision is changed to the child of
the current working copy revision.

```text
D        D
|        |
C        C
|        |
B   =>   @
|        |
@        A
```
"""#'
@usage 'flag "-e --edit" help="Instead of creating a new working-copy commit on top of the target commit (like `jj new`), edit the target commit directly (like `jj edit`)" {
        long_help #"""
Instead of creating a new working-copy commit on top of the target commit (like `jj new`), edit the target commit directly (like `jj edit`)

Takes precedence over config in `ui.movement.edit`; i.e. will negate `ui.movement.edit = false`
"""#
    }'
@usage 'flag "-n --no-edit" help="The inverse of `--edit`" conflicts=--edit {
        long_help #"""
The inverse of `--edit`

Takes precedence over config in `ui.movement.edit`; i.e. will negate `ui.movement.edit = true`
"""#
    }'
@usage 'flag --conflict help="Jump to the next conflicted descendant" conflicts=OFFSET'
@usage 'arg "[OFFSET]" help="How many revisions to move forward. Advances to the next child by default" required=#false default="1"'
export def "jj next" [
    offset?: string,                              # How many revisions to move forward. Advances to the next child by default
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --edit (-e),                                  # Instead of creating a new working-copy commit on top of the target commit (like `jj new`), edit the target commit directly (like `jj edit`)
    --no-edit (-n),                               # The inverse of `--edit`
    --conflict,                                   # Jump to the next conflicted descendant
]: nothing -> string {
    ^jj next ...(nusage argv [$offset] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --edit: $edit
        --no-edit: $no_edit
        --conflict: $conflict
    })
}

# Commands for working with the operation log
#
# See the [operation log documentation] for more information.
#
# [operation log documentation]: https://docs.jj-vcs.dev/latest/operation-log/
@usage 'alias op'
@usage 'long_help #"""
Commands for working with the operation log

See the [operation log documentation] for more information.

[operation log documentation]: https://docs.jj-vcs.dev/latest/operation-log/
"""#'
export def "jj operation" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj operation ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Abandon operation history
#
# To discard old operation history, use `jj op abandon ..<operation ID>`. It will abandon the specified operation and all its ancestors. The descendants will be reparented onto the root operation.
#
# To discard recent operations, use `jj op restore <operation ID>` followed by `jj op abandon <operation ID>..@-`.
#
# Previous versions of a change (or predecessors) are also discarded if they become unreachable from the operation history. The abandoned operations, commits, and other unreachable objects can later be garbage collected by using `jj util gc` command.
@usage 'long_help #"""
Abandon operation history

To discard old operation history, use `jj op abandon ..<operation ID>`. It will abandon the specified operation and all its ancestors. The descendants will be reparented onto the root operation.

To discard recent operations, use `jj op restore <operation ID>` followed by `jj op abandon <operation ID>..@-`.

Previous versions of a change (or predecessors) are also discarded if they become unreachable from the operation history. The abandoned operations, commits, and other unreachable objects can later be garbage collected by using `jj util gc` command.
"""#'
@usage 'arg <OPERATION> help="The operation or operation range to abandon"'
export def "jj operation abandon" [
    operation: string,                            # The operation or operation range to abandon
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj operation abandon ...(nusage argv [$operation] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Compare changes to the repository between two operations
@usage 'flag "--operation --op" help="Show repository changes in this operation, compared to its parent" {
            arg <OPERATION>
        }'
@usage 'flag "-f --from" help="Show repository changes from this operation" conflicts=--operation {
            arg <FROM>
        }'
@usage 'flag "-t --to" help="Show repository changes to this operation" conflicts=--operation {
            arg <TO>
        }'
@usage 'flag "-G --no-graph" help="Show a flat list of modified changes instead of a graph"'
@usage 'flag "-p --patch" help="Show patch of modifications to changes" {
            long_help #"""
Show patch of modifications to changes

If the previous version has different parents, it will be temporarily rebased to the parents of the new version, so the diff is not contaminated by unrelated changes.
"""#
        }'
@usage 'flag "-s --summary" help="For each path, show only whether it was modified, added, or deleted" help_heading="Diff Formatting Options"'
@usage 'flag --stat help="Show a histogram of the changes" help_heading="Diff Formatting Options"'
@usage r#'flag --types help="For each path, show only its type before and after" help_heading="Diff Formatting Options" {
            long_help #"""
For each path, show only its type before and after

The diff is shown as two letters. The first letter indicates the type before and the second letter indicates the type after. '-' indicates that the path was not present, 'F' represents a regular file, `L' represents a symlink, 'C' represents a conflict, and 'G' represents a Git submodule.
"""#
        }'#
@usage r#'flag --name-only help="For each path, show only its path" help_heading="Diff Formatting Options" {
            long_help #"""
For each path, show only its path

Typically useful for shell commands like: `jj diff -r @- --name-only | xargs perl -pi -e's/OLD/NEW/g`
"""#
        }'#
@usage 'flag --git help="Show a Git-format diff" help_heading="Diff Formatting Options"'
@usage 'flag --color-words help="Show a word-level diff with changes indicated only by color" help_heading="Diff Formatting Options"'
@usage 'flag --tool help="Generate diff by external command" help_heading="Diff Formatting Options" {
            long_help #"""
Generate diff by external command

A builtin format can also be specified as `:<name>`. For example, `--tool=:git` is equivalent to `--git`.
"""#
            arg <TOOL>
        }'
@usage 'flag --context help="Number of lines of context to show" help_heading="Diff Formatting Options" {
            arg <CONTEXT>
        }'
@usage 'flag --ignore-all-space help="Ignore whitespace when comparing lines" help_heading="Diff Formatting Options"'
@usage 'flag --ignore-space-change help="Ignore changes in amount of whitespace when comparing lines" conflicts=--ignore-all-space help_heading="Diff Formatting Options"'
@usage 'flag --show-changes-in help="Show only changed revisions matching the given revset expression" help_heading="Diff Formatting Options" {
            long_help #"""
Show only changed revisions matching the given revset expression

If no revisions are specified, this defaults to the `revsets.op-diff-changes-in` setting.
"""#
            arg <REVSETS>
        }'
@usage 'group short-format "--summary" "--stat" "--types" "--name-only"'
@usage 'group long-format "--git" "--color-words"'
export def "jj operation diff" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --operation: string,                          # Show repository changes in this operation, compared to its parent
    --from (-f): string,                          # Show repository changes from this operation
    --to (-t): string,                            # Show repository changes to this operation
    --no-graph (-G),                              # Show a flat list of modified changes instead of a graph
    --patch (-p),                                 # Show patch of modifications to changes
    --summary (-s),                               # For each path, show only whether it was modified, added, or deleted
    --stat,                                       # Show a histogram of the changes
    --types,                                      # For each path, show only its type before and after
    --name-only,                                  # For each path, show only its path
    --git,                                        # Show a Git-format diff
    --color-words,                                # Show a word-level diff with changes indicated only by color
    --tool: string,                               # Generate diff by external command
    --context: string,                            # Number of lines of context to show
    --ignore-all-space,                           # Ignore whitespace when comparing lines
    --ignore-space-change,                        # Ignore changes in amount of whitespace when comparing lines
    --show-changes-in: string,                    # Show only changed revisions matching the given revset expression
]: nothing -> string {
    ^jj operation diff ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --operation: $operation
        --from: $from
        --to: $to
        --no-graph: $no_graph
        --patch: $patch
        --summary: $summary
        --stat: $stat
        --types: $types
        --name-only: $name_only
        --git: $git
        --color-words: $color_words
        --tool: $tool
        --context: $context
        --ignore-all-space: $ignore_all_space
        --ignore-space-change: $ignore_space_change
        --show-changes-in: $show_changes_in
    })
}

# Make an operation part of the operation log
#
# By default, operations are automatically integrated into the operation log, but `--no-integrate-operation` or internal errors may cause that to not happen. This command can then be used for making such operations part of the operation log.
#
# Running this command on an operation that is already in the operation log (`jj op log`) has no effect.
@usage 'long_help #"""
Make an operation part of the operation log

By default, operations are automatically integrated into the operation log, but `--no-integrate-operation` or internal errors may cause that to not happen. This command can then be used for making such operations part of the operation log.

Running this command on an operation that is already in the operation log (`jj op log`) has no effect.
"""#'
@usage 'arg <OPERATION> help="The operation to integrate"'
export def "jj operation integrate" [
    operation: string,                            # The operation to integrate
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj operation integrate ...(nusage argv [$operation] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Show the operation log
#
# Like other commands, `jj op log` snapshots the current working-copy changes and reconciles divergent operations. Use `--at-op=@ --ignore-working-copy` to inspect the current state without mutation.
@usage 'long_help #"""
Show the operation log

Like other commands, `jj op log` snapshots the current working-copy changes and reconciles divergent operations. Use `--at-op=@ --ignore-working-copy` to inspect the current state without mutation.
"""#'
@usage 'flag "-n --limit" help="Limit number of operations to show" {
            long_help #"""
Limit number of operations to show

Applied after operations are reordered topologically, but before being reversed.
"""#
            arg <LIMIT>
        }'
@usage 'flag --reversed help="Show operations in the opposite order (older operations first)"'
@usage 'flag "-G --no-graph" help="Show a flat list of operations instead of a graph"'
@usage 'flag "-T --template" help="Render each operation using the given template" {
            long_help #"""
Render each operation using the given template

All 0-argument methods of the [`Operation` type][Operation] are available as keywords in the template expression. See [`jj help -k templates`][templates] for more information.

If not specified, this defaults to the `templates.op_log` setting.

[Operation]: https://docs.jj-vcs.dev/latest/templates/#operation-type

[templates]: https://docs.jj-vcs.dev/latest/templates/
"""#
            arg <TEMPLATE>
        }'
@usage 'flag "-d --op-diff" help="Show changes to the repository at each operation"'
@usage 'flag "-p --patch" help="Show patch of modifications to changes (implies --op-diff)" {
            long_help #"""
Show patch of modifications to changes (implies --op-diff)

If the previous version has different parents, it will be temporarily rebased to the parents of the new version, so the diff is not contaminated by unrelated changes.
"""#
        }'
@usage 'flag "-s --summary" help="For each path, show only whether it was modified, added, or deleted" help_heading="Diff Formatting Options"'
@usage 'flag --stat help="Show a histogram of the changes" help_heading="Diff Formatting Options"'
@usage r#'flag --types help="For each path, show only its type before and after" help_heading="Diff Formatting Options" {
            long_help #"""
For each path, show only its type before and after

The diff is shown as two letters. The first letter indicates the type before and the second letter indicates the type after. '-' indicates that the path was not present, 'F' represents a regular file, `L' represents a symlink, 'C' represents a conflict, and 'G' represents a Git submodule.
"""#
        }'#
@usage r#'flag --name-only help="For each path, show only its path" help_heading="Diff Formatting Options" {
            long_help #"""
For each path, show only its path

Typically useful for shell commands like: `jj diff -r @- --name-only | xargs perl -pi -e's/OLD/NEW/g`
"""#
        }'#
@usage 'flag --git help="Show a Git-format diff" help_heading="Diff Formatting Options"'
@usage 'flag --color-words help="Show a word-level diff with changes indicated only by color" help_heading="Diff Formatting Options"'
@usage 'flag --tool help="Generate diff by external command" help_heading="Diff Formatting Options" {
            long_help #"""
Generate diff by external command

A builtin format can also be specified as `:<name>`. For example, `--tool=:git` is equivalent to `--git`.
"""#
            arg <TOOL>
        }'
@usage 'flag --context help="Number of lines of context to show" help_heading="Diff Formatting Options" {
            arg <CONTEXT>
        }'
@usage 'flag --ignore-all-space help="Ignore whitespace when comparing lines" help_heading="Diff Formatting Options"'
@usage 'flag --ignore-space-change help="Ignore changes in amount of whitespace when comparing lines" conflicts=--ignore-all-space help_heading="Diff Formatting Options"'
@usage 'flag --show-changes-in help="Show only changed revisions matching the given revset expression" help_heading="Diff Formatting Options" {
            long_help #"""
Show only changed revisions matching the given revset expression

If no revisions are specified, this defaults to the `revsets.op-diff-changes-in` setting.
"""#
            arg <REVSETS>
        }'
@usage 'group short-format "--summary" "--stat" "--types" "--name-only"'
@usage 'group long-format "--git" "--color-words"'
@usage 'output "json" framing="jsonl" { schema "{\n  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",\n  \"title\": \"An operation, one line of `jj operation log`\",\n  \"type\": \"object\",\n  \"required\": [\n    \"id\",\n    \"parents\",\n    \"time\",\n    \"description\",\n    \"hostname\",\n    \"username\",\n    \"is_snapshot\",\n    \"workspace_name\",\n    \"attributes\"\n  ],\n  \"additionalProperties\": false,\n  \"properties\": {\n    \"id\": {\n      \"type\": \"string\",\n      \"pattern\": \"^[0-9a-f]+$\"\n    },\n    \"parents\": {\n      \"type\": \"array\",\n      \"items\": {\n        \"type\": \"string\",\n        \"pattern\": \"^[0-9a-f]+$\"\n      }\n    },\n    \"time\": {\n      \"type\": \"object\",\n      \"required\": [\n        \"start\",\n        \"end\"\n      ],\n      \"additionalProperties\": false,\n      \"properties\": {\n        \"start\": {\n          \"type\": \"string\",\n          \"format\": \"date-time\"\n        },\n        \"end\": {\n          \"type\": \"string\",\n          \"format\": \"date-time\"\n        }\n      }\n    },\n    \"description\": {\n      \"type\": \"string\"\n    },\n    \"hostname\": {\n      \"type\": \"string\"\n    },\n    \"username\": {\n      \"type\": \"string\"\n    },\n    \"is_snapshot\": {\n      \"type\": \"boolean\"\n    },\n    \"workspace_name\": {\n      \"type\": [\n        \"string\",\n        \"null\"\n      ]\n    },\n    \"attributes\": {\n      \"type\": \"object\",\n      \"additionalProperties\": {\n        \"type\": \"string\"\n      }\n    }\n  }\n}\n" }'
export def "jj operation log" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --limit (-n): string,                         # Limit number of operations to show
    --reversed,                                   # Show operations in the opposite order (older operations first)
    --op-diff (-d),                               # Show changes to the repository at each operation
    --patch (-p),                                 # Show patch of modifications to changes (implies --op-diff)
    --summary (-s),                               # For each path, show only whether it was modified, added, or deleted
    --stat,                                       # Show a histogram of the changes
    --types,                                      # For each path, show only its type before and after
    --name-only,                                  # For each path, show only its path
    --git,                                        # Show a Git-format diff
    --color-words,                                # Show a word-level diff with changes indicated only by color
    --tool: string,                               # Generate diff by external command
    --context: string,                            # Number of lines of context to show
    --ignore-all-space,                           # Ignore whitespace when comparing lines
    --ignore-space-change,                        # Ignore changes in amount of whitespace when comparing lines
    --show-changes-in: string,                    # Show only changed revisions matching the given revset expression
]: nothing -> table<id: string, parents: list<string>, time: record<start: datetime, end: datetime>, description: string, hostname: string, username: string, is_snapshot: bool, workspace_name: oneof<string, nothing>, attributes: record> {
    let text = ^jj operation log --no-graph --template "json(self) ++ \"\\n\"" ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --limit: $limit
        --reversed: $reversed
        --op-diff: $op_diff
        --patch: $patch
        --summary: $summary
        --stat: $stat
        --types: $types
        --name-only: $name_only
        --git: $git
        --color-words: $color_words
        --tool: $tool
        --context: $context
        --ignore-all-space: $ignore_all_space
        --ignore-space-change: $ignore_space_change
        --show-changes-in: $show_changes_in
    })
    nusage decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"title\":\"An operation, one line of `jj operation log`\",\"type\":\"object\",\"required\":[\"id\",\"parents\",\"time\",\"description\",\"hostname\",\"username\",\"is_snapshot\",\"workspace_name\",\"attributes\"],\"additionalProperties\":false,\"properties\":{\"id\":{\"type\":\"string\",\"pattern\":\"^[0-9a-f]+$\"},\"parents\":{\"type\":\"array\",\"items\":{\"type\":\"string\",\"pattern\":\"^[0-9a-f]+$\"}},\"time\":{\"type\":\"object\",\"required\":[\"start\",\"end\"],\"additionalProperties\":false,\"properties\":{\"start\":{\"type\":\"string\",\"format\":\"date-time\"},\"end\":{\"type\":\"string\",\"format\":\"date-time\"}}},\"description\":{\"type\":\"string\"},\"hostname\":{\"type\":\"string\"},\"username\":{\"type\":\"string\"},\"is_snapshot\":{\"type\":\"boolean\"},\"workspace_name\":{\"type\":[\"string\",\"null\"]},\"attributes\":{\"type\":\"object\",\"additionalProperties\":{\"type\":\"string\"}}}}" { from json --objects | into datetime time.start | into datetime time.end } --lines
}

# Create a new operation that restores the repo to an earlier state
#
# This restores the repo to the state at the specified operation, effectively undoing all later operations. It does so by creating a new operation.
@usage 'long_help #"""
Create a new operation that restores the repo to an earlier state

This restores the repo to the state at the specified operation, effectively undoing all later operations. It does so by creating a new operation.
"""#'
@usage r#'flag --what help="What portions of the local state to restore (can be repeated)" var=#true {
            long_help #"""
What portions of the local state to restore (can be repeated)

This option is EXPERIMENTAL.
"""#
            default {
                repo
                remote-tracking
            }
            arg <WHAT>… var=#true {
                choices {
                    choice repo help="The jj repo state and local bookmarks"
                    choice remote-tracking help="The remote-tracking bookmarks. Do not restore these if you'd like to push after the undo"
                }
            }
        }'#
@usage 'arg <OPERATION> help="The operation to restore to" help_long=#"""
The operation to restore to

Use `jj op log` to find an operation to restore to. Use e.g. `jj --at-op=<operation ID> log` before restoring to an operation to see the state of the repo at that operation.
"""#'
export def "jj operation restore" [
    operation: string,                            # The operation to restore to
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --what: list<string>@[repo remote-tracking],  # What portions of the local state to restore (can be repeated)
]: nothing -> string {
    ^jj operation restore ...(nusage argv [$operation] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --what: $what
    })
}

# Create a new operation that reverts an earlier operation
#
# This reverts an individual operation by applying the inverse of the operation.
@usage 'long_help #"""
Create a new operation that reverts an earlier operation

This reverts an individual operation by applying the inverse of the operation.
"""#'
@usage r#'flag --what help="What portions of the local state to restore (can be repeated)" var=#true {
            long_help #"""
What portions of the local state to restore (can be repeated)

This option is EXPERIMENTAL.
"""#
            default {
                repo
                remote-tracking
            }
            arg <WHAT>… var=#true {
                choices {
                    choice repo help="The jj repo state and local bookmarks"
                    choice remote-tracking help="The remote-tracking bookmarks. Do not restore these if you'd like to push after the undo"
                }
            }
        }'#
@usage 'arg "[OPERATION]" help="The operation to revert" help_long=#"""
The operation to revert

Use `jj op log` to find an operation to revert.
"""# required=#false default=@'
export def "jj operation revert" [
    operation?: string,                           # The operation to revert
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --what: list<string>@[repo remote-tracking],  # What portions of the local state to restore (can be repeated)
]: nothing -> string {
    ^jj operation revert ...(nusage argv [$operation] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --what: $what
    })
}

# Show changes to the repository in an operation
@usage 'flag "-G --no-graph" help="Show a flat list of modified changes instead of a graph"'
@usage 'flag "-T --template" help="Render the operation using the given template" {
            long_help #"""
Render the operation using the given template

All 0-argument methods of the [`Operation` type][Operation] are available as keywords in the template expression. See [`jj help -k templates`][templates] for more information.

If not specified, this defaults to the `templates.op_show` setting.

[Operation]: https://docs.jj-vcs.dev/latest/templates/#operation-type

[templates]: https://docs.jj-vcs.dev/latest/templates/
"""#
            arg <TEMPLATE>
        }'
@usage 'flag "-p --patch" help="Show patch of modifications to changes" {
            long_help #"""
Show patch of modifications to changes

If the previous version has different parents, it will be temporarily rebased to the parents of the new version, so the diff is not contaminated by unrelated changes.
"""#
        }'
@usage 'flag --no-op-diff help="Do not show operation diff" {
            conflicts "--patch" "--summary" "--stat" "--types" "--name-only" "--git" "--color-words" "--tool" "--context" "--ignore-all-space" "--ignore-space-change"
        }'
@usage 'flag "-s --summary" help="For each path, show only whether it was modified, added, or deleted" help_heading="Diff Formatting Options"'
@usage 'flag --stat help="Show a histogram of the changes" help_heading="Diff Formatting Options"'
@usage r#'flag --types help="For each path, show only its type before and after" help_heading="Diff Formatting Options" {
            long_help #"""
For each path, show only its type before and after

The diff is shown as two letters. The first letter indicates the type before and the second letter indicates the type after. '-' indicates that the path was not present, 'F' represents a regular file, `L' represents a symlink, 'C' represents a conflict, and 'G' represents a Git submodule.
"""#
        }'#
@usage r#'flag --name-only help="For each path, show only its path" help_heading="Diff Formatting Options" {
            long_help #"""
For each path, show only its path

Typically useful for shell commands like: `jj diff -r @- --name-only | xargs perl -pi -e's/OLD/NEW/g`
"""#
        }'#
@usage 'flag --git help="Show a Git-format diff" help_heading="Diff Formatting Options"'
@usage 'flag --color-words help="Show a word-level diff with changes indicated only by color" help_heading="Diff Formatting Options"'
@usage 'flag --tool help="Generate diff by external command" help_heading="Diff Formatting Options" {
            long_help #"""
Generate diff by external command

A builtin format can also be specified as `:<name>`. For example, `--tool=:git` is equivalent to `--git`.
"""#
            arg <TOOL>
        }'
@usage 'flag --context help="Number of lines of context to show" help_heading="Diff Formatting Options" {
            arg <CONTEXT>
        }'
@usage 'flag --ignore-all-space help="Ignore whitespace when comparing lines" help_heading="Diff Formatting Options"'
@usage 'flag --ignore-space-change help="Ignore changes in amount of whitespace when comparing lines" conflicts=--ignore-all-space help_heading="Diff Formatting Options"'
@usage 'flag --show-changes-in help="Show only changed revisions matching the given revset expression" help_heading="Diff Formatting Options" {
            long_help #"""
Show only changed revisions matching the given revset expression

If no revisions are specified, this defaults to the `revsets.op-diff-changes-in` setting.
"""#
            arg <REVSETS>
        }'
@usage 'arg "[OPERATION]" help="Show repository changes in this operation, compared to its parent(s)" required=#false default=@'
@usage 'group short-format "--summary" "--stat" "--types" "--name-only"'
@usage 'group long-format "--git" "--color-words"'
export def "jj operation show" [
    operation?: string,                           # Show repository changes in this operation, compared to its parent(s)
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --no-graph (-G),                              # Show a flat list of modified changes instead of a graph
    --template (-T): string,                      # Render the operation using the given template
    --patch (-p),                                 # Show patch of modifications to changes
    --no-op-diff,                                 # Do not show operation diff
    --summary (-s),                               # For each path, show only whether it was modified, added, or deleted
    --stat,                                       # Show a histogram of the changes
    --types,                                      # For each path, show only its type before and after
    --name-only,                                  # For each path, show only its path
    --git,                                        # Show a Git-format diff
    --color-words,                                # Show a word-level diff with changes indicated only by color
    --tool: string,                               # Generate diff by external command
    --context: string,                            # Number of lines of context to show
    --ignore-all-space,                           # Ignore whitespace when comparing lines
    --ignore-space-change,                        # Ignore changes in amount of whitespace when comparing lines
    --show-changes-in: string,                    # Show only changed revisions matching the given revset expression
]: nothing -> string {
    ^jj operation show ...(nusage argv [$operation] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --no-graph: $no_graph
        --template: $template
        --patch: $patch
        --no-op-diff: $no_op_diff
        --summary: $summary
        --stat: $stat
        --types: $types
        --name-only: $name_only
        --git: $git
        --color-words: $color_words
        --tool: $tool
        --context: $context
        --ignore-all-space: $ignore_all_space
        --ignore-space-change: $ignore_space_change
        --show-changes-in: $show_changes_in
    })
}

# Parallelize revisions by making them siblings
#
# Running `jj parallelize 1::2` will transform the history like this:
# ```text
# 3
# |             3
# 2            / \
# |    ->     1   2
# 1            \ /
# |             0
# 0
# ```
#
# The command effectively says "these revisions are actually independent",
# meaning that they should no longer be ancestors/descendants of each other.
# However, revisions outside the set that were previously ancestors of a
# revision in the set will remain ancestors of it. For example, revision 0
# above remains an ancestor of both 1 and 2. Similarly,
# revisions outside the set that were previously descendants of a revision
# in the set will remain descendants of it. For example, revision 3 above
# remains a descendant of both 1 and 2.
#
# Therefore, `jj parallelize '1 | 3'` is a no-op. That's because 2, which is
# not in the target set, was a descendant of 1 before, so it remains a
# descendant, and it was an ancestor of 3 before, so it remains an ancestor.
@usage r#'long_help #"""
Parallelize revisions by making them siblings

Running `jj parallelize 1::2` will transform the history like this:
```text
3
|             3
2            / \
|    ->     1   2
1            \ /
|             0
0
```

The command effectively says "these revisions are actually independent",
meaning that they should no longer be ancestors/descendants of each other.
However, revisions outside the set that were previously ancestors of a
revision in the set will remain ancestors of it. For example, revision 0
above remains an ancestor of both 1 and 2. Similarly,
revisions outside the set that were previously descendants of a revision
in the set will remain descendants of it. For example, revision 3 above
remains a descendant of both 1 and 2.

Therefore, `jj parallelize '1 | 3'` is a no-op. That's because 2, which is
not in the target set, was a descendant of 1 before, so it remains a
descendant, and it was an ancestor of 3 before, so it remains an ancestor.
"""#'#
@usage 'flag -r var=#true hide=#true {
        arg <REVSETS>… var=#true
    }'
@usage 'arg "[REVSETS]…" help="The revisions to parallelize [aliases: -r]" required=#false var=#true var_min=1'
export def "jj parallelize" [
    ...revsets: string,                           # The revisions to parallelize [aliases: -r]
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj parallelize ...(nusage argv [...$revsets] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Change the working copy revision relative to the parent revision
#
# The command creates a new empty working copy revision that is the child of
# an ancestor `offset` revisions behind the parent of the current working
# copy.
#
# For example, when the offset is 1:
#
# ```text
# D @      D
# |/       |
# A   =>   A @
# |        |/
# B        B
# ```
#
# If `--edit` is passed, the working copy revision is changed to the parent of
# the current working copy revision.
#
# ```text
# D @      D
# |/       |
# C   =>   @
# |        |
# B        B
# |        |
# A        A
# ```
@usage 'long_help #"""
Change the working copy revision relative to the parent revision

The command creates a new empty working copy revision that is the child of
an ancestor `offset` revisions behind the parent of the current working
copy.

For example, when the offset is 1:

```text
D @      D
|/       |
A   =>   A @
|        |/
B        B
```

If `--edit` is passed, the working copy revision is changed to the parent of
the current working copy revision.

```text
D @      D
|/       |
C   =>   @
|        |
B        B
|        |
A        A
```
"""#'
@usage 'flag "-e --edit" help="Edit the parent directly, instead of moving the working-copy commit" {
        long_help #"""
Edit the parent directly, instead of moving the working-copy commit

Takes precedence over config in `ui.movement.edit`; i.e. will negate `ui.movement.edit = false`
"""#
    }'
@usage 'flag "-n --no-edit" help="The inverse of `--edit`" conflicts=--edit {
        long_help #"""
The inverse of `--edit`

Takes precedence over config in `ui.movement.edit`; i.e. will negate `ui.movement.edit = true`
"""#
    }'
@usage 'flag --conflict help="Jump to the previous conflicted ancestor" conflicts=OFFSET'
@usage 'arg "[OFFSET]" help="How many revisions to move backward. Moves to the parent by default" required=#false default="1"'
export def "jj prev" [
    offset?: string,                              # How many revisions to move backward. Moves to the parent by default
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --edit (-e),                                  # Edit the parent directly, instead of moving the working-copy commit
    --no-edit (-n),                               # The inverse of `--edit`
    --conflict,                                   # Jump to the previous conflicted ancestor
]: nothing -> string {
    ^jj prev ...(nusage argv [$offset] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --edit: $edit
        --no-edit: $no_edit
        --conflict: $conflict
    })
}

# Move revisions to different parent(s)
#
# This command moves revisions to different parent(s) while preserving the
# changes (diff) in the revisions.
#
# There are three different ways of specifying which revisions to rebase:
#
# * `--source/-s` to rebase a revision and its descendants
# * `--branch/-b` to rebase a whole branch, relative to the destination
# * `--revisions/-r` to rebase the specified revisions without their
#   descendants
#
# If no option is specified, it defaults to `-b @`.
#
# There are three different ways of specifying where the revisions should be
# rebased to:
#
# * `--onto/-o` to rebase the revisions onto the specified targets
# * `--insert-after/-A` to rebase the revisions onto the specified targets and
#   to rebase the targets' descendants onto the rebased revisions
# * `--insert-before/-B` to rebase the revisions onto the specified targets'
#   parents and to rebase the targets and their descendants onto the rebased
#   revisions
#
# See the sections below for details about the different ways of specifying
# which revisions to rebase where.
#
# If a working-copy revision gets abandoned, it will be given a new, empty
# revision. This is true in general; it is not specific to this command.
#
# ### Specifying which revisions to rebase
#
# With `--source/-s`, the command rebases the specified revision and its
# descendants to the destination. For example, `jj rebase -s M -o O` would
# transform your history like this (letters followed by an apostrophe are
# post-rebase versions):
#
# ```text
# O           N'
# |           |
# | N         M'
# | |         |
# | M         O
# | |    =>   |
# | | L       | L
# | |/        | |
# | K         | K
# |/          |/
# J           J
# ```
#
# Each revision passed to `-s` will become a direct child of the destination,
# so if you instead run `jj rebase -s M -s N -o O` (or `jj rebase -s 'M|N' -o
# O`) in the example above, then N' would instead be a direct child of O.
#
# With `--branch/-b`, the command rebases the whole "branch" containing the
# specified revision. A "branch" is the set of revisions that includes:
#
# * the specified revision and ancestors that are not also ancestors of the
#   destination
# * all descendants of those revisions
#
# In other words, `jj rebase -b X -o Y` rebases revisions in the revset
# `(Y..X)::` (which is equivalent to `jj rebase -s 'roots(Y..X)' -o Y` for a
# single root). For example, either `jj rebase -b L -o O` or `jj rebase -b M
# -o O` would transform your history like this (because `L` and `M` are on the
# same "branch", relative to the destination):
#
# ```text
# O           N'
# |           |
# | N         M'
# | |         |
# | M         | L'
# | |    =>   |/
# | | L       K'
# | |/        |
# | K         O
# |/          |
# J           J
# ```
#
# With `--revisions/-r`, the command rebases only the specified revisions to
# the destination. Any "hole" left behind will be filled by rebasing
# descendants onto the specified revisions' parent(s). For example,
# `jj rebase -r K -o M` would transform your history like this:
#
# ```text
# M          K'
# |          |
# | L        M
# | |   =>   |
# | K        | L'
# |/         |/
# J          J
# ```
#
# Multiple revisions can be specified, and any dependencies (graph edges)
# within the set will be preserved. For example, `jj rebase -r 'K|N' -o O`
# would transform your history like this:
#
# ```text
# O           N'
# |           |
# | N         K'
# | |         |
# | M         O
# | |    =>   |
# | | L       | M'
# | |/        |/
# | K         | L'
# |/          |/
# J           J
# ```
#
# `jj rebase -s X` is similar to `jj rebase -r X::` and will behave the same
# if X is a single revision. However, if X is a set of multiple revisions,
# or if you passed multiple `-s` arguments, then `jj rebase -s` will make each
# of the specified revisions an immediate child of the destination, while
# `jj rebase -r` will preserve dependencies within the set.
#
# Note that you can create a merge revision by repeating the `-o` argument.
# For example, if you realize that revision L actually depends on revision M
# in order to work (in addition to its current parent K), you can run `jj
# rebase -s L -o K -o M`:
#
# ```text
# M          L'
# |          |\
# | L        M |
# | |   =>   | |
# | K        | K
# |/         |/
# J          J
# ```
#
# ### Specifying where to rebase the revisions
#
# With `--onto/-o`, the command rebases the selected revisions onto the
# targets. Existing descendants of the targets will not be affected. See
# the section above for examples.
#
# With `--insert-after/-A`, the selected revisions will be inserted after the
# targets. This is similar to `-o`, but if the targets have any existing
# descendants, then those will be rebased onto the rebased selected revisions.
#
# For example, `jj rebase -r K -A L` will rewrite history like this:
# ```text
# N           N'
# |           |
# | M         | M'
# |/          |/
# L      =>   K'
# |           |
# | K         L
# |/          |
# J           J
# ```
#
# The `-A` (and `-B`) argument can also be used for reordering revisions. For
# example, `jj rebase -r M -A J` will rewrite history like this:
# ```text
# M          L'
# |          |
# L          K'
# |     =>   |
# K          M'
# |          |
# J          J
# ```
#
# With `--insert-before/-B`, the selected revisions will be inserted before
# the targets. This is achieved by rebasing the selected revisions onto the
# target revisions' parents, and then rebasing the target revisions and their
# descendants onto the rebased revisions.
#
# For example, `jj rebase -r K -B L` will rewrite history like this:
# ```text
# N           N'
# |           |
# | M         | M'
# |/          |/
# L     =>    L'
# |           |
# | K         K'
# |/          |
# J           J
# ```
#
# The `-A` and `-B` arguments can also be combined, which can be useful around
# merges. For example, you can use `jj rebase -r K -A J -B M` to create a new
# merge (but `jj rebase -r M -o L -o K` might be simpler in this particular
# case):
# ```text
# M           M'
# |           |\
# L           L |
# |     =>    | |
# | K         | K'
# |/          |/
# J           J
# ```
#
# To insert a commit inside an existing merge with `jj rebase -r O -A K -B M`:
# ```text
# O           N'
# |           |\
# N           | M'
# |\          | |\
# | M         | O'|
# | |    =>   |/ /
# | L         | L
# | |         | |
# K |         K |
# |/          |/
# J           J
# ```
@usage r#'long_help #"""
Move revisions to different parent(s)

This command moves revisions to different parent(s) while preserving the
changes (diff) in the revisions.

There are three different ways of specifying which revisions to rebase:

* `--source/-s` to rebase a revision and its descendants
* `--branch/-b` to rebase a whole branch, relative to the destination
* `--revisions/-r` to rebase the specified revisions without their
  descendants

If no option is specified, it defaults to `-b @`.

There are three different ways of specifying where the revisions should be
rebased to:

* `--onto/-o` to rebase the revisions onto the specified targets
* `--insert-after/-A` to rebase the revisions onto the specified targets and
  to rebase the targets' descendants onto the rebased revisions
* `--insert-before/-B` to rebase the revisions onto the specified targets'
  parents and to rebase the targets and their descendants onto the rebased
  revisions

See the sections below for details about the different ways of specifying
which revisions to rebase where.

If a working-copy revision gets abandoned, it will be given a new, empty
revision. This is true in general; it is not specific to this command.

### Specifying which revisions to rebase

With `--source/-s`, the command rebases the specified revision and its
descendants to the destination. For example, `jj rebase -s M -o O` would
transform your history like this (letters followed by an apostrophe are
post-rebase versions):

```text
O           N'
|           |
| N         M'
| |         |
| M         O
| |    =>   |
| | L       | L
| |/        | |
| K         | K
|/          |/
J           J
```

Each revision passed to `-s` will become a direct child of the destination,
so if you instead run `jj rebase -s M -s N -o O` (or `jj rebase -s 'M|N' -o
O`) in the example above, then N' would instead be a direct child of O.

With `--branch/-b`, the command rebases the whole "branch" containing the
specified revision. A "branch" is the set of revisions that includes:

* the specified revision and ancestors that are not also ancestors of the
  destination
* all descendants of those revisions

In other words, `jj rebase -b X -o Y` rebases revisions in the revset
`(Y..X)::` (which is equivalent to `jj rebase -s 'roots(Y..X)' -o Y` for a
single root). For example, either `jj rebase -b L -o O` or `jj rebase -b M
-o O` would transform your history like this (because `L` and `M` are on the
same "branch", relative to the destination):

```text
O           N'
|           |
| N         M'
| |         |
| M         | L'
| |    =>   |/
| | L       K'
| |/        |
| K         O
|/          |
J           J
```

With `--revisions/-r`, the command rebases only the specified revisions to
the destination. Any "hole" left behind will be filled by rebasing
descendants onto the specified revisions' parent(s). For example,
`jj rebase -r K -o M` would transform your history like this:

```text
M          K'
|          |
| L        M
| |   =>   |
| K        | L'
|/         |/
J          J
```

Multiple revisions can be specified, and any dependencies (graph edges)
within the set will be preserved. For example, `jj rebase -r 'K|N' -o O`
would transform your history like this:

```text
O           N'
|           |
| N         K'
| |         |
| M         O
| |    =>   |
| | L       | M'
| |/        |/
| K         | L'
|/          |/
J           J
```

`jj rebase -s X` is similar to `jj rebase -r X::` and will behave the same
if X is a single revision. However, if X is a set of multiple revisions,
or if you passed multiple `-s` arguments, then `jj rebase -s` will make each
of the specified revisions an immediate child of the destination, while
`jj rebase -r` will preserve dependencies within the set.

Note that you can create a merge revision by repeating the `-o` argument.
For example, if you realize that revision L actually depends on revision M
in order to work (in addition to its current parent K), you can run `jj
rebase -s L -o K -o M`:

```text
M          L'
|          |\
| L        M |
| |   =>   | |
| K        | K
|/         |/
J          J
```

### Specifying where to rebase the revisions

With `--onto/-o`, the command rebases the selected revisions onto the
targets. Existing descendants of the targets will not be affected. See
the section above for examples.

With `--insert-after/-A`, the selected revisions will be inserted after the
targets. This is similar to `-o`, but if the targets have any existing
descendants, then those will be rebased onto the rebased selected revisions.

For example, `jj rebase -r K -A L` will rewrite history like this:
```text
N           N'
|           |
| M         | M'
|/          |/
L      =>   K'
|           |
| K         L
|/          |
J           J
```

The `-A` (and `-B`) argument can also be used for reordering revisions. For
example, `jj rebase -r M -A J` will rewrite history like this:
```text
M          L'
|          |
L          K'
|     =>   |
K          M'
|          |
J          J
```

With `--insert-before/-B`, the selected revisions will be inserted before
the targets. This is achieved by rebasing the selected revisions onto the
target revisions' parents, and then rebasing the target revisions and their
descendants onto the rebased revisions.

For example, `jj rebase -r K -B L` will rewrite history like this:
```text
N           N'
|           |
| M         | M'
|/          |/
L     =>    L'
|           |
| K         K'
|/          |
J           J
```

The `-A` and `-B` arguments can also be combined, which can be useful around
merges. For example, you can use `jj rebase -r K -A J -B M` to create a new
merge (but `jj rebase -r M -o L -o K` might be simpler in this particular
case):
```text
M           M'
|           |\
L           L |
|     =>    | |
| K         | K'
|/          |/
J           J
```

To insert a commit inside an existing merge with `jj rebase -r O -A K -B M`:
```text
O           N'
|           |\
N           | M'
|\          | |\
| M         | O'|
| |    =>   |/ /
| L         | L
| |         | |
K |         K |
|/          |/
J           J
```
"""#'#
@usage r#'flag "-b --branch" help="Rebase the whole branch relative to destination's ancestors (can be repeated)" var=#true {
        long_help #"""
Rebase the whole branch relative to destination's ancestors (can be repeated)

`jj rebase -b=br -o=dst` is equivalent to `jj rebase '-s=roots(dst..br)' -o=dst`.

If none of `-b`, `-s`, or `-r` is provided, then the default is `-b @`.
"""#
        arg <REVSETS>… var=#true
    }'#
@usage 'flag "-s --source" help="Rebase specified revision(s) together with their trees of descendants (can be repeated)" var=#true {
        long_help #"""
Rebase specified revision(s) together with their trees of descendants (can be repeated)

Each specified revision will become a direct child of the destination revision(s), even if some of the source revisions are descendants of others.

If none of `-b`, `-s`, or `-r` is provided, then the default is `-b @`.
"""#
        arg <REVSETS>… var=#true
    }'
@usage r#'flag "-r --revision" help="Rebase the given revisions, rebasing descendants onto this revision's parent(s)" var=#true {
        alias "--revisions" hide=#true
        long_help #"""
Rebase the given revisions, rebasing descendants onto this revision's parent(s)

Unlike `-s` or `-b`, you may `jj rebase -r` a revision `A` onto a descendant of `A`.

If none of `-b`, `-s`, or `-r` is provided, then the default is `-b @`.
"""#
        arg <REVSETS>… var=#true
    }'#
@usage 'flag "-o -d --onto --destination" help="The revision(s) to rebase onto (can be repeated to create a merge commit)" var=#true {
        arg <REVSETS>… var=#true
    }'
@usage 'flag "-A --insert-after --after" help="The revision(s) to insert after (can be repeated to create a merge commit)" var=#true conflicts=--onto {
        arg <REVSETS>… var=#true
    }'
@usage 'flag "-B --insert-before --before" help="The revision(s) to insert before (can be repeated to create a merge commit)" var=#true conflicts=--onto {
        arg <REVSETS>… var=#true
    }'
@usage 'flag --skip-emptied help="If true, when rebasing would produce an empty commit, the commit is abandoned. It will not be abandoned if it was already empty before the rebase. Will never skip merge commits with multiple non-empty parents"'
@usage 'flag --keep-divergent help="Keep divergent commits while rebasing" {
        long_help #"""
Keep divergent commits while rebasing

Without this flag, divergent commits are abandoned while rebasing if another commit with the same change ID is already present in the destination with identical changes.
"""#
    }'
@usage 'flag --simplify-parents help="Simplify parents of rebased commits, like `jj simplify-parents`, while rebasing them. Any parents that are ancestors of other parents will be removed"'
@usage 'group RebaseDestinationArgs "--onto" "--insert-after" "--insert-before" required=#true multiple=#true'
@usage 'group to_rebase "--branch" "--source" "--revision"'
export def "jj rebase" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --branch (-b): list<string>,                  # Rebase the whole branch relative to destination's ancestors (can be repeated)
    --source (-s): list<string>,                  # Rebase specified revision(s) together with their trees of descendants (can be repeated)
    --revision (-r): list<string>,                # Rebase the given revisions, rebasing descendants onto this revision's parent(s)
    --onto (-o): list<string>,                    # The revision(s) to rebase onto (can be repeated to create a merge commit)
    --insert-after (-A): list<string>,            # The revision(s) to insert after (can be repeated to create a merge commit)
    --insert-before (-B): list<string>,           # The revision(s) to insert before (can be repeated to create a merge commit)
    --skip-emptied,                               # If true, when rebasing would produce an empty commit, the commit is abandoned. It will not be abandoned if it was already empty before the rebase. Will never skip merge commits with multiple non-empty parents
    --keep-divergent,                             # Keep divergent commits while rebasing
    --simplify-parents,                           # Simplify parents of rebased commits, like `jj simplify-parents`, while rebasing them. Any parents that are ancestors of other parents will be removed
]: nothing -> string {
    ^jj rebase ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --branch: $branch
        --source: $source
        --revision: $revision
        --onto: $onto
        --insert-after: $insert_after
        --insert-before: $insert_before
        --skip-emptied: $skip_emptied
        --keep-divergent: $keep_divergent
        --simplify-parents: $simplify_parents
    })
}

# Redo the most recently undone operation
#
# This is the natural counterpart of `jj undo`. Repeated invocations of `jj undo` and `jj redo` act similarly to Undo/Redo commands in a text editor.
#
# Use `jj op log` to visualize the log of past operations, including a detailed description of any past undo/redo operations. See also `jj op restore` to explicitly restore an older operation by its id (available in the operation log).
#
# By default, `jj redo` refuses to redo an undo-operation that was performed in another workspace, since that is usually not what you meant to redo. Pass `--allow-cross-workspace` to redo it anyway, or use `jj op revert` to revert a specific undo operation.
@usage 'long_help #"""
Redo the most recently undone operation

This is the natural counterpart of `jj undo`. Repeated invocations of `jj undo` and `jj redo` act similarly to Undo/Redo commands in a text editor.

Use `jj op log` to visualize the log of past operations, including a detailed description of any past undo/redo operations. See also `jj op restore` to explicitly restore an older operation by its id (available in the operation log).

By default, `jj redo` refuses to redo an undo-operation that was performed in another workspace, since that is usually not what you meant to redo. Pass `--allow-cross-workspace` to redo it anyway, or use `jj op revert` to revert a specific undo operation.
"""#'
@usage 'flag --allow-cross-workspace help="Allow redoing an undo-operation that was performed in another workspace"'
export def "jj redo" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --allow-cross-workspace,                      # Allow redoing an undo-operation that was performed in another workspace
]: nothing -> string {
    ^jj redo ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --allow-cross-workspace: $allow_cross_workspace
    })
}

# Resolve conflicted files with an external merge tool
#
# Only conflicts that can be resolved with a 3-way merge are supported. See docs for merge tool configuration instructions. External merge tools will be invoked for each conflicted file one-by-one until all conflicts are resolved. To stop resolving conflicts, exit the merge tool without making any changes.
#
# Note that conflicts can also be resolved without using this command. You may edit the conflict markers in the conflicted file directly with a text editor.
@usage 'long_help #"""
Resolve conflicted files with an external merge tool

Only conflicts that can be resolved with a 3-way merge are supported. See docs for merge tool configuration instructions. External merge tools will be invoked for each conflicted file one-by-one until all conflicts are resolved. To stop resolving conflicts, exit the merge tool without making any changes.

Note that conflicts can also be resolved without using this command. You may edit the conflict markers in the conflicted file directly with a text editor.
"""#'
@usage 'flag "-r --revision" default=@ {
        arg <REVSET>
    }'
@usage 'flag "-l --list" help="Instead of resolving conflicts, list all the conflicts"'
@usage 'flag --tool help="Specify 3-way merge tool to be used" conflicts=--list {
        long_help #"""
Specify 3-way merge tool to be used

The built-in merge tools `:ours` and `:theirs` can be used to choose side #1 and side #2 of the conflict respectively.
"""#
        arg <NAME>
    }'
@usage 'arg "[FILESETS]…" help="Only resolve conflicts in these paths. You can use the `--list` argument to find paths to use here" required=#false var=#true var_min=1'
@usage 'complete filesets type=path'
export def "jj resolve" [
    ...filesets: path@"nusage complete",          # Only resolve conflicts in these paths. You can use the `--list` argument to find paths to use here
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --revision (-r): string,
    --list (-l),                                  # Instead of resolving conflicts, list all the conflicts
    --tool: string,                               # Specify 3-way merge tool to be used
]: nothing -> string {
    ^jj resolve ...(nusage argv [...$filesets] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --revision: $revision
        --list: $list
        --tool: $tool
    })
}

# Restore paths from another revision
#
# That means that the paths get the same content in the destination (`--into`) as they had in the source (`--from`). This is typically used for undoing changes to some paths in the working copy (`jj restore <paths>`).
#
# If only one of `--from` or `--into` is specified, the other one defaults to the working copy.
#
# When neither `--from` nor `--into` is specified, the command restores into the working copy from its parent(s). `jj restore` without arguments is similar to `jj abandon`, except that it leaves an empty revision with its description and other metadata preserved.
#
# See `jj diffedit` if you'd like to restore portions of files rather than entire files.
@usage r#'long_help #"""
Restore paths from another revision

That means that the paths get the same content in the destination (`--into`) as they had in the source (`--from`). This is typically used for undoing changes to some paths in the working copy (`jj restore <paths>`).

If only one of `--from` or `--into` is specified, the other one defaults to the working copy.

When neither `--from` nor `--into` is specified, the command restores into the working copy from its parent(s). `jj restore` without arguments is similar to `jj abandon`, except that it leaves an empty revision with its description and other metadata preserved.

See `jj diffedit` if you'd like to restore portions of files rather than entire files.
"""#'#
@usage 'flag "-f --from" help="Revision to restore from (source)" {
        arg <REVSET>
    }'
@usage 'flag "-t --into --to" help="Revision to restore into (destination)" {
        arg <REVSET>
    }'
@usage 'flag "-c --changes-in" help="Undo the changes in a revision as compared to the merge of its parents" {
        long_help #"""
Undo the changes in a revision as compared to the merge of its parents.

This undoes the changes that can be seen with `jj diff -r REVSET`. If `REVSET` only has a single parent, this option is equivalent to `jj restore --into REVSET --from REVSET-`.

The default behavior of `jj restore` is equivalent to `jj restore --changes-in @`.
"""#
        conflicts "--into" "--from"
        arg <REVSET>
    }'
@usage 'flag "-r --revision" help="Prints an error. DO NOT USE" hide=#true {
        long_help #"""
Prints an error. DO NOT USE.

If we followed the pattern of `jj diff` and `jj diffedit`, we would use `--revision` instead of `--changes-in` However, that would make it likely that someone unfamiliar with this pattern would use `-r` when they wanted `--from`. This would make a different revision empty, and the user might not even realize something went wrong.
"""#
        arg <REVISION>
    }'
@usage 'flag "-i --interactive" help="Interactively choose which parts to restore"'
@usage 'flag --tool help="Specify diff editor to be used (implies --interactive)" {
        arg <NAME>
    }'
@usage 'flag --restore-descendants help="Preserve the content (not the diff) when rebasing descendants"'
@usage 'arg "[FILESETS]…" help="Restore only these paths (instead of all paths)" required=#false var=#true var_min=1'
@usage 'complete filesets type=path'
export def "jj restore" [
    ...filesets: path@"nusage complete",          # Restore only these paths (instead of all paths)
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --from (-f): string,                          # Revision to restore from (source)
    --into (-t): string,                          # Revision to restore into (destination)
    --changes-in (-c): string,                    # Undo the changes in a revision as compared to the merge of its parents
    --interactive (-i),                           # Interactively choose which parts to restore
    --tool: string,                               # Specify diff editor to be used (implies --interactive)
    --restore-descendants,                        # Preserve the content (not the diff) when rebasing descendants
]: nothing -> string {
    ^jj restore ...(nusage argv [...$filesets] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --from: $from
        --into: $into
        --changes-in: $changes_in
        --interactive: $interactive
        --tool: $tool
        --restore-descendants: $restore_descendants
    })
}

# Apply the reverse of the given revision(s)
#
# The reverse of each of the given revisions is applied sequentially in reverse topological order at the given location.
#
# The description of the new revisions can be customized with the `templates.revert_description` config variable.
@usage 'long_help #"""
Apply the reverse of the given revision(s)

The reverse of each of the given revisions is applied sequentially in reverse topological order at the given location.

The description of the new revisions can be customized with the `templates.revert_description` config variable.
"""#'
@usage 'flag "-r --revision" help="The revision(s) to apply the reverse of" required=#true var=#true {
        alias "--revisions" hide=#true
        arg <REVSETS>… var=#true
    }'
@usage 'flag "-o -d --onto --destination" help="The revision(s) to apply the reverse changes on top of" var=#true {
        arg <REVSETS>… var=#true
    }'
@usage 'flag "-A --insert-after --after" help="The revision(s) to insert the reverse changes after (can be repeated to create a merge commit)" var=#true conflicts=--onto {
        arg <REVSETS>… var=#true
    }'
@usage 'flag "-B --insert-before --before" help="The revision(s) to insert the reverse changes before (can be repeated to create a merge commit)" var=#true conflicts=--onto {
        arg <REVSETS>… var=#true
    }'
@usage 'group location "--onto" "--insert-after" "--insert-before" required=#true multiple=#true'
export def "jj revert" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --revision (-r): list<string>,                # The revision(s) to apply the reverse of
    --onto (-o): list<string>,                    # The revision(s) to apply the reverse changes on top of
    --insert-after (-A): list<string>,            # The revision(s) to insert the reverse changes after (can be repeated to create a merge commit)
    --insert-before (-B): list<string>,           # The revision(s) to insert the reverse changes before (can be repeated to create a merge commit)
]: nothing -> string {
    ^jj revert ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --revision: $revision
        --onto: $onto
        --insert-after: $insert_after
        --insert-before: $insert_before
    })
}

# Show the current workspace root directory (shortcut for `jj workspace root`)
export def "jj root" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj root ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Run a command across a set of revisions.
#
# Checks out each revision in an isolated working copy, runs the command, then
# amends the revision with the resulting working copy. By default, descendants
# are rebased on top of the amended revisions, propagating the diff. Use
# `--restore-descendants` to keep descendants' content unchanged instead, or
# `--ignore-changes` to run the command without rewriting any commits.
#
# The command is executed with the following environment variables set:
#
# - JJ_CHANGE_ID
# - JJ_COMMIT_ID
# - JJ_WORKSPACE_ROOT
#
# ### Example
#
# ```shell
# # Run pre-commit on your local work
# $ jj run -j 4 -- pre-commit run .github/pre-commit.yaml
# ```
@usage r#'long_help #"""
Run a command across a set of revisions.

Checks out each revision in an isolated working copy, runs the command, then
amends the revision with the resulting working copy. By default, descendants
are rebased on top of the amended revisions, propagating the diff. Use
`--restore-descendants` to keep descendants' content unchanged instead, or
`--ignore-changes` to run the command without rewriting any commits.

The command is executed with the following environment variables set:

- JJ_CHANGE_ID
- JJ_COMMIT_ID
- JJ_WORKSPACE_ROOT

### Example

```shell
# Run pre-commit on your local work
$ jj run -j 4 -- pre-commit run .github/pre-commit.yaml
```
"""#'#
@usage 'flag "-r --revision" help="The revisions to change" var=#true {
        alias "--revisions" hide=#true
        arg <REVSETS>… var=#true
    }'
@usage 'flag -x help="A no-op option to match the interface of `git rebase -x`" hide=#true'
@usage 'flag "-j --jobs" help="How many processes should run in parallel" {
        long_help #"""
How many processes should run in parallel

Overrides the `run.jobs` config setting. Defaults to 1 if neither is set.
"""#
        arg <JOBS>
    }'
@usage 'flag --root help="Run the command from the working-copy root in each commit instead of from the subdirectory `jj run` was invoked from"'
@usage 'flag --clean help="Delete each working copy before running the command" {
        long_help #"""
Delete each working copy before running the command

By default `jj run` reuses working copies between invocations so build artifacts are preserved. With `--clean`, every commit starts from a freshly checked-out tree.
"""#
    }'
@usage 'flag --restore-descendants help="Preserve the content (not the diff) when rebasing descendants"'
@usage r#'flag --passthrough help="Pass through stdout and stderr directly to the terminal" {
        long_help #"""
Pass through stdout and stderr directly to the terminal

The command's stdout and stderr are connected directly to the terminal (instead of being captured), so programs that behave differently on a TTY (e.g. colored output, progress bars) work as expected. Stdin is not inherited. Only one job is allowed since parallel jobs would interleave their output.
"""#
    }'#
@usage 'flag --ignore-changes help="Run the command without rewriting any commits" conflicts=--restore-descendants {
        long_help #"""
Run the command without rewriting any commits.

Each revision is checked out and the command is executed, but changes made to the working copy are discarded. Useful for read-only checks (tests, linters).

This option permits running on immutable commits without passing `--ignore-immutable`.
"""#
    }'
@usage r#'flag --ignore-errors help="Continue with remaining revisions when a command's exit code indicates failure" {
        long_help #"""
Continue with remaining revisions when a command's exit code indicates failure

Any changes made by a failed command will not be saved, but changes from successful commands are still applied atomically at the end.

The exit code from any failed command will not impact the exit code of `jj run` itself.
"""#
    }'#
@usage 'flag --sparse-patterns help="How to handle sparse patterns when running the command. This is controlled per `jj run` invocation" default=copy {
        long_help #"""
How to handle sparse patterns when running the command. This is controlled per `jj run` invocation.

If sparse patterns were inherited in a run and a subsequent run is passed `--sparse-args full`, but no `--clean`, then the command will run in fully materialized workspace together with all artifacts left from the previous run.
"""#
        arg <SPARSE_PATTERNS> {
            choices {
                choice copy help="Copy all sparse patterns from the current workspace"
                choice full help="Include all files in the new workspace"
                choice empty help="Clear all files from the workspace (it will be empty)"
            }
        }
    }'
@usage 'arg <COMMAND> help="Command to run across all selected revisions"'
@usage 'arg "[ARGS]…" help="Arguments to pass to the command" help_long=#"""
Arguments to pass to the command

Hint: Use a `--` separator to allow passing arguments starting with `-`. For example `jj run --revisions=... -- cargo build --release`.
"""# required=#false var=#true var_min=1'
export def "jj run" [
    command: string,                              # Command to run across all selected revisions
    ...args: string,                              # Arguments to pass to the command
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --revision (-r): list<string>,                # The revisions to change
    --jobs (-j): string,                          # How many processes should run in parallel
    --root,                                       # Run the command from the working-copy root in each commit instead of from the subdirectory `jj run` was invoked from
    --clean,                                      # Delete each working copy before running the command
    --restore-descendants,                        # Preserve the content (not the diff) when rebasing descendants
    --passthrough,                                # Pass through stdout and stderr directly to the terminal
    --ignore-changes,                             # Run the command without rewriting any commits
    --ignore-errors,                              # Continue with remaining revisions when a command's exit code indicates failure
    --sparse-patterns: string@[copy full empty],  # How to handle sparse patterns when running the command. This is controlled per `jj run` invocation
]: nothing -> string {
    ^jj run ...(nusage argv [$command ...$args] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --revision: $revision
        --jobs: $jobs
        --root: $root
        --clean: $clean
        --restore-descendants: $restore_descendants
        --passthrough: $passthrough
        --ignore-changes: $ignore_changes
        --ignore-errors: $ignore_errors
        --sparse-patterns: $sparse_patterns
    })
}

# Show revision metadata and diff
@usage 'flag -r var=#true hide=#true display_order=0 {
        arg <REVSETS>… var=#true
    }'
@usage 'flag --reversed help="Show revisions in the opposite order (older revisions first)" display_order=1'
@usage 'flag "-T --template" help="Render each revision using the given template" display_order=2 {
        long_help #"""
Render each revision using the given template

All 0-argument methods of the [`Commit` type][Commit] are available as keywords in the template expression. See [`jj help -k templates`][templates] for more information.

If not specified, this defaults to the `templates.show` setting.

[Commit]: https://docs.jj-vcs.dev/latest/templates/#commit-type

[templates]: https://docs.jj-vcs.dev/latest/templates/
"""#
        arg <TEMPLATE>
    }'
@usage 'flag "-s --summary" help="For each path, show only whether it was modified, added, or deleted" help_heading="Diff Formatting Options" display_order=3'
@usage 'flag --stat help="Show a histogram of the changes" help_heading="Diff Formatting Options" display_order=4'
@usage r#'flag --types help="For each path, show only its type before and after" help_heading="Diff Formatting Options" display_order=5 {
        long_help #"""
For each path, show only its type before and after

The diff is shown as two letters. The first letter indicates the type before and the second letter indicates the type after. '-' indicates that the path was not present, 'F' represents a regular file, `L' represents a symlink, 'C' represents a conflict, and 'G' represents a Git submodule.
"""#
    }'#
@usage r#'flag --name-only help="For each path, show only its path" help_heading="Diff Formatting Options" display_order=6 {
        long_help #"""
For each path, show only its path

Typically useful for shell commands like: `jj diff -r @- --name-only | xargs perl -pi -e's/OLD/NEW/g`
"""#
    }'#
@usage 'flag --git help="Show a Git-format diff" help_heading="Diff Formatting Options" display_order=7'
@usage 'flag --color-words help="Show a word-level diff with changes indicated only by color" help_heading="Diff Formatting Options" display_order=8'
@usage 'flag --tool help="Generate diff by external command" help_heading="Diff Formatting Options" display_order=9 {
        long_help #"""
Generate diff by external command

A builtin format can also be specified as `:<name>`. For example, `--tool=:git` is equivalent to `--git`.
"""#
        arg <TOOL>
    }'
@usage 'flag --context help="Number of lines of context to show" help_heading="Diff Formatting Options" display_order=10 {
        arg <CONTEXT>
    }'
@usage 'flag --no-patch help="Do not show the patch" help_heading="Diff Formatting Options" display_order=13 {
        conflicts "--summary" "--stat" "--types" "--name-only" "--git" "--color-words" "--tool" "--context" "--ignore-all-space" "--ignore-space-change"
    }'
@usage 'flag "-w --ignore-all-space" help="Ignore whitespace when comparing lines" help_heading="Diff Formatting Options" display_order=11'
@usage 'flag "-b --ignore-space-change" help="Ignore changes in amount of whitespace when comparing lines" conflicts=--ignore-all-space help_heading="Diff Formatting Options" display_order=12'
@usage 'arg "[REVSETS]…" help="Show changes in these revisions, compared to their parent(s) [default: @] [aliases: -r]" required=#false var=#true var_min=1'
@usage 'group short-format "--summary" "--stat" "--types" "--name-only"'
@usage 'group long-format "--git" "--color-words"'
export def "jj show" [
    ...revsets: string,                           # Show changes in these revisions, compared to their parent(s) [default: @] [aliases: -r]
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --reversed,                                   # Show revisions in the opposite order (older revisions first)
    --template (-T): string,                      # Render each revision using the given template
    --summary (-s),                               # For each path, show only whether it was modified, added, or deleted
    --stat,                                       # Show a histogram of the changes
    --types,                                      # For each path, show only its type before and after
    --name-only,                                  # For each path, show only its path
    --git,                                        # Show a Git-format diff
    --color-words,                                # Show a word-level diff with changes indicated only by color
    --tool: string,                               # Generate diff by external command
    --context: string,                            # Number of lines of context to show
    --no-patch,                                   # Do not show the patch
    --ignore-all-space (-w),                      # Ignore whitespace when comparing lines
    --ignore-space-change (-b),                   # Ignore changes in amount of whitespace when comparing lines
]: nothing -> string {
    ^jj show ...(nusage argv [...$revsets] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --reversed: $reversed
        --template: $template
        --summary: $summary
        --stat: $stat
        --types: $types
        --name-only: $name_only
        --git: $git
        --color-words: $color_words
        --tool: $tool
        --context: $context
        --no-patch: $no_patch
        --ignore-all-space: $ignore_all_space
        --ignore-space-change: $ignore_space_change
    })
}

# Cryptographically sign a revision
#
# This command requires configuring a [commit signing] backend.
#
# [commit signing]: https://docs.jj-vcs.dev/latest/config/#commit-signing
@usage 'long_help #"""
Cryptographically sign a revision

This command requires configuring a [commit signing] backend.

[commit signing]: https://docs.jj-vcs.dev/latest/config/#commit-signing
"""#'
@usage 'flag "-r --revision" help="What revision(s) to sign" var=#true {
        alias "--revisions" hide=#true
        long_help #"""
What revision(s) to sign

If no revisions are specified, this defaults to the `revsets.sign` setting.

Note that revisions are always re-signed.

While that leads to discomfort for users, which sign with hardware devices, as of now we cannot reliably check if a commit is already signed by the user without creating a signature (see [#5786]).

[#5786]: https://github.com/jj-vcs/jj/issues/5786
"""#
        arg <REVSETS>… var=#true
    }'
@usage 'flag --key help="The key used for signing" {
        arg <KEY>
    }'
export def "jj sign" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --revision (-r): list<string>,                # What revision(s) to sign
    --key: string,                                # The key used for signing
]: nothing -> string {
    ^jj sign ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --revision: $revision
        --key: $key
    })
}

# Simplify parent edges for the specified revision(s)
#
# Removes all parents of each of the specified revisions that are also indirect ancestors of the same revisions through other parents. This has no effect on any revision's contents, including the working copy.
#
# In other words, for all (A, B, C) where A has (B, C) as parents and C is an ancestor of B, A will be rewritten to have only B as a parent instead of B+C.
@usage r#'long_help #"""
Simplify parent edges for the specified revision(s).

Removes all parents of each of the specified revisions that are also indirect ancestors of the same revisions through other parents. This has no effect on any revision's contents, including the working copy.

In other words, for all (A, B, C) where A has (B, C) as parents and C is an ancestor of B, A will be rewritten to have only B as a parent instead of B+C.
"""#'#
@usage 'flag "-s --source" help="Simplify specified revision(s) together with their trees of descendants (can be repeated)" var=#true {
        arg <REVSETS>… var=#true
    }'
@usage 'flag "-r --revision" help="Simplify specified revision(s) (can be repeated)" var=#true {
        alias "--revisions" hide=#true
        long_help #"""
Simplify specified revision(s) (can be repeated)

If both `--source` and `--revisions` are not provided, this defaults to the `revsets.simplify-parents` setting, or `reachable(@, mutable())` if it is not set.
"""#
        arg <REVSETS>… var=#true
    }'
export def "jj simplify-parents" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --source (-s): list<string>,                  # Simplify specified revision(s) together with their trees of descendants (can be repeated)
    --revision (-r): list<string>,                # Simplify specified revision(s) (can be repeated)
]: nothing -> string {
    ^jj simplify-parents ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --source: $source
        --revision: $revision
    })
}

# Manage which paths from the working-copy commit are present in the working copy
export def "jj sparse" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj sparse ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Start an editor to update the patterns that are present in the working copy
export def "jj sparse edit" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj sparse edit ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# List the patterns that are currently present in the working copy
#
# By default, a newly cloned or initialized repo will have have a pattern matching all files from the repo root. That pattern is rendered as `.` (a single period).
@usage 'long_help #"""
List the patterns that are currently present in the working copy

By default, a newly cloned or initialized repo will have have a pattern matching all files from the repo root. That pattern is rendered as `.` (a single period).
"""#'
export def "jj sparse list" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj sparse list ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Reset the patterns to include all files in the working copy
export def "jj sparse reset" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj sparse reset ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Update the patterns that are present in the working copy
#
# For example, if all you need is the `README.md` and the `lib/` directory, use `jj sparse set --clear --add README.md --add lib`. If you no longer need the `lib` directory, use `jj sparse set --remove lib`.
@usage 'long_help #"""
Update the patterns that are present in the working copy

For example, if all you need is the `README.md` and the `lib/` directory, use `jj sparse set --clear --add README.md --add lib`. If you no longer need the `lib` directory, use `jj sparse set --remove lib`.
"""#'
@usage 'flag --add help="Patterns to add to the working copy" var=#true {
            arg <ADD>… var=#true
        }'
@usage 'flag --remove help="Patterns to remove from the working copy" var=#true conflicts=--clear {
            arg <REMOVE>… var=#true
        }'
@usage 'flag --clear help="Include no files in the working copy (combine with --add)"'
@usage 'complete add type=path'
@usage 'complete remove type=path'
export def "jj sparse set" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --add: list<path>@"nusage complete",          # Patterns to add to the working copy
    --remove: list<path>@"nusage complete",       # Patterns to remove from the working copy
    --clear,                                      # Include no files in the working copy (combine with --add)
]: nothing -> string {
    ^jj sparse set ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --add: $add
        --remove: $remove
        --clear: $clear
    })
}

# Split a revision in two
#
# Starts a [diff editor] on the changes in the revision. Edit the right side
# of the diff until it has the content you want in the first commit. Once you
# close the editor, your revision will be split into two commits.
#
# [diff editor]:
#     https://docs.jj-vcs.dev/latest/config/#editing-diffs
#
# By default, the selected changes stay in the original commit, and the
# remaining changes go into a new child commit:
#
# ```text
# L                 L'
# |                 |
# K (split)   =>    K" (remaining)
# |                 |
# J                 K' (selected)
#                   |
#                   J
# ```
#
# With `--parallel/-p`, the two parts become sibling commits instead of
# parent and child:
#
# ```text
#                   L'
# L                / \
# |               K'  |  (selected)
# K (split)  =>   |   K" (remaining)
# |                \ /
# J                 J
# ```
#
# With `-o`, `-A`, or `-B`, the selected changes are extracted into a new
# commit at the specified location, while the remaining changes stay in place:
#
# ```text
# M                 M'
# |                 |
# L                 L'
# |                 |
# K (split)   =>    K' (remaining, stays here)
# |                 |
# J                 J'
#                   |
#                   K" (selected, inserted before J with -B J)
# ```
#
# You will be asked to enter change descriptions for the split commits.
#
# Splitting an empty commit is not supported because the same effect can be
# achieved with `jj new`.
@usage r#'long_help #"""
Split a revision in two

Starts a [diff editor] on the changes in the revision. Edit the right side
of the diff until it has the content you want in the first commit. Once you
close the editor, your revision will be split into two commits.

[diff editor]:
    https://docs.jj-vcs.dev/latest/config/#editing-diffs

By default, the selected changes stay in the original commit, and the
remaining changes go into a new child commit:

```text
L                 L'
|                 |
K (split)   =>    K" (remaining)
|                 |
J                 K' (selected)
                  |
                  J
```

With `--parallel/-p`, the two parts become sibling commits instead of
parent and child:

```text
                  L'
L                / \
|               K'  |  (selected)
K (split)  =>   |   K" (remaining)
|                \ /
J                 J
```

With `-o`, `-A`, or `-B`, the selected changes are extracted into a new
commit at the specified location, while the remaining changes stay in place:

```text
M                 M'
|                 |
L                 L'
|                 |
K (split)   =>    K' (remaining, stays here)
|                 |
J                 J'
                  |
                  K" (selected, inserted before J with -B J)
```

You will be asked to enter change descriptions for the split commits.

Splitting an empty commit is not supported because the same effect can be
achieved with `jj new`.
"""#'#
@usage 'flag "-i --interactive" help="Interactively choose which parts to split" {
        long_help #"""
Interactively choose which parts to split

This is the default if no filesets are provided.
"""#
    }'
@usage 'flag --tool help="Specify diff editor to be used (implies --interactive)" {
        arg <NAME>
    }'
@usage 'flag "-r --revision" help="The revision to split" default=@ {
        arg <REVSET>
    }'
@usage r#'flag "-o -d --onto --destination" help="The revision(s) to rebase the selected changes onto (can be repeated to create a merge commit)" var=#true conflicts=--parallel {
        long_help #"""
The revision(s) to rebase the selected changes onto (can be repeated to create a merge commit)

Extracts the selected changes into a new commit based on the given revision(s). The remaining changes stay in the original commit's location.
"""#
        arg <REVSETS>… var=#true
    }'#
@usage r#'flag "-A --insert-after --after" help="The revision(s) to insert after (can be repeated to create a merge commit)" var=#true {
        long_help #"""
The revision(s) to insert after (can be repeated to create a merge commit)

Extracts the selected changes into a new commit inserted after the given revision(s). The remaining changes stay in the original commit's location.
"""#
        conflicts "--onto" "--parallel"
        arg <REVSETS>… var=#true
    }'#
@usage r#'flag "-B --insert-before --before" help="The revision(s) to insert before (can be repeated to create a merge commit)" var=#true {
        long_help #"""
The revision(s) to insert before (can be repeated to create a merge commit)

Extracts the selected changes into a new commit inserted before the given revision(s). The remaining changes stay in the original commit's location.
"""#
        conflicts "--onto" "--parallel"
        arg <REVSETS>… var=#true
    }'#
@usage r#'flag "-m --message" help="The change description to use for the selected changes (don't open editor)" var=#true {
        long_help #"""
The change description to use for the selected changes (don't open editor)

Sets the description for the revision containing the selected changes. The other revision will keep its original description, if any.
"""#
        arg <MESSAGE>… var=#true
    }'#
@usage 'flag --editor help="Open an editor to edit the change description(s)" {
        long_help #"""
Open an editor to edit the change description(s)

Forces an editor to open when using `--message` to allow the message to be edited afterward.
"""#
    }'
@usage 'flag "-p --parallel" help="Split the revision into two parallel revisions instead of a parent and child"'
@usage 'arg "[FILESETS]…" help="Files matching any of these filesets are put in the selected changes" required=#false var=#true var_min=1'
@usage 'complete filesets type=path'
export def "jj split" [
    ...filesets: path@"nusage complete",          # Files matching any of these filesets are put in the selected changes
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --interactive (-i),                           # Interactively choose which parts to split
    --tool: string,                               # Specify diff editor to be used (implies --interactive)
    --revision (-r): string,                      # The revision to split
    --onto (-o): list<string>,                    # The revision(s) to rebase the selected changes onto (can be repeated to create a merge commit)
    --insert-after (-A): list<string>,            # The revision(s) to insert after (can be repeated to create a merge commit)
    --insert-before (-B): list<string>,           # The revision(s) to insert before (can be repeated to create a merge commit)
    --message (-m): list<string>,                 # The change description to use for the selected changes (don't open editor)
    --editor,                                     # Open an editor to edit the change description(s)
    --parallel (-p),                              # Split the revision into two parallel revisions instead of a parent and child
]: nothing -> string {
    ^jj split ...(nusage argv [...$filesets] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --interactive: $interactive
        --tool: $tool
        --revision: $revision
        --onto: $onto
        --insert-after: $insert_after
        --insert-before: $insert_before
        --message: $message
        --editor: $editor
        --parallel: $parallel
    })
}

# Move changes from a revision into another revision
#
# Without any options, moves the changes from the working-copy revision to the parent revision.
#
# With the `-r` option, moves the changes from the specified revision to the parent revision. Fails if there are several parent revisions (i.e., the given revision is a merge).
#
# With the `--from` and/or `--into` options, moves changes from/to the given revisions. If either is left out, it defaults to the working-copy commit. For example, `jj squash --into @--` moves changes from the working-copy commit to the grandparent.
#
# If, after moving changes out, the source revision is empty compared to its parent(s), and `--keep-emptied` is not set, it will be abandoned. Without `--interactive` or paths, the source revision will always be empty.
#
# If the source was abandoned and both the source and destination had a non-empty description, you will be asked for the combined description. If either was empty, then the other one will be used.
#
# If a working-copy commit gets abandoned, it will be given a new, empty commit. This is true in general; it is not specific to this command.
#
# The name "squash" comes from the idea of combining (squashing) the changes from multiple revisions together.
#
# EXPERIMENTAL FEATURES
#
# An alternative squashing UI is available via the `-o`, `-A`, and `-B` options. Using any of these options creates a new commit. They can be used together with one or more `--from` options (if no `--from` is specified, `--from @` is assumed).
@usage 'long_help #"""
Move changes from a revision into another revision

Without any options, moves the changes from the working-copy revision to the parent revision.

With the `-r` option, moves the changes from the specified revision to the parent revision. Fails if there are several parent revisions (i.e., the given revision is a merge).

With the `--from` and/or `--into` options, moves changes from/to the given revisions. If either is left out, it defaults to the working-copy commit. For example, `jj squash --into @--` moves changes from the working-copy commit to the grandparent.

If, after moving changes out, the source revision is empty compared to its parent(s), and `--keep-emptied` is not set, it will be abandoned. Without `--interactive` or paths, the source revision will always be empty.

If the source was abandoned and both the source and destination had a non-empty description, you will be asked for the combined description. If either was empty, then the other one will be used.

If a working-copy commit gets abandoned, it will be given a new, empty commit. This is true in general; it is not specific to this command.

The name "squash" comes from the idea of combining (squashing) the changes from multiple revisions together.

EXPERIMENTAL FEATURES

An alternative squashing UI is available via the `-o`, `-A`, and `-B` options. Using any of these options creates a new commit. They can be used together with one or more `--from` options (if no `--from` is specified, `--from @` is assumed).
"""#'
@usage 'flag "-r --revision" help="Revision to squash into its parent (default: @). Incompatible with the experimental `-o`/`-A`/`-B` options" {
        arg <REVSET>
    }'
@usage 'flag "-f --from" help="Revision(s) to squash from (default: @)" var=#true conflicts=--revision {
        arg <REVSETS>… var=#true
    }'
@usage 'flag "-t --into --to" help="Revision to squash into (default: @)" conflicts=--revision {
        arg <REVSET>
    }'
@usage 'flag "-o -d --onto --destination" help="(Experimental) The revision(s) to use as parent for the new commit (can be repeated to create a merge commit)" var=#true {
        conflicts "--into" "--revision"
        arg <REVSETS>… var=#true
    }'
@usage 'flag "-A --insert-after --after" help="(Experimental) The revision(s) to insert the new commit after (can be repeated to create a merge commit)" var=#true {
        conflicts "--onto" "--into" "--revision"
        arg <REVSETS>… var=#true
    }'
@usage 'flag "-B --insert-before --before" help="(Experimental) The revision(s) to insert the new commit before (can be repeated to create a merge commit)" var=#true {
        conflicts "--onto" "--into" "--revision"
        arg <REVSETS>… var=#true
    }'
@usage r#'flag "-m --message" help="The description to use for squashed revision (don't open editor)" var=#true {
        arg <MESSAGE>… var=#true
    }'#
@usage 'flag "-u --use-destination-message" help="Use the description of the destination revision and discard the description(s) of the source revision(s)" conflicts=--message'
@usage 'flag --editor help="Open an editor to edit the change description" {
        long_help #"""
Open an editor to edit the change description

Forces an editor to open when using `--message` to allow the message to be edited afterwards.
"""#
    }'
@usage 'flag "-i --interactive" help="Interactively choose which parts to squash"'
@usage 'flag --tool help="Specify diff editor to be used (implies --interactive)" {
        arg <NAME>
    }'
@usage 'flag "-k --keep-emptied" help="The source revision will not be abandoned"'
@usage 'arg "[FILESETS]…" help="Move only changes to these paths (instead of all paths)" required=#false var=#true var_min=1'
@usage 'complete filesets type=path'
export def "jj squash" [
    ...filesets: path@"nusage complete",          # Move only changes to these paths (instead of all paths)
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --revision (-r): string,                      # Revision to squash into its parent (default: @). Incompatible with the experimental `-o`/`-A`/`-B` options
    --from (-f): list<string>,                    # Revision(s) to squash from (default: @)
    --into (-t): string,                          # Revision to squash into (default: @)
    --onto (-o): list<string>,                    # (Experimental) The revision(s) to use as parent for the new commit (can be repeated to create a merge commit)
    --insert-after (-A): list<string>,            # (Experimental) The revision(s) to insert the new commit after (can be repeated to create a merge commit)
    --insert-before (-B): list<string>,           # (Experimental) The revision(s) to insert the new commit before (can be repeated to create a merge commit)
    --message (-m): list<string>,                 # The description to use for squashed revision (don't open editor)
    --use-destination-message (-u),               # Use the description of the destination revision and discard the description(s) of the source revision(s)
    --editor,                                     # Open an editor to edit the change description
    --interactive (-i),                           # Interactively choose which parts to squash
    --tool: string,                               # Specify diff editor to be used (implies --interactive)
    --keep-emptied (-k),                          # The source revision will not be abandoned
]: nothing -> string {
    ^jj squash ...(nusage argv [...$filesets] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --revision: $revision
        --from: $from
        --into: $into
        --onto: $onto
        --insert-after: $insert_after
        --insert-before: $insert_before
        --message: $message
        --use-destination-message: $use_destination_message
        --editor: $editor
        --interactive: $interactive
        --tool: $tool
        --keep-emptied: $keep_emptied
    })
}

# Show high-level repo status [default alias: st]
#
# This includes:
#
# * The working copy commit and its parents, and a summary of the changes in the working copy (compared to the merged parents)
#
# * Conflicts in the working copy
#
# * [Conflicted bookmarks]
#
# Note: You can use `jj diff --summary -r <rev>` to see the changed files for a specific revision.
#
# [Conflicted bookmarks]: https://docs.jj-vcs.dev/latest/bookmarks/#conflicts
@usage 'long_help #"""
Show high-level repo status [default alias: st]

This includes:

* The working copy commit and its parents, and a summary of the changes in the working copy (compared to the merged parents)

* Conflicts in the working copy

* [Conflicted bookmarks]

Note: You can use `jj diff --summary -r <rev>` to see the changed files for a specific revision.

[Conflicted bookmarks]: https://docs.jj-vcs.dev/latest/bookmarks/#conflicts
"""#'
@usage 'arg "[FILESETS]…" help="Restrict the status display to these paths" required=#false var=#true var_min=1'
@usage 'complete filesets type=path'
export def "jj status" [
    ...filesets: path@"nusage complete",          # Restrict the status display to these paths
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj status ...(nusage argv [...$filesets] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Manage tags
export def "jj tag" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj tag ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Delete existing tags
#
# Revisions referred to by the deleted tags are not abandoned.
@usage 'alias d'
@usage 'long_help #"""
Delete existing tags

Revisions referred to by the deleted tags are not abandoned.
"""#'
@usage 'arg <NAMES>… help="Tag names to delete" help_long=#"""
Tag names to delete

By default, the specified pattern matches tag names with glob syntax. You can also use other [string pattern syntax].

[string pattern syntax]: https://docs.jj-vcs.dev/latest/revsets/#string-patterns
"""# var=#true var_min=1'
export def "jj tag delete" [
    ...names: string,                             # Tag names to delete
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj tag delete ...(nusage argv [...$names] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# List tags and their targets
#
# By default, a tracked remote tag will be included only if its target is different from the local tag. An untracked remote tag won't be listed. For a conflicted tag (both local and remote), old target revisions are preceded by a "-" and new target revisions are preceded by a "+".
#
# The `-r` flag combined with revset expressions can be used for filtering. For example:
#
# * `jj tag list -r 'REV::'` shows tags whose targets are descendants of REV (similar to `git tag --contains REV`).
#
# * `jj tag list -r '::REV'` shows tags whose targets are ancestors of REV (similar to `git tag --merged REV`).
@usage 'alias l'
@usage r#'long_help #"""
List tags and their targets

By default, a tracked remote tag will be included only if its target is different from the local tag. An untracked remote tag won't be listed. For a conflicted tag (both local and remote), old target revisions are preceded by a "-" and new target revisions are preceded by a "+".

The `-r` flag combined with revset expressions can be used for filtering. For example:

* `jj tag list -r 'REV::'` shows tags whose targets are descendants of REV (similar to `git tag --contains REV`).

* `jj tag list -r '::REV'` shows tags whose targets are ancestors of REV (similar to `git tag --merged REV`).
"""#'#
@usage 'flag "-a --all-remotes" help="Show all tracked and untracked remote tags including the ones whose targets are synchronized with the local tags" {
            alias "--all" hide=#true
        }'
@usage 'flag --remote help="Show all tracked and untracked remote tags belonging to this remote" var=#true conflicts=--all-remotes {
            long_help #"""
Show all tracked and untracked remote tags belonging to this remote

Can be combined with `--tracked` or `--conflicted` to filter the tags shown (can be repeated.)

By default, the specified pattern matches remote names with glob syntax. You can also use other [string pattern syntax].

[string pattern syntax]: https://docs.jj-vcs.dev/latest/revsets/#string-patterns
"""#
            arg <REMOTE>… var=#true
        }'
@usage 'flag "-t --tracked" help="Show tracked remote tags only" conflicts=--all-remotes {
            long_help #"""
Show tracked remote tags only

This omits local Git-tracking tags by default.
"""#
        }'
@usage 'flag "-c --conflicted" help="Show conflicted tags only" conflicts=--all-remotes'
@usage r#'flag "-r --revision" help="Show tags whose local targets are in the given revisions" var=#true {
            alias "--revisions" hide=#true
            long_help #"""
Show tags whose local targets are in the given revisions

Note that `-r deleted_tag` will not work since `deleted_tag` wouldn't have a local target.
"""#
            arg <REVSETS>… var=#true
        }'#
@usage 'flag "-T --template" help="Render each tag using the given template" {
            long_help #"""
Render each tag using the given template

All 0-argument methods of the [`CommitRef` type][CommitRef] are available as keywords in the template expression. See [`jj help -k templates`][templates] for more information.

The default template can be set by the `templates.tag_list` setting.

[CommitRef]: https://docs.jj-vcs.dev/latest/templates/#commitref-type

[templates]: https://docs.jj-vcs.dev/latest/templates/
"""#
            arg <TEMPLATE>
        }'
@usage 'flag --sort help="Sort tags based on the given key (or multiple keys)" var=#true {
            long_help #"""
Sort tags based on the given key (or multiple keys)

Suffix the key with `-` to sort in descending order of the value (e.g. `--sort name-`). Note that when using multiple keys, the first key is the most significant.

This defaults to the `ui.tag-list-sort-keys` setting.
"""#
            arg <SORT_KEY>… var=#true delimiter=, {
                choices name name- author-name author-name- author-email author-email- author-date author-date- committer-name committer-name- committer-email committer-email- committer-date committer-date-
            }
        }'
@usage 'arg "[NAMES]…" help="Show tags whose local name matches" help_long=#"""
Show tags whose local name matches

By default, the specified pattern matches tag names with glob syntax. You can also use other [string pattern syntax].

[string pattern syntax]: https://docs.jj-vcs.dev/latest/revsets/#string-patterns
"""# required=#false var=#true var_min=1'
@usage 'output "json" framing="jsonl" { schema "{\n  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",\n  \"title\": \"A bookmark or a tag, one line of `jj bookmark list` or `jj tag list`\",\n  \"type\": \"object\",\n  \"required\": [\n    \"name\",\n    \"target\"\n  ],\n  \"additionalProperties\": false,\n  \"properties\": {\n    \"name\": {\n      \"type\": \"string\"\n    },\n    \"remote\": {\n      \"type\": \"string\"\n    },\n    \"target\": {\n      \"$ref\": \"#/$defs/target\"\n    },\n    \"tracking_target\": {\n      \"$ref\": \"#/$defs/target\"\n    }\n  },\n  \"$defs\": {\n    \"target\": {\n      \"type\": \"array\",\n      \"minItems\": 1,\n      \"items\": {\n        \"anyOf\": [\n          {\n            \"type\": \"string\",\n            \"pattern\": \"^[0-9a-f]+$\"\n          },\n          {\n            \"type\": \"null\"\n          }\n        ]\n      }\n    }\n  }\n}\n" }'
export def "jj tag list" [
    ...names: string,                                                                                                                                                                                               # Show tags whose local name matches
    --repository (-R): path@"nusage complete",                                                                                                                                                                      # Path to repository to operate on
    --ignore-working-copy,                                                                                                                                                                                          # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                                                                                                                                                                                       # Run the command as usual but don't integrate any operations
    --ignore-immutable,                                                                                                                                                                                             # Allow rewriting immutable commits
    --at-operation: string,                                                                                                                                                                                         # Operation to load the repo at
    --debug,                                                                                                                                                                                                        # Enable debug logging
    --color: string@[always never debug auto],                                                                                                                                                                      # When to colorize output
    --quiet,                                                                                                                                                                                                        # Silence non-primary command output
    --no-pager,                                                                                                                                                                                                     # Disable the pager
    --config: list<string>,                                                                                                                                                                                         # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",                                                                                                                                                                    # Additional configuration files (can be repeated)
    --all-remotes (-a),                                                                                                                                                                                             # Show all tracked and untracked remote tags including the ones whose targets are synchronized with the local tags
    --remote: list<string>,                                                                                                                                                                                         # Show all tracked and untracked remote tags belonging to this remote
    --tracked (-t),                                                                                                                                                                                                 # Show tracked remote tags only
    --conflicted (-c),                                                                                                                                                                                              # Show conflicted tags only
    --revision (-r): list<string>,                                                                                                                                                                                  # Show tags whose local targets are in the given revisions
    --sort: list<string>@[name name- author-name author-name- author-email author-email- author-date author-date- committer-name committer-name- committer-email committer-email- committer-date committer-date-],  # Sort tags based on the given key (or multiple keys)
]: nothing -> table<name: string, remote: oneof<string, nothing>, target: list<oneof<string, nothing>>, tracking_target: oneof<list<oneof<string, nothing>>, nothing>> {
    let text = ^jj tag list --template "json(self) ++ \"\\n\"" ...(nusage argv [...$names] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --all-remotes: $all_remotes
        --remote: $remote
        --tracked: $tracked
        --conflicted: $conflicted
        --revision: $revision
        --sort: $sort
    })
    nusage decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"title\":\"A bookmark or a tag, one line of `jj bookmark list` or `jj tag list`\",\"type\":\"object\",\"required\":[\"name\",\"target\"],\"additionalProperties\":false,\"properties\":{\"name\":{\"type\":\"string\"},\"remote\":{\"type\":\"string\"},\"target\":{\"$ref\":\"#/$defs/target\"},\"tracking_target\":{\"$ref\":\"#/$defs/target\"}},\"$defs\":{\"target\":{\"type\":\"array\",\"minItems\":1,\"items\":{\"anyOf\":[{\"type\":\"string\",\"pattern\":\"^[0-9a-f]+$\"},{\"type\":\"null\"}]}}}}" { from json --objects | default null remote | default null tracking_target } --lines
}

# Create or update tags
@usage 'alias s'
@usage 'flag "-r --revision --to" help="Target revision to point to" default=@ {
            arg <REVSET>
        }'
@usage 'flag --allow-move help="Allow moving existing tags"'
@usage 'arg <NAMES>… help="Tag names to create or update" var=#true var_min=1'
export def "jj tag set" [
    ...names: string,                             # Tag names to create or update
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --revision (-r): string,                      # Target revision to point to
    --allow-move,                                 # Allow moving existing tags
]: nothing -> string {
    ^jj tag set ...(nusage argv [...$names] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --revision: $revision
        --allow-move: $allow_move
    })
}

# Start tracking given remote tags
#
# A tracked remote tag will be imported as a local tag of the same name. Changes to it will propagate to the existing local tag on future pulls.
@usage 'long_help #"""
Start tracking given remote tags

A tracked remote tag will be imported as a local tag of the same name. Changes to it will propagate to the existing local tag on future pulls.
"""#'
@usage 'flag --remote help="Remote names to track" var=#true {
            long_help #"""
Remote names to track

By default, the specified pattern matches remote names with glob syntax. You can also use other [string pattern syntax].

If no remote names are given, all remote tags matching the tag names will be tracked.

[string pattern syntax]: https://docs.jj-vcs.dev/latest/revsets/#string-patterns
"""#
            arg <REMOTE>… var=#true
        }'
@usage 'arg "<TAG[@REMOTE]>…" help="Tag name patterns or remote tag symbols to track" help_long=#"""
Tag name patterns or remote tag symbols to track

`TAG` matches tag names using glob syntax by default. You can also use other [string pattern syntax].

`TAG@REMOTE` resolves to a remote tag exactly.

[string pattern syntax]: https://docs.jj-vcs.dev/latest/revsets/#string-patterns
"""# var=#true var_min=1'
export def "jj tag track" [
    ...tag_remote: string,                        # Tag name patterns or remote tag symbols to track
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --remote: list<string>,                       # Remote names to track
]: nothing -> string {
    ^jj tag track ...(nusage argv [...$tag_remote] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --remote: $remote
    })
}

# Stop tracking given remote tags
#
# An untracked remote tag is just a pointer to the last-fetched remote tag. It won't be imported as a local tag on future pulls.
@usage r#'long_help #"""
Stop tracking given remote tags

An untracked remote tag is just a pointer to the last-fetched remote tag. It won't be imported as a local tag on future pulls.
"""#'#
@usage 'flag --remote help="Remote names to untrack" var=#true {
            long_help #"""
Remote names to untrack

By default, the specified pattern matches remote names with glob syntax. You can also use other [string pattern syntax].

If no remote names are given, all remote tags matching the tag names will be untracked.

[string pattern syntax]: https://docs.jj-vcs.dev/latest/revsets/#string-patterns
"""#
            arg <REMOTE>… var=#true
        }'
@usage 'arg "<TAG[@REMOTE]>…" help="Tag name patterns or remote tag symbols to untrack" help_long=#"""
Tag name patterns or remote tag symbols to untrack

`TAG` matches tag names using glob syntax by default. You can also use other [string pattern syntax].

`TAG@REMOTE` resolves to a remote tag exactly.

[string pattern syntax]: https://docs.jj-vcs.dev/latest/revsets/#string-patterns
"""# var=#true var_min=1'
export def "jj tag untrack" [
    ...tag_remote: string,                        # Tag name patterns or remote tag symbols to untrack
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --remote: list<string>,                       # Remote names to untrack
]: nothing -> string {
    ^jj tag untrack ...(nusage argv [...$tag_remote] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --remote: $remote
    })
}

# Undo the last operation
#
# If used once after a normal (non-`undo`) operation, this will undo that last operation by restoring its parent. If `jj undo` is used repeatedly, it will restore increasingly older operations, going further back into the past.
#
# There is also a complementary `jj redo` command that would instead move in the direction of the future after one or more `jj undo`s.
#
# Use `jj op log` to visualize the log of past operations, including a detailed description of any past undo/redo operations. See also `jj op restore` to explicitly restore an older operation by its id (available in the operation log).
#
# By default, `jj undo` refuses to undo an operation that was performed in another workspace, since that is usually not what you meant to undo. Pass `--allow-cross-workspace` to undo it anyway, or use `jj op revert` to revert a specific operation.
@usage 'long_help #"""
Undo the last operation

If used once after a normal (non-`undo`) operation, this will undo that last operation by restoring its parent. If `jj undo` is used repeatedly, it will restore increasingly older operations, going further back into the past.

There is also a complementary `jj redo` command that would instead move in the direction of the future after one or more `jj undo`s.

Use `jj op log` to visualize the log of past operations, including a detailed description of any past undo/redo operations. See also `jj op restore` to explicitly restore an older operation by its id (available in the operation log).

By default, `jj undo` refuses to undo an operation that was performed in another workspace, since that is usually not what you meant to undo. Pass `--allow-cross-workspace` to undo it anyway, or use `jj op revert` to revert a specific operation.
"""#'
@usage 'flag --allow-cross-workspace help="Allow undoing an operation that was performed in another workspace"'
export def "jj undo" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --allow-cross-workspace,                      # Allow undoing an operation that was performed in another workspace
]: nothing -> string {
    ^jj undo ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --allow-cross-workspace: $allow_cross_workspace
    })
}

# Drop a cryptographic signature
#
# See also [commit signing] docs.
#
# [commit signing]: https://docs.jj-vcs.dev/latest/config/#commit-signing
@usage 'long_help #"""
Drop a cryptographic signature

See also [commit signing] docs.

[commit signing]: https://docs.jj-vcs.dev/latest/config/#commit-signing
"""#'
@usage 'flag "-r --revision" help="What revision(s) to unsign" var=#true {
        alias "--revisions" hide=#true
        arg <REVSETS>… var=#true
    }'
export def "jj unsign" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --revision (-r): list<string>,                # What revision(s) to unsign
]: nothing -> string {
    ^jj unsign ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --revision: $revision
    })
}

# Infrequently used commands such as for generating shell completions
export def "jj util" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj util ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Commands relating to the backend used in the current repo
export def "jj util backend" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj util backend ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Print the name of the backend used in the current repo
export def "jj util backend name" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj util backend name ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Print a command-line-completion script
#
# Apply it by running one of these:
#
# - Bash: `source <(jj util completion bash)`
# - Fish: `jj util completion fish | source`
# - Nushell:
#     ```nu
#     jj util completion nushell | save -f "completions-jj.nu"
#     use "completions-jj.nu" *  # Or `source "completions-jj.nu"`
#     ```
# - Zsh:
#     ```shell
#     autoload -U compinit
#     compinit
#     source <(jj util completion zsh)
#     ```
#
# See the docs on [command-line completion] for more details.
#
# [command-line completion]:
#    https://docs.jj-vcs.dev/latest/install-and-setup/#command-line-completion
@usage 'long_help #"""
Print a command-line-completion script

Apply it by running one of these:

- Bash: `source <(jj util completion bash)`
- Fish: `jj util completion fish | source`
- Nushell:
    ```nu
    jj util completion nushell | save -f "completions-jj.nu"
    use "completions-jj.nu" *  # Or `source "completions-jj.nu"`
    ```
- Zsh:
    ```shell
    autoload -U compinit
    compinit
    source <(jj util completion zsh)
    ```

See the docs on [command-line completion] for more details.

[command-line completion]:
   https://docs.jj-vcs.dev/latest/install-and-setup/#command-line-completion
"""#'
@usage 'arg <SHELL> {
            choices bash elvish fish nushell power-shell zsh
        }'
export def "jj util completion" [
    shell: string@[bash elvish fish nushell power-shell zsh],
    --repository (-R): path@"nusage complete",                 # Path to repository to operate on
    --ignore-working-copy,                                     # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                                  # Run the command as usual but don't integrate any operations
    --ignore-immutable,                                        # Allow rewriting immutable commits
    --at-operation: string,                                    # Operation to load the repo at
    --debug,                                                   # Enable debug logging
    --color: string@[always never debug auto],                 # When to colorize output
    --quiet,                                                   # Silence non-primary command output
    --no-pager,                                                # Disable the pager
    --config: list<string>,                                    # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",               # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj util completion ...(nusage argv [$shell] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Print the JSON schema for the jj TOML config format
export def "jj util config-schema" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj util config-schema ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Compare two files on disk
@usage 'flag --git help="Show a Git-format diff" help_heading="Diff Formatting Options" display_order=4'
@usage 'flag --color-words help="Show a word-level diff with changes indicated only by color" help_heading="Diff Formatting Options" display_order=5'
@usage 'flag --tool help="Generate diff by external command" help_heading="Diff Formatting Options" display_order=6 {
            long_help #"""
Generate diff by external command

A builtin format can also be specified as `:<name>`. For example, `--tool=:git` is equivalent to `--git`.
"""#
            arg <TOOL>
        }'
@usage 'flag --context help="Number of lines of context to show" help_heading="Diff Formatting Options" display_order=7 {
            arg <CONTEXT>
        }'
@usage 'flag "-s --summary" help="For each path, show only whether it was modified, added, or deleted" hide=#true help_heading="Diff Formatting Options" display_order=0'
@usage 'flag --stat help="Show a histogram of the changes" hide=#true help_heading="Diff Formatting Options" display_order=1'
@usage r#'flag --types help="For each path, show only its type before and after" hide=#true help_heading="Diff Formatting Options" display_order=2 {
            long_help #"""
For each path, show only its type before and after

The diff is shown as two letters. The first letter indicates the type before and the second letter indicates the type after. '-' indicates that the path was not present, 'F' represents a regular file, `L' represents a symlink, 'C' represents a conflict, and 'G' represents a Git submodule.
"""#
        }'#
@usage r#'flag --name-only help="For each path, show only its path" hide=#true help_heading="Diff Formatting Options" display_order=3 {
            long_help #"""
For each path, show only its path

Typically useful for shell commands like: `jj diff -r @- --name-only | xargs perl -pi -e's/OLD/NEW/g`
"""#
        }'#
@usage 'flag "-w --ignore-all-space" help="Ignore whitespace when comparing lines" help_heading="Diff Formatting Options" display_order=8'
@usage 'flag "-b --ignore-space-change" help="Ignore changes in amount of whitespace when comparing lines" conflicts=--ignore-all-space help_heading="Diff Formatting Options" display_order=9'
@usage 'arg <PATH1> help="First path to compare"'
@usage 'arg <PATH2> help="Second path to compare"'
@usage 'group short-format "--summary" "--stat" "--types" "--name-only"'
@usage 'group long-format "--git" "--color-words"'
@usage 'complete path1 type=path'
@usage 'complete path2 type=path'
export def "jj util diff" [
    path1: path@"nusage complete",                # First path to compare
    path2: path@"nusage complete",                # Second path to compare
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --git,                                        # Show a Git-format diff
    --color-words,                                # Show a word-level diff with changes indicated only by color
    --tool: string,                               # Generate diff by external command
    --context: string,                            # Number of lines of context to show
    --ignore-all-space (-w),                      # Ignore whitespace when comparing lines
    --ignore-space-change (-b),                   # Ignore changes in amount of whitespace when comparing lines
]: nothing -> string {
    ^jj util diff ...(nusage argv [$path1 $path2] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --git: $git
        --color-words: $color_words
        --tool: $tool
        --context: $context
        --ignore-all-space: $ignore_all_space
        --ignore-space-change: $ignore_space_change
    })
}

# Execute an external command via jj
#
# This command will have access to the environment variable JJ_WORKSPACE_ROOT.
#
# This is useful for arbitrary aliases.
#
# !! WARNING !!
#
# The following technique just provides a convenient syntax for running
# arbitrary code on your system. Using it irresponsibly may cause damage
# ranging from breaking the behavior of `jj undo` to wiping your file system.
# Exercise the same amount of caution while writing these aliases as you would
# when typing commands into the terminal!
#
# This feature may be removed or replaced by an embedded scripting language in
# the future.
#
# Let's assume you have a script called "my-jj-script" in your $PATH and you
# would like to execute it as "jj my-script". You would add the following line
# to your configuration file to achieve that:
#
# ```toml
# [aliases]
# my-script = ["util", "exec", "--", "my-jj-script"]
# #                            ^^^^
# # This makes sure that flags are passed to your script instead of parsed by jj.
# ```
#
# If you don't want to manage your script as a separate file, you can even
# inline it into your config file:
#
# ```toml
# [aliases]
# my-inline-script = ["util", "exec", "--", "bash", "-c", """
# set -euo pipefail
# echo "Look Ma, everything in one file!"
# echo "args: $@"
# """, ""]
# #    ^^
# # This last empty string will become "$0" in bash, so your actual arguments
# # are all included in "$@" and start at "$1" as expected.
# ```
#
# > Note: Shebangs (e.g. `#!/usr/bin/env`) aren't necessary since you're
# > already explicitly passing your script into the right shell.
@usage r#'long_help #"""
Execute an external command via jj

This command will have access to the environment variable JJ_WORKSPACE_ROOT.

This is useful for arbitrary aliases.

!! WARNING !!

The following technique just provides a convenient syntax for running
arbitrary code on your system. Using it irresponsibly may cause damage
ranging from breaking the behavior of `jj undo` to wiping your file system.
Exercise the same amount of caution while writing these aliases as you would
when typing commands into the terminal!

This feature may be removed or replaced by an embedded scripting language in
the future.

Let's assume you have a script called "my-jj-script" in your $PATH and you
would like to execute it as "jj my-script". You would add the following line
to your configuration file to achieve that:

```toml
[aliases]
my-script = ["util", "exec", "--", "my-jj-script"]
#                            ^^^^
# This makes sure that flags are passed to your script instead of parsed by jj.
```

If you don't want to manage your script as a separate file, you can even
inline it into your config file:

```toml
[aliases]
my-inline-script = ["util", "exec", "--", "bash", "-c", """
set -euo pipefail
echo "Look Ma, everything in one file!"
echo "args: $@"
""", ""]
#    ^^
# This last empty string will become "$0" in bash, so your actual arguments
# are all included in "$@" and start at "$1" as expected.
```

> Note: Shebangs (e.g. `#!/usr/bin/env`) aren't necessary since you're
> already explicitly passing your script into the right shell.
"""#'#
@usage 'arg <COMMAND> help="External command to execute"'
@usage 'arg "[ARGS]…" help="Arguments to pass to the external command" required=#false var=#true var_min=1'
@usage 'complete args type=path'
export def "jj util exec" [
    command: string,                              # External command to execute
    ...args: path@"nusage complete",              # Arguments to pass to the external command
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj util exec ...(nusage argv [$command ...$args] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Run backend-dependent garbage collection
#
# To garbage-collect old operations and the commits/objects referenced by them, run `jj op abandon ..<some old operation>` before `jj util gc`.
@usage 'long_help #"""
Run backend-dependent garbage collection.

To garbage-collect old operations and the commits/objects referenced by them, run `jj op abandon ..<some old operation>` before `jj util gc`.
"""#'
@usage 'flag --expire help="Time threshold" {
            long_help #"""
Time threshold

By default, only obsolete objects and operations older than 2 weeks are pruned.

Only the string "now" can be passed to this parameter. Support for arbitrary absolute and relative timestamps will come in a subsequent release.
"""#
            arg <EXPIRE>
        }'
export def "jj util gc" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --expire: string,                             # Time threshold
]: nothing -> string {
    ^jj util gc ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --expire: $expire
    })
}

# Install Jujutsu's manpages to the provided path
@usage 'arg <PATH> help="The path where manpages will installed. An example path might be `/usr/share/man`. The provided path will be appended with `man1`, etc., as appropriate"'
@usage 'complete path type=path'
export def "jj util install-man-pages" [
    path: path@"nusage complete",                 # The path where manpages will installed. An example path might be `/usr/share/man`. The provided path will be appended with `man1`, etc., as appropriate
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj util install-man-pages ...(nusage argv [$path] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Print the CLI help for all subcommands in Markdown
export def "jj util markdown-help" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj util markdown-help ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Snapshot the working copy if needed
#
# Snapshots the working copy and updates the working-copy commit if the
# working copy has changed since the last snapshot. Since almost every command
# snapshots the working copy, there is very little reason to run this command
# as a human; it is mostly meant for scripts.
#
# If you want to see the ID of the current operation after this command, run
# `jj operation log --limit 1`. However, since that command also snapshots the
# working copy, there would be no need to run `jj util snapshot` first.
#
# ### Example of programmatic snapshotting
#
# Consider the following:
#
# ```bash
# $ echo content > new-file.txt
# # At this point, `jj` does not know about `new-file.txt`.
# $ ./my-script-that-runs-jj-commands
# # Since the script ran `jj` commands, the changes to `new-file.txt` have
# # been snapshotted in an operation, which you can see with:
# $ jj operation log --patch
# ```
#
# If `my-script-that-runs-jj-commands` has a "sandwich" of `jj util snapshot`
# at the beginning and end of the script, then the operation that captures
# `new-file.txt` will be distinct from the operations created by the `jj`
# commands in that script. In addition, the `jj operation log --patch` that
# you ran on the command-line after the script would also have its own
# operation if needed. However, without `jj util snapshot`, these operations
# will be mixed together in the operation log. If this is important to you,
# then `jj util snapshot` is useful here to explicitly trigger a snapshot.
#
# ### Checking if the operation ID changed
#
# If you want to compare "before and after" operation IDs, it may be better to
# use `jj operation log --no-graph --limit 1 -T id` to query for operation
# information, which you can store in a variable in a script. You can then
# compare these values as needed to figure out if anything changed during a
# `jj` command, such as:
#
# ```bash
# start_op_id="$(jj op log -G -n 1 -T id)"
# jj git fetch || exit
# fetch_op_id="$(jj op log -G -n 1 -T id)"
# if [[ "${start_op_id}" == "${fetch_op_id}" ]]; then
#   # Nothing was fetched.
#   exit 0
# fi
# jj rebase -r 'mutable()' -o 'trunk()'
# rebase_op_id="$(jj op log -G -n 1 -T id)"
# if [[ "${fetch_op_id}" == "${rebase_op_id}" ]]; then
#   # Nothing was rebased.
#   exit 0
# fi
# echo "Fetched and rebased!"
# ```
#
# Note that `jj util snapshot` does not output an operation ID, so it is not
# suitable for checks such as these.
@usage r#'long_help #"""
Snapshot the working copy if needed

Snapshots the working copy and updates the working-copy commit if the
working copy has changed since the last snapshot. Since almost every command
snapshots the working copy, there is very little reason to run this command
as a human; it is mostly meant for scripts.

If you want to see the ID of the current operation after this command, run
`jj operation log --limit 1`. However, since that command also snapshots the
working copy, there would be no need to run `jj util snapshot` first.

### Example of programmatic snapshotting

Consider the following:

```bash
$ echo content > new-file.txt
# At this point, `jj` does not know about `new-file.txt`.
$ ./my-script-that-runs-jj-commands
# Since the script ran `jj` commands, the changes to `new-file.txt` have
# been snapshotted in an operation, which you can see with:
$ jj operation log --patch
```

If `my-script-that-runs-jj-commands` has a "sandwich" of `jj util snapshot`
at the beginning and end of the script, then the operation that captures
`new-file.txt` will be distinct from the operations created by the `jj`
commands in that script. In addition, the `jj operation log --patch` that
you ran on the command-line after the script would also have its own
operation if needed. However, without `jj util snapshot`, these operations
will be mixed together in the operation log. If this is important to you,
then `jj util snapshot` is useful here to explicitly trigger a snapshot.

### Checking if the operation ID changed

If you want to compare "before and after" operation IDs, it may be better to
use `jj operation log --no-graph --limit 1 -T id` to query for operation
information, which you can store in a variable in a script. You can then
compare these values as needed to figure out if anything changed during a
`jj` command, such as:

```bash
start_op_id="$(jj op log -G -n 1 -T id)"
jj git fetch || exit
fetch_op_id="$(jj op log -G -n 1 -T id)"
if [[ "${start_op_id}" == "${fetch_op_id}" ]]; then
  # Nothing was fetched.
  exit 0
fi
jj rebase -r 'mutable()' -o 'trunk()'
rebase_op_id="$(jj op log -G -n 1 -T id)"
if [[ "${fetch_op_id}" == "${rebase_op_id}" ]]; then
  # Nothing was rebased.
  exit 0
fi
echo "Fetched and rebased!"
```

Note that `jj util snapshot` does not output an operation ID, so it is not
suitable for checks such as these.
"""#'#
export def "jj util snapshot" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj util snapshot ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Display version information
export def "jj version" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj version ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Commands for working with workspaces
#
# Workspaces let you add additional working copies attached to the same repo. A common use case is so you can run a slow build or test in one workspace while you're continuing to write code in another workspace.
#
# Each workspace has its own working-copy commit. When you have more than one workspace attached to a repo, they are indicated by `<workspace name>@` in `jj log`.
#
# Each workspace also has own sparse patterns.
@usage r#'long_help #"""
Commands for working with workspaces

Workspaces let you add additional working copies attached to the same repo. A common use case is so you can run a slow build or test in one workspace while you're continuing to write code in another workspace.

Each workspace has its own working-copy commit. When you have more than one workspace attached to a repo, they are indicated by `<workspace name>@` in `jj log`.

Each workspace also has own sparse patterns.
"""#'#
export def "jj workspace" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj workspace ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Add a workspace
#
# By default, the new workspace inherits the sparse patterns of the current workspace. You can override this with the `--sparse-patterns` option.
@usage 'long_help #"""
Add a workspace

By default, the new workspace inherits the sparse patterns of the current workspace. You can override this with the `--sparse-patterns` option.
"""#'
@usage 'flag --name help="A name for the workspace" {
            long_help #"""
A name for the workspace

To override the default, which is the basename of the destination directory.
"""#
            arg <NAME>
        }'
@usage 'flag "-r --revision" help="A list of parent revisions for the working-copy commit of the newly created workspace. You may specify nothing, or any number of parents" var=#true {
            alias "--revisions" hide=#true
            long_help #"""
A list of parent revisions for the working-copy commit of the newly created workspace. You may specify nothing, or any number of parents.

If no revisions are specified, the new workspace will be created, and its working-copy commit will exist on top of the parent(s) of the working-copy commit in the current workspace, i.e. they will share the same parent(s).

If any revisions are specified, the new workspace will be created, and the new working-copy commit will be created with all these revisions as parents, i.e. the working-copy commit will exist as if you had run `jj new r1 r2 r3 ...`.
"""#
            arg <REVSETS>… var=#true
        }'
@usage 'flag "-m --message" help="The change description to use" var=#true {
            arg <MESSAGE>… var=#true
        }'
@usage 'flag --colocate help="Create a corresponding Git worktree for this workspace" conflicts=--no-colocate {
            long_help #"""
Create a corresponding Git worktree for this workspace

By default, a Git worktree is created when the current workspace is colocated and the [git.colocate config] is `true`.

[git.colocate config]: https://docs.jj-vcs.dev/latest/config/#default-colocation
"""#
        }'
@usage 'flag --no-colocate help="Do not create a Git worktree for this workspace" conflicts=--colocate'
@usage 'flag --sparse-patterns help="How to handle sparse patterns when creating a new workspace" default=copy {
            arg <SPARSE_PATTERNS> {
                choices {
                    choice copy help="Copy all sparse patterns from the current workspace"
                    choice full help="Include all files in the new workspace"
                    choice empty help="Clear all files from the workspace (it will be empty)"
                }
            }
        }'
@usage 'arg <DESTINATION> help="Where to create the new workspace"'
@usage 'complete destination type=dir'
export def "jj workspace add" [
    destination: path@"nusage complete",          # Where to create the new workspace
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --name: string,                               # A name for the workspace
    --revision (-r): list<string>,                # A list of parent revisions for the working-copy commit of the newly created workspace. You may specify nothing, or any number of parents
    --message (-m): list<string>,                 # The change description to use
    --colocate,                                   # Create a corresponding Git worktree for this workspace
    --no-colocate,                                # Do not create a Git worktree for this workspace
    --sparse-patterns: string@[copy full empty],  # How to handle sparse patterns when creating a new workspace
]: nothing -> string {
    ^jj workspace add ...(nusage argv [$destination] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --name: $name
        --revision: $revision
        --message: $message
        --colocate: $colocate
        --no-colocate: $no_colocate
        --sparse-patterns: $sparse_patterns
    })
}

# Stop tracking a workspace's working-copy commit in the repo
#
# The workspace will not be touched on disk. It can be deleted from disk before or after running this command.
@usage r#'long_help #"""
Stop tracking a workspace's working-copy commit in the repo

The workspace will not be touched on disk. It can be deleted from disk before or after running this command.
"""#'#
@usage 'arg "[WORKSPACES]…" help="Names of the workspaces to forget. By default, forgets only the current workspace" required=#false var=#true var_min=1'
export def "jj workspace forget" [
    ...workspaces: string,                        # Names of the workspaces to forget. By default, forgets only the current workspace
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj workspace forget ...(nusage argv [...$workspaces] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# List workspaces
@usage 'flag "-T --template" help="Render each workspace using the given template" {
            long_help #"""
Render each workspace using the given template

All 0-argument methods of the [`WorkspaceRef` type][WorkspaceRef] are available as keywords in the template expression. See [`jj help -k templates`][templates] for more information.

The default template can be set by the `templates.workspace_list` setting.

[WorkspaceRef]: https://docs.jj-vcs.dev/latest/templates/#workspaceref-type

[templates]: https://docs.jj-vcs.dev/latest/templates/
"""#
            arg <TEMPLATE>
        }'
@usage 'output "json" framing="jsonl" { schema "{\n  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",\n  \"title\": \"A workspace and its working-copy commit, one line of `jj workspace list`\",\n  \"type\": \"object\",\n  \"required\": [\n    \"name\",\n    \"target\"\n  ],\n  \"additionalProperties\": false,\n  \"properties\": {\n    \"name\": {\n      \"type\": \"string\"\n    },\n    \"target\": {\n      \"$ref\": \"#/$defs/commit\"\n    }\n  },\n  \"$defs\": {\n    \"commit_id\": {\n      \"type\": \"string\",\n      \"pattern\": \"^[0-9a-f]+$\"\n    },\n    \"signature\": {\n      \"type\": \"object\",\n      \"required\": [\n        \"name\",\n        \"email\",\n        \"timestamp\"\n      ],\n      \"additionalProperties\": false,\n      \"properties\": {\n        \"name\": {\n          \"type\": \"string\"\n        },\n        \"email\": {\n          \"type\": \"string\"\n        },\n        \"timestamp\": {\n          \"type\": \"string\",\n          \"format\": \"date-time\"\n        }\n      }\n    },\n    \"commit\": {\n      \"type\": \"object\",\n      \"required\": [\n        \"commit_id\",\n        \"parents\",\n        \"change_id\",\n        \"description\",\n        \"author\",\n        \"committer\"\n      ],\n      \"additionalProperties\": false,\n      \"properties\": {\n        \"commit_id\": {\n          \"$ref\": \"#/$defs/commit_id\"\n        },\n        \"parents\": {\n          \"type\": \"array\",\n          \"items\": {\n            \"$ref\": \"#/$defs/commit_id\"\n          }\n        },\n        \"change_id\": {\n          \"type\": \"string\",\n          \"pattern\": \"^[k-z]+$\"\n        },\n        \"description\": {\n          \"type\": \"string\"\n        },\n        \"author\": {\n          \"$ref\": \"#/$defs/signature\"\n        },\n        \"committer\": {\n          \"$ref\": \"#/$defs/signature\"\n        }\n      }\n    }\n  }\n}\n" }'
export def "jj workspace list" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> table<name: string, target: record<commit_id: string, parents: list<string>, change_id: string, description: string, author: record<name: string, email: string, timestamp: datetime>, committer: record<name: string, email: string, timestamp: datetime>>> {
    let text = ^jj workspace list --template "json(self) ++ \"\\n\"" ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
    nusage decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"title\":\"A workspace and its working-copy commit, one line of `jj workspace list`\",\"type\":\"object\",\"required\":[\"name\",\"target\"],\"additionalProperties\":false,\"properties\":{\"name\":{\"type\":\"string\"},\"target\":{\"$ref\":\"#/$defs/commit\"}},\"$defs\":{\"commit_id\":{\"type\":\"string\",\"pattern\":\"^[0-9a-f]+$\"},\"signature\":{\"type\":\"object\",\"required\":[\"name\",\"email\",\"timestamp\"],\"additionalProperties\":false,\"properties\":{\"name\":{\"type\":\"string\"},\"email\":{\"type\":\"string\"},\"timestamp\":{\"type\":\"string\",\"format\":\"date-time\"}}},\"commit\":{\"type\":\"object\",\"required\":[\"commit_id\",\"parents\",\"change_id\",\"description\",\"author\",\"committer\"],\"additionalProperties\":false,\"properties\":{\"commit_id\":{\"$ref\":\"#/$defs/commit_id\"},\"parents\":{\"type\":\"array\",\"items\":{\"$ref\":\"#/$defs/commit_id\"}},\"change_id\":{\"type\":\"string\",\"pattern\":\"^[k-z]+$\"},\"description\":{\"type\":\"string\"},\"author\":{\"$ref\":\"#/$defs/signature\"},\"committer\":{\"$ref\":\"#/$defs/signature\"}}}}}" { from json --objects | into datetime target.author.timestamp | into datetime target.committer.timestamp } --lines
}

# Remove a workspace and its working-copy files from disk
#
# The workspace directory and its contents are removed from disk. The working-copy state is snapshotted into a commit before the workspace is removed. The main workspace cannot be removed.
@usage 'long_help #"""
Remove a workspace and its working-copy files from disk

The workspace directory and its contents are removed from disk. The working-copy state is snapshotted into a commit before the workspace is removed. The main workspace cannot be removed.
"""#'
@usage 'arg <WORKSPACES>… help="Names of the workspaces to remove" var=#true var_min=1'
export def "jj workspace remove" [
    ...workspaces: string,                        # Names of the workspaces to remove
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj workspace remove ...(nusage argv [...$workspaces] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Renames the current workspace
@usage 'arg <NEW_WORKSPACE_NAME> help="The name of the workspace to update to"'
export def "jj workspace rename" [
    new_workspace_name: string,                   # The name of the workspace to update to
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj workspace rename ...(nusage argv [$new_workspace_name] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}

# Show the workspace root directory
@usage 'flag --name help="Name of the workspace (defaults to current)" {
            arg <NAME>
        }'
export def "jj workspace root" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
    --name: string,                               # Name of the workspace (defaults to current)
]: nothing -> string {
    ^jj workspace root ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
        --name: $name
    })
}

# Update a workspace that has become stale
#
# See the [stale working copy documentation] for more information.
#
# [stale working copy documentation]: https://docs.jj-vcs.dev/latest/working-copy/#stale-working-copy
@usage 'long_help #"""
Update a workspace that has become stale

See the [stale working copy documentation] for more information.

[stale working copy documentation]: https://docs.jj-vcs.dev/latest/working-copy/#stale-working-copy
"""#'
export def "jj workspace update-stale" [
    --repository (-R): path@"nusage complete",    # Path to repository to operate on
    --ignore-working-copy,                        # Don't snapshot the working copy, and don't update it
    --no-integrate-operation,                     # Run the command as usual but don't integrate any operations
    --ignore-immutable,                           # Allow rewriting immutable commits
    --at-operation: string,                       # Operation to load the repo at
    --debug,                                      # Enable debug logging
    --color: string@[always never debug auto],    # When to colorize output
    --quiet,                                      # Silence non-primary command output
    --no-pager,                                   # Disable the pager
    --config: list<string>,                       # Additional configuration options (can be repeated)
    --config-file: list<path>@"nusage complete",  # Additional configuration files (can be repeated)
]: nothing -> string {
    ^jj workspace update-stale ...(nusage argv [] {
        --repository: $repository
        --ignore-working-copy: $ignore_working_copy
        --no-integrate-operation: $no_integrate_operation
        --ignore-immutable: $ignore_immutable
        --at-operation: $at_operation
        --debug: $debug
        --color: $color
        --quiet: $quiet
        --no-pager: $no_pager
        --config: $config
        --config-file: $config_file
    })
}
