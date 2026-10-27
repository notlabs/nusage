#!/usr/bin/env nusage
#USAGE about "List migration targets"
#USAGE output ("list<string>")"nuon" default=#true

# A command in its own right, and the completion provider `migrate` names with
# `choices run="./targets.nu"`. Because it is a sibling command, the generated completer
# calls it directly and the parser checks its declared output type.
[dev staging prod]
