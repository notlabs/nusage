#!/usr/bin/env nusage
#USAGE about "Holds the intent to its schemas and its checked claims to nusage as it is"
# Disposable: the claims, the traits and the schemas are what last. This holds each file to
# its schema, the names the claims use to the traits and the graph's words, and runs each
# checked claim against today's `nusage prelude`, backed by `nusage inspect`; an open claim
# it only holds to its shape.

const here = path self | path dirname

# Where a value breaks its schema, a line each; none when it holds.
def findings [schema: string, name: string]: any -> list<string> {
    let result = $in | to json | ^nusage validate ($here | path join $schema) - | complete
    if $result.exit_code == 0 {
        return []
    }
    $result.stdout + $result.stderr | lines | where $it != "" | each {|line| $"($name): ($line)" }
}

def write-files [dir: string, files: record] {
    for file in ($files | transpose path text) {
        let target = $dir | path join $file.path
        mkdir ($target | path dirname)
        $file.text | save --force --raw $target
        # mise discovers file tasks by their executable bit; no config needs trusting.
        if $nu.os-info.name != windows and ($file.text | str starts-with "#!") {
            ^chmod +x $target
        }
    }
}

# Inspect validates the resolved analysis on both sides. Prelude retains the existing
# comparison semantics, including the caller's own $usage type.
def analysis [dir: string, script: string]: nothing -> record {
    let result = do {
        cd $dir
        ^nusage inspect ($dir | path join $script) | complete
    }
    if $result.exit_code != 0 {
        error make --unspanned {msg: $"nusage inspect ($script): ($result.stderr)"}
    }
    let inspected = $result.stdout | from json
    if ($inspected.findings | is-not-empty) {
        error make --unspanned {
            msg: $"nusage inspect ($script) has findings: ($inspected.findings | to nuon)"
        }
    }
    # Prelude carries the caller's own $usage type, which inspect's resolved calls do not.
    let prelude = do {
        cd $dir
        ^nusage prelude ($dir | path join $script) | complete
    }
    if $prelude.exit_code != 0 or ($prelude.stderr | str trim | is-not-empty) {
        error make --unspanned {msg: $"nusage prelude ($script): ($prelude.stderr)"}
    }
    $inspected | insert prelude $prelude.stdout
}

# A named call must stay resolved, with exactly the long flags its claim expects.
def call-flags [analysis: record, expected: record, phase: string] {
    let calls = $analysis.calls | where name == $expected.name
    if ($calls | length) != 1 {
        error make --unspanned {msg: $"($phase): expected one resolved call to ($expected.name)"}
    }
    let flags = $calls.0.command.flags | get long | compact | sort
    let wanted = $expected | get $"($phase)_flags" | sort
    if $flags != $wanted {
        error make --unspanned {
            msg: $"($phase): ($expected.name) has flags ($flags | to nuon), expected ($wanted | to nuon)"
        }
    }
}

# What the claim's change does to the analysis, against what it expects.
def holds [claim: record]: nothing -> bool {
    let dir = mktemp --directory
    write-files $dir $claim.given.files
    let before = analysis $dir $claim.given.script
    let after = if ($claim.change.moved? | default false) {
        let moved = mktemp --directory
        for entry in (ls --all $dir) {
            cp --recursive $entry.name $moved
        }
        # Paths move with the fixture; normalize that directory in the compared prelude.
        let after = analysis $moved $claim.given.script
        rm --recursive $moved
        $after | update prelude ($after.prelude | str replace --all $moved $dir)
    } else {
        write-files $dir $claim.change.files
        analysis $dir $claim.given.script
    }
    rm --recursive $dir
    for expected in ($claim.expect.calls? | default []) {
        call-flags $before $expected before
        call-flags $after $expected after
    }
    if $claim.expect.analysis == changed {
        $after.prelude != $before.prelude
    } else {
        $after.prelude == $before.prelude
    }
}

let traits = open ($here | path join traits.nuon)
mut failed = $traits | findings trait.schema.json traits.nuon
mut claims = []
for file in (glob ($here | path join claims *.nuon) | sort) {
    let name = $file | path relative-to $here
    let these = open $file
    $failed ++= $these | findings claim.schema.json $name
    $claims ++= $these | each {|claim| $claim | insert file $name }
}
if ($failed | is-empty) {
    let names = $traits | get name
    for id in ($claims | get id | uniq --repeated) {
        $failed ++= [$"claims: `($id)` is the id of more than one claim"]
    }
    for claim in $claims {
        let named = ($claim.traits? | default []) ++ ($claim.expect?.traits? | default [])
        for name in ($named | where $it not-in $names) {
            $failed ++= [$"($claim.file): ($claim.id): no trait is named `($name)`"]
        }
        if $claim.expect?.graph? != null {
            let graph = $claim.expect.graph
            $failed ++= $graph | findings graph.schema.json $"($claim.file): ($claim.id)"
            let ids = $graph.nodes? | default [] | get id
            for end in (
                $graph.edges?
                | default []
                | each {|edge| [$edge.from $edge.to] }
                | flatten
                | uniq
            ) {
                if $end not-in $ids {
                    $failed ++= [
                        $"($claim.file): ($claim.id): an edge names `($end)`, which no node is"
                    ]
                }
            }
        }
    }
}
if ($failed | is-empty) {
    for claim in ($claims | where status == checked) {
        if not (holds $claim) {
            $failed ++= [
                $"($claim.file): ($claim.id): the analysis is not ($claim.expect.analysis) by the change"
            ]
        }
    }
}

print ($claims | group-by file --to-table | each {|group|
    {
        file: $group.file
        open: ($group.items | where status == open | length)
        checked: ($group.items | where status == checked | length)
    }
})
if ($failed | is-not-empty) {
    error make --unspanned {
        msg: ($failed | str join "\n")
    }
}
