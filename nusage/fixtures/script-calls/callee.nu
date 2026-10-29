#!/usr/bin/env nusage
#USAGE about "Greets, as the script another one calls"
#USAGE arg "<name>"
#USAGE flag "-l --loud"
#USAGE flag "--times" default="1" { arg (int)"<n>" }
#USAGE flag "--chatty" help="Say what it is doing, as a script does"
#USAGE output ("record<greeting: string, times: int, at: datetime>")"nuon" default=#true

# A record with a datetime in it: what crosses back to the caller is a value of the declared
# type, not the text of a table, and what the script prints on the way passes through.
if $usage.flags.chatty {
    print $"callee: greeting ($usage.args.name)"
}
let greeting = $"hello ($usage.args.name)"
{
    greeting: (
        if $usage.flags.loud {
            $greeting | str uppercase
        } else {
            $greeting
        }
    )
    times: $usage.flags.times
    at: 2024-01-01T00:00:00Z
}
