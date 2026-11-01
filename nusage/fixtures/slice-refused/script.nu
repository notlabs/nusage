#!/usr/bin/env nus
#USAGE arg "<name>" help="The environment variable to read"
#USAGE output ("string")"nuon" default=#true
# A read the slicer cannot name: the variable is chosen at run time, so the slice is refused,
# with a finding at the read, rather than guessed at. A slice that named too little would be
# a cache that answered wrongly.
$env | get $usage.args.name
