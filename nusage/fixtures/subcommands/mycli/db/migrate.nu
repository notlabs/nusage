#!/usr/bin/env nus
#USAGE about "Run migrations"
#USAGE arg "<target>" help="Target environment" { choices run="./targets.nu" }
#USAGE flag "--dry-run" help="Plan without applying"
#USAGE flag "--since" help="Only migrations after this time" default="2026-01-01T00:00:00Z" { arg (datetime)"<since>" }
#USAGE flag "--limit" help="At most this many" default="10" { arg (int)"<n>" }
#USAGE flag "--color" help="Colorize the plan" default=#true negate="--no-color"

$usage
