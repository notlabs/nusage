#!/usr/bin/env nus
#USAGE arg "<who>" help="Who to greet"
#USAGE flag "--loud" help="In capitals"
#USAGE output ("string")"nuon" default=#true
# The branch `--loud` leaves out is changed: the `loud` slice does not see it.
let greeting = $"hello ($usage.args.who)"
if $usage.flags.loud {
    $greeting | str upcase
} else {
    $greeting | str downcase
}
