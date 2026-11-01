#!/usr/bin/env nus
#USAGE arg "<who>" help="Who to greet"
#USAGE output ("record<script: string, task: string>")"nuon" default=#true
# Calls a script beside it and a task of mise's. Each is named in the manifest by its
# canonical name and the static shape of the call, never inlined: a callee's own slice has
# its own address, and what a run of this slice reads is the callee's result.
{
    script: (./callee.nu $usage.args.who --loud)
    task: (mise run greet $usage.args.who)
}
