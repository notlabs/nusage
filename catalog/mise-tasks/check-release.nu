#!/usr/bin/env nus
#MISE description="Check interrupted package release recovery without publishing assets"

use std/assert
use ../lib/release.nu prepare-packages

const source = "1111111111111111111111111111111111111111"
const later = "2222222222222222222222222222222222222222"

const packages = [
    {
        name: a
        version: "0.2.0"
        tag: "catalog/a/v0.2.0"
        archive: "dist/nusage-a-0.2.0.tar.gz"
    }
    {
        name: b
        version: "0.2.0"
        tag: "catalog/b/v0.2.0"
        archive: "dist/nusage-b-0.2.0.tar.gz"
    }
]

def asset [name: string] {
    {name: $name, state: uploaded, size: 42}
}
def empty-state [] {
    {
        releases: []
        tags: []
        calls: []
        fail: null
    }
}
def stored-release [state: record, tag: string] {
    $state.releases | where tag == $tag | get -o 0
}
def stored-tag [state: record, tag: string] {
    $state.tags | where name == $tag | get -o 0
}
def replace-release [state: record, release: record] {
    $state | update releases {
        $state.releases | where tag != $release.tag | append $release
    }
}

# Fake only the external GitHub boundary; exercise the production decision code.
def fake-gh [file: path, args: list<string>] {
    mut state = open $file
    $state.calls = $state.calls | append [$args]
    let result = if $state.fail != null and ($args | take ($state.fail | length)) == $state.fail {
        {exit_code: 1, stdout: "", stderr: "service unavailable (HTTP 503)"}
    } else if $args.0 == api {
        let endpoint = $args.1 | url decode
        let value = if ($endpoint | str contains /releases/tags/) {
            stored-release $state ($endpoint | split row /releases/tags/ | last)
        } else if ($endpoint | str contains /commits/) {
            stored-tag $state ($endpoint | split row /commits/ | last)
        } else {
            error make {msg: $"Unexpected endpoint: ($endpoint)"}
        }
        if $value == null {
            {exit_code: 1, stdout: "", stderr: "not found (HTTP 404)"}
        } else {
            {
                exit_code: 0
                stdout: ($value | to json --raw)
                stderr: ""
            }
        }
    } else if ($args | take 2) == [release create] {
        let target = (
            $args
            | enumerate
            | where item == "--target"
            | first
            | get index
        ) + 1
        let release = {
            tag: $args.2
            draft: false
            assets: [
                (asset ($args.3 | path basename))
            ]
        }
        $state = replace-release $state $release
        $state.tags = $state.tags | where name != $args.2 | append {name: $args.2, sha: ($args | get $target)}
        {exit_code: 0, stdout: "", stderr: ""}
    } else if ($args | take 2) == [release upload] {
        let name = $args.3 | path basename
        let release = stored-release $state $args.2
        let updated = $release | update assets { $release.assets | where name != $name | append (asset $name) }
        $state = replace-release $state $updated
        {exit_code: 0, stdout: "", stderr: ""}
    } else {
        error make {msg: $"Unexpected gh call: ($args)"}
    }
    $state | save --force $file
    $result
}

def rejected [action: closure, expected: string] {
    let outcome = try {
        do $action | collect | ignore
        null
    } catch {|err|
        $err.rendered
    }
    assert ($outcome != null)
    assert ($outcome | str contains $expected) $outcome
}

def single-state [assets: list<record>] {
    empty-state
    | update releases [
        {tag: $packages.0.tag, draft: false, assets: $assets}
    ]
    | update tags [
        {name: $packages.0.tag, sha: $source}
    ]
}

let scratch = mktemp -d
let state_file = $scratch | path join state.nuon
let gh = {|args| fake-gh $state_file $args }

let outcome = try {

    # A publishes, then B fails: rerunning must include A for signing as well as B.
    empty-state | update fail [release create $packages.1.tag] | save $state_file
    rejected { prepare-packages $packages test/repo $source $gh } "HTTP 503"
    assert ((stored-release (open $state_file) $packages.0.tag) != null)
    open $state_file | update fail null | save --force $state_file
    let resumed = prepare-packages $packages test/repo $source $gh
    assert equal ($resumed | get name) [a b]
    assert equal ($resumed | get commit) [$source $source]
    assert (
        (open $state_file).calls
        | where {|call| ($call | take 2) == [release upload]}
        | is-empty
    )

    # Signing fails, or attaching one bundle fails: only incomplete releases retry.
    assert equal (prepare-packages $packages test/repo $source $gh | get name) [a b]
    do $gh [release upload $packages.0.tag packslip.catalog-a.sigstore.json] | ignore
    assert equal (prepare-packages $packages test/repo $source $gh | get name) [b]
    do $gh [release upload $packages.1.tag packslip.catalog-b.sigstore.json] | ignore
    assert equal (prepare-packages $packages test/repo $source $gh) []

    # A later main commit signs the original bytes with their original source commit.
    single-state [
        (asset nusage-a-0.2.0.tar.gz)
    ] | save --force $state_file
    let recovered = prepare-packages [$packages.0] test/repo $later $gh
    assert equal $recovered.0.commit $source
    assert equal $recovered.0.asset nusage-a-0.2.0.tar.gz
    assert ((open $state_file).calls | where {|call| $call.0 == release} | is-empty)

    # An interrupted archive upload is repairable only from the original revision.
    single-state [
        {name: nusage-a-0.2.0.tar.gz, state: starter, size: 0}
    ] | save --force $state_file
    assert equal (prepare-packages [$packages.0] test/repo $source $gh | get name) [a]
    assert equal ((stored-release (open $state_file) $packages.0.tag).assets.0.state) uploaded
    single-state [] | save --force $state_file
    rejected { prepare-packages [$packages.0] test/repo $later $gh } "original workflow revision"
    assert ((open $state_file).calls | where {|call| $call.0 == release} | is-empty)

    # A tag without a release must not attach bytes built from a newer revision.
    single-state [] | update releases [] | save --force $state_file
    rejected { prepare-packages [$packages.0] test/repo $later $gh } "original workflow revision"

    # An uploaded signature is never paired with a rebuilt archive, even at the same SHA.
    single-state [
        (asset packslip.catalog-a.sigstore.json)
    ] | save --force $state_file
    rejected { prepare-packages [$packages.0] test/repo $source $gh } "restore the original archive"
    assert ((open $state_file).calls | where {|call| $call.0 == release} | is-empty)

    # Draft releases and releases whose tag disappeared cannot be signed read-only.
    single-state [
        (asset nusage-a-0.2.0.tar.gz)
    ]
    | update releases {|state| $state.releases | update draft true}
    | save --force $state_file
    rejected { prepare-packages [$packages.0] test/repo $source $gh } "no published tag"
    single-state [
        (asset nusage-a-0.2.0.tar.gz)
    ] | update tags [] | save --force $state_file
    rejected { prepare-packages [$packages.0] test/repo $source $gh } "no published tag"

    # Auth/network/server errors must not be mistaken for a missing release.
    empty-state | update fail [api] | save --force $state_file
    rejected { prepare-packages [$packages.0] test/repo $source $gh } "HTTP 503"
    assert ((open $state_file).calls | where {|call| $call.0 == release} | is-empty)
    null
} catch {|err| $err }
rm --recursive --force $scratch
if $outcome != null { error make $outcome }
print "catalog release recovery checks passed"
