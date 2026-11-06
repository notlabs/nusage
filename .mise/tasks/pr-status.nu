#!/usr/bin/env nus
#USAGE flag "--repo <repo>" default="notlabs/nusage"
#USAGE flag "--limit <limit>" default="100" { arg (int)"<limit>" }
#USAGE flag "--json" help="Print JSON for another process instead of a Nushell table"
#MISE description="Report where each open pull request stands"
#MISE depends=["^build"]
#MISE tools={gh="2.103.3"}
#MISE cache={enabled=false}
use ../../catalog/lib/gh *
use ../lib/pr-status.nu report

let prs = gh pr list --repo $usage.flags.repo --limit ($usage.flags.limit | into string) --state open
let rows = report $prs
if $usage.flags.json {
    $rows | to json
} else {
    $rows
}
