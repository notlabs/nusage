#!/usr/bin/env nus
#USAGE arg "<who>" help="Who to greet"
#USAGE flag "--loud" help="In capitals"
#USAGE output ("string")"nuon" default=#true
# A switch that chooses a branch: a shape folds it in, and the branch not taken leaves no
# trace in the residual, so an edit to that branch changes the slice of the other shape only.
let greeting = $"hello ($usage.args.who)"
if $usage.flags.loud {
    $greeting | str upcase
} else {
    $greeting
}
