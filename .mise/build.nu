#!/usr/bin/env nu

let metadata = ^cargo metadata --format-version 1 --no-deps --locked | from json --strict
let members = $metadata.workspace_members
let result = ^cargo build --workspace --locked --message-format json-render-diagnostics | complete
print --stderr --no-newline $result.stderr
if $result.exit_code != 0 { exit $result.exit_code }
let built = $result.stdout
    | lines
    | each { from json --strict }
    | where {|message| $message.reason == compiler-artifact and $message.executable? != null }
    | where {|message| 'bin' in $message.target.kind and $message.package_id in $members }
    | get executable
let bin = $metadata.workspace_root | path join target install bin
mkdir $bin
for exe in $built {
    let copy = $bin | path join ($exe | path basename)
    if ($copy | path type) == symlink { rm $copy }
    # Replace atomically so a running language server can keep its previous binary.
    let partial = $"($copy).partial"
    cp $exe $partial
    mv --force $partial $copy
}
