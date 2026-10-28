#!/usr/bin/env nusage
#USAGE name "greet"
#USAGE bin "greet"
#USAGE about "Greet someone"
#USAGE long_about "A contract fixture.\nIts value is the record it was handed."
#USAGE arg "<name>" help="Who to greet,\nby name"
#USAGE flag "-l --loud" help="Shout the greeting"
#USAGE flag "--times" help="How many times to greet" default="1" { arg (int)"<n>" }
#USAGE output ("record<cmd: list<string>, args: record<name: string>, flags: record<loud: bool, times: int>>")"nuon" default=#true

# A contract fixture: the script's value is the `$usage` record it was handed, so a case
# can assert exactly what each entrypoint delivered. The output annotation above is that
# record's type.
$usage
