#!/usr/bin/env nusage
#USAGE about "List migration targets"
#USAGE output ("list<string>")"nuon" default=#true

# A command in its own right, and the completion provider `migrate` names with
# `choices run="./targets.nu"`: the shim references this command as the parameter's
# completer directly. It declares no flags and gets no inherited ones: Nushell binds
# only the token positional when it calls a completer, so any flag would be unbound.
[dev staging prod]
