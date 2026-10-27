# Manage a project
export def main [
    --verbose (-v),  # Say more
] {
    let usage = {
        cmd: []
        args: {}
        flags: {verbose: $verbose}
    }
    $in | do { source ../mycli/mod.nu }
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
    $in | do { source ../mycli/db/mod.nu }
}

# Run migrations
export def "db migrate" [
    target: string@[dev staging prod],  # Target environment
    --verbose (-v),                     # Say more
    --dry-run,                          # Plan without applying
] {
    let usage = {
        cmd: [db migrate]
        args: {target: $target}
        flags: {verbose: $verbose, dry_run: $dry_run}
    }
    $in | do { source ../mycli/db/migrate.nu }
}

# Load fixtures
export def "db seed" [
    fixture?: string,  # Named fixture to load
    --verbose (-v),    # Say more
] {
    let usage = {
        cmd: [db seed]
        args: {fixture: $fixture}
        flags: {verbose: $verbose}
    }
    $in | do { source ../mycli/db/seed.nu }
}
