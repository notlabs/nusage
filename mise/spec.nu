#!/usr/bin/env nusage
#USAGE flag "--out <dir>" default="generated" help="Where the spec is written"
# The spec of the mise on PATH, written only when it differs from the one written before,
# so that what depends on it stays fresh across runs.
let out = $usage.flags.out
mkdir $out
let file = $out | path join mise.usage.kdl
let spec = ^mise usage
if not ($file | path exists) or (open --raw $file) != $spec {
    $spec | save --force $file
}
