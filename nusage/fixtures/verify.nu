#!/usr/bin/env nus
#USAGE arg "[fixtures]..." help="Fixture directories; every directory under fixtures/ by default"
#USAGE flag "--update-signatures" help="Rewrite expected/signatures.nuon instead of comparing it"
# Verify the fixtures against the `nu` that runs this script.
#
# A script fixture's cases go through both entrypoints and must return the same value:
#   - shim:        `use expected/<bin>.nu; <bin> <words>`        (Nushell types the arguments)
#   - interpreter: `let usage = ($env.NUS_ARGS | from nuon); $in | run <script>`
#                                                                  (the record is handed in as NUON,
#                  after what `nus prelude --run <script>` says precedes it: the shadows of
#                  the scripts it calls)
#   - parse:       `nus parse <script> -- <argv>`, for a single script, when
#                  target/debug/nusage is built: the record usage's parser yields
#   - prelude:     the record bound by the typed `let usage` that `nus prelude <script>`
#                  writes, which Nushell checks against the record as it runs
# A binary fixture (a `<bin>.usage.kdl`) has no scripts: a case's `invoke` runs the module
# against the fixture's `fake/<bin>`, which records the argv it received and prints what the
# case says, so argv building and decoding are checked; then completions and signatures.
# A case with `complete` asks the module for completions at a point of a line. Then the parsed
# signature and attributes of the root and every command a case names, as `scope commands`
# reports them, are compared with expected/signatures.nuon, and `nus check` holds the
# module to the spec as usage reads it.
#
#
#   mise run //nusage:verify-fixtures                       # all fixtures
#   mise run //nusage:verify-fixtures fixtures/minimal      # one
#   mise run //nusage:verify-fixtures --update-signatures   # rewrite expected/signatures.nuon
#
# `NUS_BIN` names the nus to check, and `NUS_PLUGIN` its plugin; the build `//nusage:build`
# copies both into `.bin` by default.

