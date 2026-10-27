#!/usr/bin/env nusage
#USAGE about "List migration targets"
#USAGE output ("list<string>")"nuon" default=#true

# A command in its own right, and the completion provider `migrate` names with
# `choices run="./targets.nu"`: the shim references this command as the parameter's
# completer directly.
[dev staging prod]
