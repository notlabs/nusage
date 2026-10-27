alias "attr usage" = echo

# Manage a project
@usage 'flag "-v --verbose" help="Say more" global=#true'
export def main [
    --verbose (-v),  # Say more
] {
    let usage = {
        cmd: []
        args: {}
        flags: {verbose: $verbose}
    }
    $in | run ../mycli/mod.nu
}

# Manage the database
export def db [
    --verbose (-v),  # Say more
] {
    let usage = {
        cmd: [db]
        args: {}
        flags: {verbose: $verbose}
    }
    $in | run ../mycli/db/mod.nu
}

# List migration targets
@usage 'output ("list<string>")"nuon" default=#true'
export def "db targets" []: nothing -> list<string> {
    let usage = {
        cmd: [db targets]
        args: {}
        flags: {}
    }
    $in | run ../mycli/db/targets.nu
}

# Run migrations
@usage 'arg "<target>" help="Target environment" { choices run="./targets.nu" }'
@usage 'flag "--dry-run" help="Plan without applying"'
@usage 'flag "--since" help="Only migrations after this time" { arg (datetime)"<since>" }'
@usage 'flag "--limit" help="At most this many" default="10" { arg (int)"<n>" }'
export def "db migrate" [
    target: string@"db targets",  # Target environment
    --verbose (-v),               # Say more
    --dry-run,                    # Plan without applying
    --since: datetime,            # Only migrations after this time
    --limit: int = 10,            # At most this many
] {
    let usage = {
        cmd: [db migrate]
        args: {target: $target}
        flags: {
            verbose: $verbose
            dry_run: $dry_run
            since: $since
            limit: $limit
        }
    }
    $in | run ../mycli/db/migrate.nu
}

# Load fixtures
@usage 'arg "[fixture]" help="Named fixture to load"'
export def "db seed" [
    fixture?: string,  # Named fixture to load
    --verbose (-v),    # Say more
] {
    let usage = {
        cmd: [db seed]
        args: {fixture: $fixture}
        flags: {verbose: $verbose}
    }
    $in | run ../mycli/db/seed.nu
}
