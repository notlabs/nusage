#!/usr/bin/env nusage
#USAGE arg "[fixtures]..." help="Fixture directories; every directory under fixtures/ by default"
#USAGE flag "--update-signatures" help="Rewrite expected/signatures.nuon instead of comparing it"
# Verify the fixtures against the `nu` that runs this script.
#
# A script fixture's cases go through both entrypoints and must return the same value:
#   - shim:        `use expected/<bin>.nu; <bin> <words>`        (Nushell types the arguments)
#   - interpreter: `let usage = ($env.NUSAGE_ARGS | from nuon); $in | run <script>`
#                                                                  (the record is handed in as NUON)
#   - parse:       `nusage parse <script> -- <argv>`, for a single script, when
#                  target/debug/nusage is built: the record usage's parser yields
# A binary fixture (a `<bin>.usage.kdl`) has no scripts: a case's `invoke` runs the module
# against the fixture's `fake/<bin>`, which records the argv it received and prints what the
# case says, so argv building and decoding are checked; then completions and signatures.
# A case with `complete` asks the module for completions at a point of a line. Then the parsed
# signature and attributes of the root and every command a case names, as `scope commands`
# reports them, are compared with expected/signatures.nuon, and `nusage check` holds the
# module to the spec as usage reads it.
#
#
#   mise run //nusage:verify-fixtures                       # all fixtures
#   mise run //nusage:verify-fixtures fixtures/minimal      # one
#   mise run //nusage:verify-fixtures --update-signatures   # rewrite expected/signatures.nuon
#
# `NUSAGE_BIN` names the nusage to check; the build `//nusage:build` links into `.bin` by default.

# One row per check: shim, interpreter, run and (when present) completion per case, then
# signatures.
def verify-fixture [dir: path, update: bool] {
    let name = $dir | path basename
    let module = glob ($dir | path join expected '*.nu') | first
    let bin = $module | path parse | get stem
    # A binary module's root is `main` and its subcommands carry the binary's name: `use ... *`
    # names them all as the binary does. A script module is used by its name.
    let is_binary = ($dir | path join $"($bin).usage.kdl") | path exists
    let import = if $is_binary { $"use ($module | to nuon) *" } else { $"use ($module | to nuon)" }
    let cases = glob ($dir | path join cases '*.nuon') | sort
    let per_case = $cases | each {|file|
        let case = open $file
        let id = $file | path parse | get stem
        let rows = if $is_binary {
            if ($case.invoke? | is-not-empty) {
                [(row $name invoke $id (check-invoke $dir $import $case))]
            } else {
                []
            }
        } else {
            [
                (row $name shim $id (check-shim $import $bin $case))
                (row $name interpreter $id (check-interpreter $dir $bin $case))
                (row $name run $id (check-run $dir $bin $case))
            ] | append (
                if ($dir | path join script.nu | path exists) {
                    [(row $name parse $id (check-parse $dir $case))]
                } else {
                    []
                }
            )
        }
        if ($case.complete? | is-not-empty) {
            # A binary module's completer runs usage's, through the `usage` CLI.
            let outcome = if $is_binary and (which usage | is-empty) {
                skipped "the usage CLI is not on PATH"
            } else {
                check-complete $import $case.complete
            }
            $rows | append (row $name complete $id $outcome)
        } else {
            $rows
        }
    } | flatten
    let cmds = [
        []
    ] | append (
        $cases
        | each {|f| let c = open $f; $c.usage?.cmd? | default ($c.cmd? | default []) }
    ) | uniq
    $per_case | append ((row
        $name
        signatures
        ""
        (check-signatures $dir $import $bin $cmds $update)
    )) | append ((row $name conform "" (check-conform $dir $module $bin $is_binary)))
}

# `nusage check`: the module carries what the spec shows, as usage reads the spec, for
# every command, its positionals, flags, completers and description.
def check-conform [
    dir: path
    module: path
    bin: string
    is_binary: bool
] {
    if not ($env.NUSAGE_BIN | path exists) {
        return (skipped $"($env.NUSAGE_BIN) is not built")
    }
    let source = if $is_binary {
        $dir | path join $"($bin).usage.kdl"
    } else if ($dir | path join script.nu | path exists) {
        $dir | path join script.nu
    } else {
        $dir | path join $bin
    }
    let overlay = $dir | path join $"($bin).overlay.kdl"
    let overlays = if ($overlay | path exists) { [--overlay $overlay] } else { [] }
    let out = ^$env.NUSAGE_BIN check $source $module ...$overlays | complete
    {
        ok: ($out.exit_code == 0)
        detail: ($out.stderr | str trim)
    }
}

