#!/usr/bin/env nus
#USAGE output ("list<string>")"nuon" default=#true
# What the residual reads at run time, each named in the manifest and none carried by it: the
# input, an environment variable, and a file beside the script by a path the source knows.
# The values are the run's; the names and the type are the slice's.
const here = path self | path dirname
let greeting = $env.GREETING? | default "hello"
let first = $in | default []
let names = open ($here | path join names.txt) | lines
$first | append $names | each {|name| $"($greeting) ($name)" }
