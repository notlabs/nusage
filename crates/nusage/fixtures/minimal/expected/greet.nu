alias "attr usage" = echo

# Greet someone
#
# A contract fixture.
# Its value is the record it was handed.
@usage 'arg "<name>" help="Who to greet,\nby name"'
@usage 'flag "-l --loud" help="Shout the greeting"'
@usage 'flag "--times" help="How many times to greet" default="1" { arg (int)"<n>" }'
@usage 'output ("record<cmd: list<string>, args: record<name: string>, flags: record<loud: bool, times: int>>")"nuon" default=#true'
export def main [
    name: string,      # Who to greet, by name
    --loud (-l),       # Shout the greeting
    --times: int = 1,  # How many times to greet
]: nothing -> record<cmd: list<string>, args: record<name: string>, flags: record<loud: bool, times: int>> {
    let usage = {
        cmd: []
        args: {name: $name}
        flags: {loud: $loud, times: $times}
    }
    $in | run "../script.nu"
}
