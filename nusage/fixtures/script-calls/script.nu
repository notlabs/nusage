#!/usr/bin/env nusage
#USAGE name "caller"
#USAGE bin "caller"
#USAGE about "Calls the script beside it, by its path and through nusage and nu"
#USAGE arg "<who>"
#USAGE output ("record<path: record<greeting: string, times: int, at: datetime>, nusage: string, nu: int, at: string>")"nuon" default=#true

# A contract fixture: each call of `callee.nu` is the shadow nusage defines for it, so the
# arguments are typed and parsed by the callee's header, and the value comes back typed.
{
    path: (./callee.nu $usage.args.who --times 2)
    nusage: (nusage callee.nu $usage.args.who --loud).greeting
    nu: (nu callee.nu $usage.args.who).times
    at: (./callee.nu $usage.args.who | get at | describe)
}
