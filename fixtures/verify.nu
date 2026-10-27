#!/usr/bin/env nu
# Verify the fixtures against the `nu` that runs this script.
#
# Every case goes through both entrypoints and must return the same value:
#   - shim:        `use expected/<bin>.nu; <bin> <words>`        (Nushell types the arguments)
#   - interpreter: `let usage = ($env.NUSAGE_ARGS | from nuon); $in | run <script>`
#                                                                  (the record is handed in as NUON)
# A case with `complete` also asks the shim module for completions at a point of a line.
# Then the parsed signature and attributes of the root and every command a case names, as
# `scope commands` reports them, are compared with expected/signatures.nuon.
#
#   nu fixtures/verify.nu                          # all fixtures
#   nu fixtures/verify.nu fixtures/minimal         # one
#   nu fixtures/verify.nu --update-signatures      # rewrite expected/signatures.nuon from live output

def main [
    ...fixtures: path,     # Fixture directories; default: every directory under fixtures/
    --update-signatures,   # Rewrite expected/signatures.nuon instead of comparing it
] {
    let root = $env.CURRENT_FILE | path dirname
    let fixtures = if ($fixtures | is-empty) {
        ls $root | where type == dir | get name
    } else {
        $fixtures | each { path expand }
    }
    let results = $fixtures | each {|dir| verify-fixture $dir $update_signatures } | flatten
    print ($results | select fixture check case ok | table --expand)
    let failed = $results | where not ok
    if ($failed | is-not-empty) {
        print --stderr ($failed | select fixture check case detail | table --expand)
        error make --unspanned {msg: $"($failed | length) of ($results | length) checks failed"}
    }
    print $"all ($results | length) checks passed"
}

# One row per check: shim, interpreter and (when present) completion per case, then signatures.
def verify-fixture [dir: path, update: bool] {
    let name = $dir | path basename
    let module = glob ($dir | path join expected '*.nu') | first
    let bin = $module | path parse | get stem
    let cases = glob ($dir | path join cases '*.nuon') | sort
    let per_case = $cases | each {|file|
        let case = open $file
        let id = $file | path parse | get stem
        let rows = [
            (row $name shim $id (check-shim $module $bin $case))
            (row $name interpreter $id (check-interpreter $dir $bin $case))
        ]
        if ($case.complete? | is-not-empty) {
            $rows | append (row $name complete $id (check-complete $module $case.complete))
        } else {
            $rows
        }
    } | flatten
    let cmds = [
        []
    ] | append ($cases | each {|f| open $f | get usage.cmd }) | uniq
    $per_case | append ((row
        $name
        signatures
        ""
        (check-signatures $dir $module $bin $cmds $update)
    ))
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

def check-shim [module: path, bin: string, case: record] {
    let code = $"use ($module | to nuon); ($bin) (words-of $case) | to nuon"
    run-nu $code {} | compare (expected-output $case)
}

def check-interpreter [dir: path, bin: string, case: record] {
    let script = script-for $dir $bin $case.usage.cmd
    let code = $"let usage = \($env.NUSAGE_ARGS | from nuon\); $in | run ($script | to nuon) | to nuon"
    run-nu $code {
        NUSAGE_ARGS: ($case.usage | to nuon)
    } | compare (expected-output $case)
}

def check-complete [module: path, complete: record] {
    let code = $"use ($module | to nuon); ($complete.line | to nuon) | commandline complete | to nuon"
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
    module: path
    bin: string
    cmds: list<any>
    update: bool
] {
    let names = $cmds | each {|cmd| [$bin] | append $cmd | str join ' ' }
    let code = $"use ($module | to nuon); scope commands | where name in ($names | to nuon) | select name signatures attributes | to nuon --indent 2"
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
