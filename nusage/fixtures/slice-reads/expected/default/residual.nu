const here = path self | path dirname
let greeting = $env.GREETING? | default "hello"
let first = $in | default []
let names = open ($here | path join names.txt) | lines
$first | append $names | each {|name| $"($greeting) ($name)" }
