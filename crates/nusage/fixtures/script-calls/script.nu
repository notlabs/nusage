#!/usr/bin/env nus
#USAGE name "caller"
#USAGE bin "caller"
#USAGE about "Calls the script beside it, by its path and through nusage and nu"
#USAGE arg "<who>"
#USAGE output ("record<path: record<greeting: string, times: int, at: datetime>, nus: string, nu: int, at: string>")"nuon" default=#true

# A contract fixture: each call of `callee.nu` is the shadow nusage defines for it, so the
# arguments are typed and parsed by the callee's header, the value comes back typed, and what
# the callee prints reaches the terminal.
{
    path: (./callee.nu $usage.args.who --times 2 --chatty)
    nus: (nus callee.nu $usage.args.who --loud).greeting
    nu: (nu callee.nu $usage.args.who).times
    at: (./callee.nu $usage.args.who | get at | describe)
}
