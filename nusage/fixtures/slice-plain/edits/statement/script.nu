#!/usr/bin/env nus
#USAGE arg "<who>" help="Who to greet"
#USAGE output ("string")"nuon" default=#true
# A reachable statement changed: the residual changes with it, and so does the slice's
# address.
print "greeting"
let greeting = $"hello, ($usage.args.who)"
$greeting
