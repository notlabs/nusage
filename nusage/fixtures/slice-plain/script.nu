#!/usr/bin/env nus
#USAGE arg "<who>" help="Who to greet"
#USAGE output ("string")"nuon" default=#true
# The simplest slice: nothing is folded, nothing is read but `$usage`, and the residual is the
# reachable statements with the header and the comments gone.

# Greets, after a note to the terminal that the residual keeps, since it is reachable.
print "greeting"
let greeting = $"hello ($usage.args.who)"
$greeting
