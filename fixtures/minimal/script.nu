#!/usr/bin/env nusage
#USAGE name "greet"
#USAGE bin "greet"
#USAGE about "Greet someone"
#USAGE arg "<name>" help="Who to greet"
#USAGE flag "-l --loud" help="Shout the greeting"
#USAGE flag "--times <n>" help="How many times to greet"

# A contract fixture: the script's value is the `$usage` record it was handed,
# so a case can assert exactly what each entrypoint delivered.
$usage