def row [
    fixture: string
    check: string
    case: string
    outcome: record
] {
    {
        fixture: $fixture
        check: $check
        case: $case
        ok: $outcome.ok
        skipped: ($outcome.skipped? | default false)
        detail: $outcome.detail
    }
}

# What the command must return: `output` when the script returns something other than its
# record (a provider), otherwise the record itself.
def expected-output [case: record] {
    $case.output? | default $case.usage
}

# The Nushell spelling of a case: `invoke` when argv has no direct Nushell form (repeated
# or counted flags), otherwise the argv words as written.
def words-of [case: record] {
    $case.invoke? | default ($case.argv | str join ' ')
}

def check-shim [import: string, bin: string, case: record] {
    let code = $"($import); ($bin) (words-of $case) | to nuon"
    run-nu $code {} | compare (expected-output $case)
}

def check-interpreter [dir: path, bin: string, case: record] {
    let script = script-for $dir $bin $case.usage.cmd
    let code = $"let usage = \($env.NUSAGE_ARGS | from nuon\); $in | run ($script | to nuon) | to nuon"
    run-nu $code {
        NUSAGE_ARGS: ($case.usage | to nuon)
    } | compare (expected-output $case)
}

# A binary call against the fixture's fake binary: the argv it recorded must be the case's
# `argv`, and what the call returns the case's `output`, when the case gives them; a case
# with `error` must fail instead, with a message containing it. The built `nusage` is on
# PATH, as a module holds a failed decode to its schema through it.
def check-invoke [dir: path, import: string, case: record] {
    let argv_file = mktemp
    let path = $env.PATH
    let path = if ($path | describe | str starts-with list) {
        $path | str join (char esep)
    } else {
        $path
    }
    let out = run-nu $"($import); ($case.invoke) | to nuon" {
        PATH: $"($dir | path join fake)(char esep)($env.NUSAGE_BIN | path dirname)(char esep)($path)"
        NUSAGE_FAKE_STDOUT: ($case.stdout? | default "")
        NUSAGE_FAKE_ARGV: $argv_file
    }
    let argv = open --raw $argv_file | lines
    rm $argv_file
    if ($case.error? | is-not-empty) {
        return (if $out.ok {
            {ok: false, detail: $"expected an error containing ($case.error | to nuon), got ($out.detail)"}
        } else if ($out.detail | str contains $case.error) {
            {ok: true, detail: ''}
        } else {
            {ok: false, detail: $"expected an error containing ($case.error | to nuon), got:\n($out.detail)"}
        })
    }
    if not $out.ok {
        return $out
    }
    if ($case.argv? | is-not-empty) and $argv != $case.argv {
        return {
            ok: false
            detail: $"expected argv (($case.argv | to nuon))\n     got (($argv | to nuon))"
        }
    }
    if ($case.output? | is-not-empty) or ($case | columns | 'output' in $in) {
        $out | compare $case.output
    } else {
        {ok: true, detail: ''}
    }
}

# The record the built `nusage` makes of the case's argv, as its shebang form would hand it
# to the script.
# A check the environment cannot run: its own outcome, a failure in CI, where every check
# has to run for a pass to mean anything.
def skipped [why: string] {
    {
        ok: (($env.CI? | default "") != "true")
        skipped: true
        detail: $"skipped: ($why)"
    }
}

# The interpreter entrypoint itself: `nusage <root script> ...argv` routes the call to the
# script of the command the words select and runs it with its `$usage`, so it prints the
# value the shim and the handoff return, as Nushell shows it; the same value rendered by
# the same Nushell is what it must print. `--help` prints the spec's help, and a call
# without arguments ends as `nusage parse` says: refused with exit code 2, or run.
def check-run [dir: path, bin: string, case: record] {
    if not ($env.NUSAGE_BIN | path exists) {
        return (skipped $"($env.NUSAGE_BIN) is not built")
    }
    let script = script-for $dir $bin []
    let ran = ^$env.NUSAGE_BIN $script ...$case.argv | complete
    if $ran.exit_code != 0 {
        return {
            ok: false
            detail: $"exit ($ran.exit_code): ($ran.stderr | str trim)"
        }
    }
    let shown = run-nu '$env.NUSAGE_EXPECTED | from nuon' {
        NUSAGE_EXPECTED: ((expected-output $case) | to nuon)
    }
    if ($ran.stdout | str trim) != $shown.detail {
        return {
            ok: false
            detail: $"printed:\n($ran.stdout | str trim)\nexpected:\n($shown.detail)"
        }
    }
    let help = ^$env.NUSAGE_BIN $script --help | complete
    if $help.exit_code != 0 or not ($help.stdout | str contains "Usage:") {
        return {
            ok: false
            detail: $"--help: exit ($help.exit_code): ($help.stdout)($help.stderr)"
        }
    }
    let parsed = ^$env.NUSAGE_BIN parse $script -- | complete
    let bare = ^$env.NUSAGE_BIN $script | complete
    if $parsed.exit_code not-in [0 2] or $bare.exit_code != $parsed.exit_code {
        return {
            ok: false
            detail: $"without arguments, parse exited ($parsed.exit_code) and the run ($bare.exit_code): ($bare.stderr | str trim)"
        }
    }
    {ok: true, detail: ""}
}

