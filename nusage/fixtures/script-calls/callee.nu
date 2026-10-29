#!/usr/bin/env nusage
#USAGE about "Greets, as the script another one calls"
#USAGE arg "<name>"
#USAGE flag "-l --loud"
#USAGE flag "--times" default="1" { arg (int)"<n>" }
#USAGE output ("record<greeting: string, times: int, at: datetime>")"nuon" default=#true

# A record with a datetime in it: what crosses back to the caller is a value of the declared
# type, not the text of a table.
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
