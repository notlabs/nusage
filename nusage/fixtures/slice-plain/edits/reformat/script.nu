#!/usr/bin/env nus
#USAGE arg "<who>" help="Who to greet"
#USAGE output ("string")"nuon" default=#true
# The same statements, laid out differently: the residual is canonical, so the layout of the
# source does not reach it.
print   "greeting"
let greeting = $"hello ($usage.args.who)"


$greeting
