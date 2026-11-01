#!/usr/bin/env nus
#USAGE arg "<name>" help="Who to greet"
#USAGE flag "--loud" help="In capitals"
#USAGE output ("string")"nuon" default=#true
let greeting = $"hello there, ($usage.args.name)"
if $usage.flags.loud {
    $greeting | str upcase
} else {
    $greeting
}
