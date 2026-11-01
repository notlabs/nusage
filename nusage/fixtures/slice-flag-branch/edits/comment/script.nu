#!/usr/bin/env nus
#USAGE arg "<who>" help="Who to greet"
#USAGE flag "--loud" help="In capitals, as a shout"
#USAGE output ("string")"nuon" default=#true
# Help reworded and a comment added inside the branch: no slice sees either.
let greeting = $"hello ($usage.args.who)"
if $usage.flags.loud {
    # Shouting.
    $greeting | str upcase
} else {
    $greeting
}
