alias "attr usage" = echo

# A value as an argv word: a datetime in ISO 8601, anything else as Nushell writes it.
def "nusage word" []: any -> string {
    if ($in | describe --detailed | get type) == datetime {
        $in | format date "%+"
    } else {
        $in | into string
    }
}

# The argv for a wrapper's parameters: positionals in order, absent ones dropped, each
# preceded by the clause-scoped flags, then the other flags. A flag goes by its value: a
# switch once when on, a count that many times, a list once per item with its value, any
# other value once with its value; null and false add nothing.
def "nusage argv" [positionals: list<any>, flags: record, scoped: record = {}]: nothing -> list<string> {
    let scoped = $scoped | nusage flag-words
    let words = $positionals | compact | each { nusage word }
    let instances = if ($words | is-empty) {
        $scoped
    } else {
        $words | each {|word| $scoped ++ [$word] } | flatten
    }
    $instances ++ ($flags | nusage flag-words)
}

def "nusage flag-words" []: record -> list<string> {
    $in | transpose name value | each {|flag|
        match ($flag.value | describe --detailed | get type) {
            bool => (if $flag.value { [$flag.name] } else { [] })
            int => (0..<$flag.value | each { $flag.name })
            list => ($flag.value | each {|value| [$flag.name ($value | nusage word)] } | flatten)
            nothing => []
            _ => [$flag.name ($flag.value | nusage word)]
        }
    } | flatten
}

# A binary's output decoded as the module's closure decodes it. When that fails and the
# `nusage` this module was generated with is on PATH, the output is held to the schema the
# spec declares, line by line with `--lines`, so the error names what does not match it
# rather than what failed to convert; what failed to convert follows, as the inner error.
# The error is the decoding's own when the output matches or there is no `nusage` to ask,
# and the inner one under why the output could not be held to its schema when the check
# did not run.
def "nusage decoded" [
    text: string
    schema: string
    decode: closure
    --lines
]: nothing -> any {
    try {
        $text | do $decode
    } catch {|err|
        if (which nusage | is-empty) {
            error make $err
        }
        let file = mktemp --tmpdir nusage-XXXXXX.schema.json
        $schema | save --force $file
        let flags = if $lines { [--lines] } else { [] }
        let checked = $text | ^nusage validate $file - ...$flags | complete
        rm $file
        match $checked.exit_code {
            0 => { error make $err }
            1 => {
                $err | error make --unspanned {
                    msg: $"the output does not match its schema\n($checked.stderr | str trim)"
                }
            }
            _ => {
                $err | error make --unspanned {
                    msg: $"the output could not be held to its schema: nusage validate exited ($checked.exit_code)\n($checked.stderr | str trim)"
                }
            }
        }
    }
}

