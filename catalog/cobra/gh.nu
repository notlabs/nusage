#!/usr/bin/env nusage
#USAGE about "Export gh's command tree through Usage's Cobra adapter, from a checkout of cli/cli at the pinned tag"
#USAGE flag "--json-fields" help="Print the fields each command's `--json` accepts, as JSON, instead of the spec"
# gh's root command is constructed from internal packages, which only code inside the
# upstream module may import. So the extractor, `../lib/gh/spec/main.go`, is built there: the
# repository is cloned at the tag `pin.toml` names, under the user's cache directory, the file
# is copied in as `cmd/nusage-spec/main.go`, the adapter is added to the checkout's module at
# the pinned version, and `go run` prints what the extractor exports. The checkout is kept for
# the next run, and never pushed anywhere. Go downloads the module's toolchain itself when the
# one on PATH is older.
const here = path self | path dirname

let package = $here | path join .. lib gh spec | path expand
let pin = open ($package | path join pin.toml)
let cache = $env.XDG_CACHE_HOME? | default ($env.HOME | path join .cache) | path join nusage-catalog cli-cli $pin.gh.tag

if not ($cache | path join .git | path exists) {
    mkdir ($cache | path dirname)
    let cloned = ^git -c advice.detachedHead=false clone --quiet --depth 1 --branch $pin.gh.tag $pin.gh.repository $cache | complete
    if $cloned.exit_code != 0 {
        error make --unspanned {
            msg: $"cloning ($pin.gh.repository) at ($pin.gh.tag) failed: ($cloned.stderr | str trim)"
        }
    }
}
# The checkout is held to the pinned commit, not the tag alone: a tag can be moved.
let at = ^git -C $cache rev-parse HEAD | complete
if $at.exit_code != 0 or ($at.stdout | str trim) != $pin.gh.commit {
    error make --unspanned {
        msg: $"($cache) is at ($at.stdout | str trim)($at.stderr | str trim), not ($pin.gh.tag)'s commit ($pin.gh.commit); remove it to clone again"
    }
}

mkdir ($cache | path join cmd nusage-spec)
cp ($package | path join main.go) ($cache | path join cmd nusage-spec main.go)

cd $cache
with-env {GOFLAGS: "", GOTOOLCHAIN: ($env.GOTOOLCHAIN? | default auto)} {
    let adapter = $"($pin.adapter.module)@($pin.adapter.version)"
    let listed = ^go list -m $pin.adapter.module | complete
    if $listed.exit_code != 0 or ($listed.stdout | str trim) != $"($pin.adapter.module) ($pin.adapter.version)" {
        let got = ^go get $adapter | complete
        if $got.exit_code != 0 {
            error make --unspanned {msg: $"adding ($adapter) to the checkout's module failed: ($got.stderr | str trim)"}
        }
    }
    let mode = if $usage.flags.json_fields { ["--json-fields"] } else { [] }
    let exported = ^go run ./cmd/nusage-spec ...$mode $pin.gh.tag | complete
    if $exported.exit_code != 0 {
        error make --unspanned {msg: $"the extractor failed: ($exported.stderr | str trim)"}
    }
    print --no-newline $exported.stdout
}