def check-parse [dir: path, case: record] {
    if not ($env.NUSAGE_BIN | path exists) {
        return (skipped $"($env.NUSAGE_BIN) is not built")
    }
    let script = $dir | path join script.nu
    let out = ^$env.NUSAGE_BIN parse $script -- ...$case.argv | complete
    if $out.exit_code != 0 {
        return {
            ok: false
            detail: ($out.stderr | str trim)
        }
    }
    {
        ok: true
        detail: ($out.stdout | str trim)
    } | compare $case.usage
}

def check-complete [import: string, complete: record] {
    let code = $"($import); ($complete.line | to nuon) | commandline complete | to nuon"
    run-nu $code {} | compare $complete.expect
}

# A single `script.nu`, or a `<bin>/` tree where `[db migrate]` is `db/migrate.nu` and a
# group or the root is its directory's `mod.nu`.
def script-for [dir: path, bin: string, cmd: list<string>] {
    let single = $dir | path join script.nu
    if ($single | path exists) {
        return $single
    }
    let base = [$dir $bin] | append $cmd | path join
    if ($base | path type) == dir {
        $base | path join mod.nu
    } else {
        $base + '.nu'
    }
}

def run-nu [code: string, env_vars: record] {
    let out = with-env $env_vars { ^$nu.current-exe -n -c $code } | complete
    if $out.exit_code != 0 {
        {
            ok: false
            detail: ($out.stderr | str trim)
        }
    } else {
        {
            ok: true
            detail: ($out.stdout | str trim)
        }
    }
}

def compare [expected] {
    let out = $in
    if not $out.ok {
        return $out
    }
    let got = try {
        $out.detail | from nuon
    } catch {
        return {
            ok: false
            detail: $"not nuon: ($out.detail)"
        }
    }
    if $got == $expected {
        {ok: true, detail: ''}
    } else {
        {
            ok: false
            detail: $"expected (($expected | to nuon))\n     got (($got | to nuon))"
        }
    }
}

# The parsed signature and attributes of each command, keyed by its full name.
def check-signatures [
    dir: path
    import: string
    bin: string
    cmds: list<any>
    update: bool
] {
    let names = $cmds | each {|cmd| [$bin] | append $cmd | str join ' ' }
    let code = $"($import); scope commands | where name in ($names | to nuon) | select name signatures attributes | to nuon --indent 2"
    let out = run-nu $code {}
    if not $out.ok {
        return $out
    }
    let live = $out.detail + "\n"
    let file = $dir | path join expected signatures.nuon
    if $update {
        $live | save --force $file
        return {
            ok: true
            detail: $"wrote ($file)"
        }
    }
    if not ($file | path exists) {
        return {
            ok: false
            detail: $"missing ($file); run with --update-signatures"
        }
    }
    if (open --raw $file) == $live {
        {ok: true, detail: ''}
    } else {
        {
            ok: false
            detail: $"signatures differ from ($file); diff it or run with --update-signatures"
        }
    }
}

const root = path self | path dirname
$env.NUSAGE_BIN = $env.NUSAGE_BIN? | default (
    $root
    | path dirname
    | path dirname
    | path join .bin nusage
)
let fixtures = if ($usage.args.fixtures | is-empty) {
    ls $root | where type == dir | get name
} else {
    $usage.args.fixtures | each { path expand }
}

let results = $fixtures | each {|dir| verify-fixture $dir $usage.flags.update_signatures } | flatten
print ($results | select fixture check case ok skipped | table --expand)
let failed = $results | where not ok
if ($failed | is-not-empty) {
    print --stderr ($failed | select fixture check case detail | table --expand)
    error make --unspanned {msg: $"($failed | length) of ($results | length) checks failed"}
}
let skipped = $results | where skipped
if ($skipped | is-not-empty) {
    print $"($skipped | length) of ($results | length) checks skipped: ($skipped | get detail | uniq | str join '; ')"
}
print $"all ($results | length) checks passed"