# Docker Compose
#
# Define and run multi-container applications with Docker
@usage 'version "5.6.1"'
@usage 'flag --dry-run help="Execute command in dry run mode" global=#true'
@usage 'flag --all-resources help="Include all resources, even those not used by services"'
@usage 'flag --ansi help="Control when to print ANSI control characters (\"never\"|\"always\"|\"auto\")" default=auto {
    arg <ANSI>
}'
@usage 'flag --compatibility help="Run compose in backward compatibility mode"'
@usage 'flag --env-file help="Specify an alternate environment file" {
    arg <ENV_FILE>
}'
@usage 'flag "-f --file" help="Compose configuration files" {
    arg <FILE>
}'
@usage r#'flag --insecure-registry help="Use insecure registry to pull Compose OCI artifacts. Doesn't apply to images" hide=#true {
    arg <INSECURE_REGISTRY>
}'#
@usage 'flag --no-ansi help="Do not print ANSI control characters (DEPRECATED)" hide=#true'
@usage 'flag --parallel help="Control max parallelism, -1 for unlimited" default="-1" {
    arg <PARALLEL>
}'
@usage 'flag --profile help="Specify a profile to enable" {
    arg <PROFILE>
}'
@usage 'flag --progress help="Set type of progress output (auto, tty, plain, json, quiet)" {
    arg <PROGRESS>
}'
@usage 'flag --project-directory help="Specify an alternate working directory\n(default: the path of the, first specified, Compose file)" {
    arg <PROJECT_DIRECTORY>
}'
@usage 'flag "-p --project-name" help="Project name" {
    arg <PROJECT_NAME>
}'
@usage 'flag --verbose help="Show more output" hide=#true'
@usage 'flag --workdir help="DEPRECATED! USE --project-directory INSTEAD.\nSpecify an alternate working directory\n(default: the path of the, first specified, Compose file)" hide=#true {
    arg <WORKDIR>
}'
export def main [
    --dry-run,                    # Execute command in dry run mode
    --all-resources,              # Include all resources, even those not used by services
    --ansi: string,               # Control when to print ANSI control characters ("never"|"always"|"auto")
    --compatibility,              # Run compose in backward compatibility mode
    --env-file: string,           # Specify an alternate environment file
    --file (-f): string,          # Compose configuration files
    --parallel: string,           # Control max parallelism, -1 for unlimited
    --profile: string,            # Specify a profile to enable
    --progress: string,           # Set type of progress output (auto, tty, plain, json, quiet)
    --project-directory: string,  # Specify an alternate working directory (default: the path of the, first specified, Compose file)
    --project-name (-p): string,  # Project name
]: nothing -> string {
    ^docker-compose ...(nusage argv [] {
        --dry-run: $dry_run
        --all-resources: $all_resources
        --ansi: $ansi
        --compatibility: $compatibility
        --env-file: $env_file
        --file: $file
        --parallel: $parallel
        --profile: $profile
        --progress: $progress
        --project-directory: $project_directory
        --project-name: $project_name
    })
}

# List running compose projects
@usage 'flag "-a --all" help="Show all stopped Compose projects"'
@usage 'flag --filter help="Filter output based on conditions provided" {
        arg <FILTER>
    }'
@usage 'flag --format help="Format the output. Values: [table | json]" default=table {
        arg <FORMAT>
    }'
@usage 'flag "-q --quiet" help="Only display project names" hide=#true'
@usage 'output "table" default=#true'
@usage 'select "--format"'
@usage 'output "json" framing="json" {
        schema #"""
{
  "type": "array",
  "items": {
    "type": "object",
    "required": ["Name", "Status", "ConfigFiles"],
    "properties": {
      "Name": {"type": "string"},
      "Status": {"type": "string"},
      "ConfigFiles": {"type": "string"}
    }
  }
}
"""#
    }'
export def "docker-compose ls" [
    --dry-run,         # Execute command in dry run mode
    --all (-a),        # Show all stopped Compose projects
    --filter: string,  # Filter output based on conditions provided
]: nothing -> table<Name: string, Status: string, ConfigFiles: string> {
    let text = ^docker-compose ls --format json ...(nusage argv [] {--dry-run: $dry_run, --all: $all, --filter: $filter})
    nusage decoded $text "{\"type\":\"array\",\"items\":{\"type\":\"object\",\"required\":[\"Name\",\"Status\",\"ConfigFiles\"],\"properties\":{\"Name\":{\"type\":\"string\"},\"Status\":{\"type\":\"string\"},\"ConfigFiles\":{\"type\":\"string\"}}}}" { from json }
}

# Show the Docker Compose version information
@usage 'flag "-f --format" help="Format the output. Values: [pretty | json]. (Default: pretty)" {
        arg <FORMAT>
    }'
@usage r#'flag "--short" help="Shows only Compose's version number" hide=#true'#
@usage 'output "pretty" default=#true'
@usage 'select "--format"'
@usage 'output "json" framing="json" {
        schema #"""
{
  "type": "object",
  "required": ["version"],
  "properties": {"version": {"type": "string"}}
}
"""#
    }'
export def "docker-compose version" [
    --dry-run,  # Execute command in dry run mode
]: nothing -> record<version: string> {
    let text = ^docker-compose version --format json ...(nusage argv [] {--dry-run: $dry_run})
    nusage decoded $text "{\"type\":\"object\",\"required\":[\"version\"],\"properties\":{\"version\":{\"type\":\"string\"}}}" { from json }
}
