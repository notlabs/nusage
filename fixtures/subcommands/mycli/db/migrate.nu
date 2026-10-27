#!/usr/bin/env nusage
#USAGE about "Run migrations"
#USAGE arg "<target>" help="Target environment" { choices run="./targets.nu" }
#USAGE flag "--dry-run" help="Plan without applying"
#USAGE flag "--since" help="Only migrations after this time" { arg (datetime)"<since>" }
#USAGE flag "--limit" help="At most this many" default="10" { arg (int)"<n>" }

$usage