# One row per check: shim, interpreter, run and (when present) completion per case, then
# signatures.
def verify-fixture [dir: path, update: bool] {
    if (($dir | path join shapes | path type) == dir) {
        return (verify-slice $dir)
    }
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
                (row $name shim-plugin $id (check-shim-plugin $dir $bin $case))
                (row $name interpreter $id (check-interpreter $dir $bin $case))
                (row $name executor $id (check-executor $dir $bin $case))
                (row $name run $id (check-run $dir $bin $case))
                (row $name prelude $id (check-prelude $dir $bin $case))
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

# A slice fixture, told by its `shapes/`: the slices of `script.nu` written by hand, for the
# slicer to reproduce byte for byte. `shapes/<shape>.nuon` is a static projection of
# `$usage`; `expected/<shape>/` holds the residual and the manifest it gives, or
# `findings.nuon` where the slice is refused; `edits/<name>/` holds a changed source, with
# `expect.nuon` saying per shape whether the slice is `kept`, byte for byte, or `changed`,
# with an `expected/<shape>/` of its own. Each is held to its schema and to the layout; the
# slicer's own rows are pending until `nus slice` exists. The script's cases run as a
# script's, through the interpreter and the entrypoint: the script is a script before it is
# a slice, and the residual must give what it gives.
def verify-slice [dir: path] {
    let name = $dir | path basename
    const schemas = path self | path dirname | path dirname | path join schemas
    let shapes = glob ($dir | path join shapes '*.nuon') | sort | each {|f| $f | path parse | get stem }
    let per_shape = $shapes | each {|shape|
        let expected = $dir | path join expected $shape
        [
            (row $name shape $shape (validate-nuon ($dir | path join shapes $"($shape).nuon") ($schemas | path join slice-shape.schema.json)))
            (row $name expected $shape (check-slice-expected $expected $schemas))
            (row $name slice $shape (check-slice ($dir | path join script.nu) ($dir | path join shapes $"($shape).nuon") $expected))
        ]
    } | flatten
    let per_edit = glob ($dir | path join edits '*') | sort | each {|edit|
        let id = $edit | path basename
        let expect = open ($edit | path join expect.nuon)
        $expect | columns | each {|shape|
            let own = $edit | path join expected $shape
            let outcome = if $shape not-in $shapes {
                {ok: false, detail: $"no shape ($shape) under shapes/"}
            } else if ($expect | get $shape) == kept {
                if ($own | path exists) {
                    {ok: false, detail: $"($shape) is kept, so ($own) must not exist"}
                } else {
                    check-slice ($edit | path join script.nu) ($dir | path join shapes $"($shape).nuon") ($dir | path join expected $shape)
                }
            } else if ($expect | get $shape) == changed {
                let laid_out = check-slice-expected $own $schemas
                if not $laid_out.ok {
                    $laid_out
                } else if (same-slice $own ($dir | path join expected $shape)) {
                    {ok: false, detail: $"($shape) is changed, but ($own) is what the unedited source gives"}
                } else {
                    check-slice ($edit | path join script.nu) ($dir | path join shapes $"($shape).nuon") $own
                }
            } else {
                {ok: false, detail: $"($id): ($shape) is kept or changed, not ($expect | get $shape | to nuon)"}
            }
            row $name edit $"($id)/($shape)" $outcome
        }
    } | flatten
    # The cases run from a copy outside the repository: a task of mise's beside the script
    # is found from its own directory there, not from this repository's root.
    let scratch = mktemp --directory
    for entry in (ls --all $dir) {
        cp --recursive $entry.name $scratch
    }
    let per_case = glob ($dir | path join cases '*.nuon') | sort | each {|file|
        let case = open $file
        let id = $file | path parse | get stem
        [
            (row $name interpreter $id (check-interpreter $scratch script $case))
            (row $name run $id (check-run $scratch script $case))
        ]
    } | flatten
    rm --recursive $scratch
    $per_shape | append $per_edit | append $per_case
}

# A NUON file held to a schema through `nus validate`.
def validate-nuon [file: path, schema: path] {
    if not ($env.NUS_BIN | path exists) {
        return (skipped $"($env.NUS_BIN) is not built")
    }
    let out = open $file | to json | ^$env.NUS_BIN validate $schema - | complete
    if $out.exit_code == 0 {
        {ok: true, detail: ''}
    } else {
        let said = [$out.stdout $out.stderr] | str join (char nl) | str trim
        {ok: false, detail: $"($file | path basename): ($said)"}
    }
}

# An expected slice: a residual with its manifest, or findings and nothing else.
def check-slice-expected [expected: path, schemas: path] {
    let residual = $expected | path join residual.nu
    let manifest = $expected | path join manifest.nuon
    let findings = $expected | path join findings.nuon
    if ($findings | path exists) {
        if ($residual | path exists) or ($manifest | path exists) {
            return {ok: false, detail: "a refused slice has findings and nothing else"}
        }
        let found = open $findings
        let shaped = $found | all {|f|
            ($f | columns | sort) == [message span] and ($f.span | columns | sort) == [end start] and $f.span.start <= $f.span.end
        }
        return (if ($found | is-not-empty) and $shaped {
            {ok: true, detail: ''}
        } else {
            {ok: false, detail: "findings are records of a span, start and end, and a message, at least one"}
        })
    }
    if not ($residual | path exists) or not ($manifest | path exists) {
        return {ok: false, detail: $"($expected) holds residual.nu and manifest.nuon, or findings.nuon"}
    }
    let text = open --raw $residual
    if ($text | str trim | is-empty) or not ($text | str ends-with "\n") {
        return {ok: false, detail: "the residual is not empty and ends with one newline"}
    }
    validate-nuon $manifest ($schemas | path join slice.schema.json)
}

# Whether two expected slices are the same bytes.
def same-slice [a: path, b: path] {
    [residual.nu manifest.nuon findings.nuon] | all {|file|
        let x = $a | path join $file
        let y = $b | path join $file
        ($x | path exists) == ($y | path exists) and (not ($x | path exists) or (open --raw $x) == (open --raw $y))
    }
}

# The slicer's own row: `nus slice <script> --shape <shape> --out <dir>` must write the
# expected files byte for byte. Pending, not skipped, until the subcommand exists: the
# fixtures are the design, written ahead of it.
def check-slice [script: path, shape: path, expected: path] {
    if not ($env.NUS_BIN | path exists) {
        return (skipped $"($env.NUS_BIN) is not built")
    }
    let probe = ^$env.NUS_BIN slice --help | complete
    if $probe.exit_code != 0 {
        return {ok: true, skipped: true, detail: "pending: nus slice is not implemented"}
    }
    let out = mktemp --directory
    let sliced = ^$env.NUS_BIN slice $script --shape $shape --out $out | complete
    let outcome = if $sliced.exit_code != 0 and not (($expected | path join findings.nuon) | path exists) {
        {ok: false, detail: ($sliced.stderr | str trim)}
    } else if (same-slice $out $expected) {
        {ok: true, detail: ''}
    } else {
        let diff = ^diff --recursive --unified $expected $out | complete
        {ok: false, detail: ($diff.stdout | str trim)}
    }
    rm --recursive $out
    $outcome
}

# `nus check`: the module carries what the spec shows, as usage reads the spec, for
# every command, its positionals, flags, completers and description.
def check-conform [
    dir: path
    module: path
    bin: string
    is_binary: bool
] {
    if not ($env.NUS_BIN | path exists) {
        return (skipped $"($env.NUS_BIN) is not built")
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
    # A service's spec has its HTTP mapping beside it.
    let http = $dir | path join $"($bin).http.kdl"
    let mapping = if ($http | path exists) { [--http $http] } else { [] }
    let out = ^$env.NUS_BIN check $source $module ...$overlays ...$mapping | complete
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

# The module's shadows run the scripts they call with the `nus` on PATH: the one built here.
def check-shim [import: string, bin: string, case: record] {
    let code = $"($import); ($bin) (words-of $case) | to nuon"
    run-nu $code {
        PATH: (search-path [
            ($env.NUS_BIN | path dirname)
        ])
    } | after-printed $case | compare (expected-output $case)
}

# The module written for a session with the plugin registered, `nus generate --plugin`: the
# helpers the plugin serves are called and not defined, so its shadows run their scripts in
# the plugin's process. Written afresh into a directory of its own, run under this Nushell
# with the built plugin, and held to the same cases as the module that stands on its own.
def check-shim-plugin [dir: path, bin: string, case: record] {
    if not ($env.NUS_BIN | path exists) {
        return (skipped $"($env.NUS_BIN) is not built")
    }
    if not ($env.NUS_PLUGIN | path exists) {
        return (skipped $"($env.NUS_PLUGIN) is not built")
    }
    let single = $dir | path join script.nu
    let source = if ($single | path exists) {
        $single
    } else {
        $dir | path join $bin
    }
    let out = mktemp --directory
    let module = $out | path join $"($bin).nu"
    let generated = ^$env.NUS_BIN generate --plugin $source --out $module | complete
    if $generated.exit_code != 0 {
        rm --recursive $out
        return {
            ok: false
            detail: ($generated.stderr | str trim)
        }
    }
    let outcome = run-nu $"use ($module | to nuon); ($bin) (words-of $case) | to nuon" {
        PATH: (search-path [
            ($env.NUS_BIN | path dirname)
        ])
    } --plugins [$env.NUS_PLUGIN] | after-printed $case | compare (expected-output $case)
    rm --recursive $out
    $outcome
}

def check-interpreter [dir: path, bin: string, case: record] {
    let script = script-for $dir $bin $case.usage.cmd
    # The shadows of the scripts it calls, which only the built nusage knows.
    let prelude = if ($env.NUS_BIN | path exists) {
        ^$env.NUS_BIN prelude --run $script
    } else {
        ""
    }
    let code = $"($prelude)\nlet usage = \($env.NUS_ARGS | from nuon\); $in | run ($script | to nuon) | to nuon"
    run-nu $code {
        NUS_ARGS: ($case.usage | to nuon)
    } | after-printed $case | compare (expected-output $case)
}

# The plugin's `nus call`: the script run in an engine inside the plugin's process, by the
# built plugin under this Nushell, which must return the interpreter's value after what the
# script printed.
def check-executor [dir: path, bin: string, case: record] {
    if not ($env.NUS_PLUGIN | path exists) {
        return (skipped $"($env.NUS_PLUGIN) is not built")
    }
    # The root script, with the case's argv: the executor routes to the subcommand's, as
    # the interpreter does.
    let script = script-for $dir $bin []
    let code = $"nus call ($script | to nuon) nus ($script | to nuon) ...($case.argv | to nuon) | to nuon"
    run-nu $code {} --plugins [$env.NUS_PLUGIN] | after-printed $case | compare (expected-output $case)
}

# A binary call against the fixture's fake binary: the argv it recorded must be the case's
# `argv`, and what the call returns the case's `output`, when the case gives them; a case
# with `error` must fail instead, with a message containing it. The built `nus` is on
# PATH, as a module holds a failed decode to its schema through it.
def check-invoke [dir: path, import: string, case: record] {
    let argv_file = mktemp
    let out = run-nu $"($import); ($case.invoke) | to nuon" {
        PATH: (search-path [
            ($dir | path join fake)
            ($env.NUS_BIN | path dirname)
        ])
        NUS_FAKE_STDOUT: ($case.stdout? | default "")
        NUS_FAKE_ARGV: $argv_file
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

# The record the built `nus` makes of the case's argv, as its shebang form would hand it
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

# The interpreter entrypoint itself: `nus <root script> ...argv` routes the call to the
# script of the command the words select and runs it with its `$usage`, so it prints the
# value the shim and the handoff return, as Nushell shows it; the same value rendered by
# the same Nushell is what it must print. `--help` prints the spec's help, and a call
# without arguments ends as `nus parse` says: refused with exit code 2, or run.
def check-run [dir: path, bin: string, case: record] {
    if not ($env.NUS_BIN | path exists) {
        return (skipped $"($env.NUS_BIN) is not built")
    }
    let script = script-for $dir $bin []
    let ran = ^$env.NUS_BIN $script ...$case.argv | complete
    if $ran.exit_code != 0 {
        return {
            ok: false
            detail: $"exit ($ran.exit_code): ($ran.stderr | str trim)"
        }
    }
    let shown = run-nu '$env.NUS_EXPECTED | from nuon' {
        NUS_EXPECTED: ((expected-output $case) | to nuon)
    }
    let printed = {
        ok: true
        detail: ($ran.stdout | str trim)
    } | after-printed $case
    if not $printed.ok {
        return $printed
    }
    if $printed.detail != $shown.detail {
        return {
            ok: false
            detail: $"printed:\n($ran.stdout | str trim)\nexpected:\n($shown.detail)"
        }
    }
    let help = ^$env.NUS_BIN $script --help | complete
    if $help.exit_code != 0 or not ($help.stdout | str contains "Usage:") {
        return {
            ok: false
            detail: $"--help: exit ($help.exit_code): ($help.stdout)($help.stderr)"
        }
    }
    let parsed = ^$env.NUS_BIN parse $script -- | complete
    let bare = ^$env.NUS_BIN $script | complete
    if $parsed.exit_code not-in [0 2] or $bare.exit_code != $parsed.exit_code {
        return {
            ok: false
            detail: $"without arguments, parse exited ($parsed.exit_code) and the run ($bare.exit_code): ($bare.stderr | str trim)"
        }
    }
    {ok: true, detail: ""}
}

def check-parse [dir: path, case: record] {
    if not ($env.NUS_BIN | path exists) {
        return (skipped $"($env.NUS_BIN) is not built")
    }
    let script = $dir | path join script.nu
    let out = ^$env.NUS_BIN parse $script -- ...$case.argv | complete
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

# PATH with the directories first, as an external reads it.
def search-path [dirs: list<path>] {
    let path = $env.PATH
    let path = if ($path | describe | str starts-with list) {
        $path | str join (char esep)
    } else {
        $path
    }
    $dirs | append $path | str join (char esep)
}

# The `$usage` type `nus prelude` declares holds the record the script sees: the prelude's
# typed `let` binds the case's record, and Nushell checks the binding as it runs, so the type
# cannot drift from the record the shim and the interpreter build.
def check-prelude [dir: path, bin: string, case: record] {
    if not ($env.NUS_BIN | path exists) {
        return (skipped $"($env.NUS_BIN) is not built")
    }
    let script = script-for $dir $bin $case.usage.cmd
    let prelude = ^$env.NUS_BIN prelude $script | complete
    if $prelude.exit_code != 0 {
        return {
            ok: false
            detail: ($prelude.stderr | str trim)
        }
    }
    run-nu $"($prelude.stdout)\n$usage | to nuon" {
        NUS_USAGE: ($case.usage | to nuon)
    } | compare $case.usage
}

def run-nu [code: string, env_vars: record, --plugins: list<path> = []] {
    let plugins = if ($plugins | is-empty) {
        []
    } else {
        [
            "--plugins" ($plugins | to nuon)
        ]
    }
    let out = with-env $env_vars { ^$nu.current-exe -n ...$plugins -c $code } | complete
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

# What a call printed before its value: the case's `printed`, which must come first, is taken
# off, so what follows is the value.
def after-printed [case: record] {
    let out = $in
    let printed = $case.printed? | default ""
    if not $out.ok or ($printed | is-empty) {
        return $out
    }
    if not ($out.detail | str starts-with $printed) {
        return {
            ok: false
            detail: $"expected ($printed | to nuon) printed first, got:\n($out.detail)"
        }
    }
    {
        ok: true
        detail: ($out.detail | str substring ($printed | str length).. | str trim)
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
$env.NUS_BIN = $env.NUS_BIN? | default (
    $root
    | path dirname
    | path dirname
    | path join .bin nus
)
$env.NUS_PLUGIN = $env.NUS_PLUGIN? | default (
    $root
    | path dirname
    | path dirname
    | path join .bin nu_plugin_nus
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
