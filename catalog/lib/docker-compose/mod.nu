alias "attr usage" = echo

# A value as an argv word: a datetime in ISO 8601, anything else as Nushell writes it.
def "nus word" []: any -> string {
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
def "nus argv" [positionals: list<any>, flags: record, scoped: record = {}]: nothing -> list<string> {
    let scoped = $scoped | nus flag-words
    let words = $positionals | compact | each { nus word }
    let instances = if ($words | is-empty) {
        $scoped
    } else {
        $words | each {|word| $scoped ++ [$word] } | flatten
    }
    $instances ++ ($flags | nus flag-words)
}

def "nus flag-words" []: record -> list<string> {
    $in | transpose name value | each {|flag|
        match ($flag.value | describe --detailed | get type) {
            bool => (if $flag.value { [$flag.name] } else { [] })
            int => (0..<$flag.value | each { $flag.name })
            list => ($flag.value | each {|value| [$flag.name ($value | nus word)] } | flatten)
            nothing => []
            _ => [$flag.name ($flag.value | nus word)]
        }
    } | flatten
}

# A binary's output decoded as the module's closure decodes it. When that fails and the
# `nus` this module was generated with is on PATH, the output is held to the schema the
# spec declares, line by line with `--lines`, so the error names what does not match it
# rather than what failed to convert; what failed to convert follows, as the inner error.
# The error is the decoding's own when the output matches or there is no `nus` to ask,
# and the inner one under why the output could not be held to its schema when the check
# did not run.
def "nus decoded" [
    text: string
    schema: string
    decode: closure
    --lines
]: nothing -> any {
    try {
        $text | do $decode
    } catch {|err|
        if (which nus | is-empty) {
            error make $err
        }
        let file = mktemp --tmpdir nusage-XXXXXX.schema.json
        $schema | save --force $file
        let flags = if $lines { [--lines] } else { [] }
        let checked = $text | ^nus validate $file - ...$flags | complete
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
                    msg: $"the output could not be held to its schema: nus validate exited ($checked.exit_code)\n($checked.stderr | str trim)"
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
    ^docker-compose ...(nus argv [] {
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
    let text = ^docker-compose ls --format json ...(nus argv [] {--dry-run: $dry_run, --all: $all, --filter: $filter})
    nus decoded $text "{\"type\":\"array\",\"items\":{\"type\":\"object\",\"required\":[\"Name\",\"Status\",\"ConfigFiles\"],\"properties\":{\"Name\":{\"type\":\"string\"},\"Status\":{\"type\":\"string\"},\"ConfigFiles\":{\"type\":\"string\"}}}}" { from json }
}

# List containers
@usage 'flag "-a --all" help="Show all stopped containers (including those created by the run command)"'
@usage 'flag --filter help="Filter services by a property (supported filters: status)" {
        arg <FILTER>
    }'
@usage r#'flag "--format" help="Format output using a custom template:\n'table':            Print output in table format with column headers (default)\n'table TEMPLATE':   Print output in table format using the given Go template\n'json':             Print in JSON format\n'TEMPLATE':         Print output using the given Go template.\nRefer to https://docs.docker.com/go/formatting/ for more information about formatting output with templates" hide=#true {
        arg <FORMAT>
    }'#
@usage r#'flag "--no-trunc" help="Don't truncate output" hide=#true'#
@usage 'flag "--orphans" help="Include orphaned services (not declared by project)" default="true" hide=#true'
@usage 'flag "-q --quiet" help="Only display IDs" hide=#true'
@usage 'flag "--services" help="Display services" hide=#true'
@usage 'flag "--status" help="Filter services by status. Values: [paused | restarting | removing | running | dead | created | exited]" var=#true {
        arg <STATUS>
    }'
@usage 'arg "[SERVICE...]" required=#false'
@usage 'output "json" framing="jsonl" { schema "{\n  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",\n  \"title\": \"Docker Compose v5.6.1 ps JSON line\",\n  \"description\": \"ContainerContext accessors, with --format json --no-trunc. Display strings are retained as strings; Publishers may be null.\",\n  \"type\": \"object\",\n  \"required\": [\n    \"Command\",\n    \"CreatedAt\",\n    \"Engine\",\n    \"ExitCode\",\n    \"Health\",\n    \"ID\",\n    \"Image\",\n    \"Labels\",\n    \"LocalVolumes\",\n    \"Mounts\",\n    \"Name\",\n    \"Names\",\n    \"Networks\",\n    \"Ports\",\n    \"Project\",\n    \"Publishers\",\n    \"RunningFor\",\n    \"Service\",\n    \"Size\",\n    \"State\",\n    \"Status\"\n  ],\n  \"properties\": {\n    \"Command\": {\n      \"type\": \"string\"\n    },\n    \"CreatedAt\": {\n      \"type\": \"string\"\n    },\n    \"Engine\": {\n      \"type\": \"string\"\n    },\n    \"ExitCode\": {\n      \"type\": \"integer\"\n    },\n    \"Health\": {\n      \"type\": \"string\"\n    },\n    \"ID\": {\n      \"type\": \"string\"\n    },\n    \"Image\": {\n      \"type\": \"string\"\n    },\n    \"Labels\": {\n      \"type\": \"string\"\n    },\n    \"LocalVolumes\": {\n      \"type\": \"string\"\n    },\n    \"Mounts\": {\n      \"type\": \"string\"\n    },\n    \"Name\": {\n      \"type\": \"string\"\n    },\n    \"Names\": {\n      \"type\": \"string\"\n    },\n    \"Networks\": {\n      \"type\": \"string\"\n    },\n    \"Ports\": {\n      \"type\": \"string\"\n    },\n    \"Project\": {\n      \"type\": \"string\"\n    },\n    \"Publishers\": {\n      \"type\": [\n        \"array\",\n        \"null\"\n      ],\n      \"items\": {\n        \"type\": \"object\",\n        \"required\": [\n          \"URL\",\n          \"TargetPort\",\n          \"PublishedPort\",\n          \"Protocol\"\n        ],\n        \"properties\": {\n          \"URL\": {\n            \"type\": \"string\"\n          },\n          \"TargetPort\": {\n            \"type\": \"integer\"\n          },\n          \"PublishedPort\": {\n            \"type\": \"integer\"\n          },\n          \"Protocol\": {\n            \"type\": \"string\"\n          }\n        }\n      }\n    },\n    \"RunningFor\": {\n      \"type\": \"string\"\n    },\n    \"Service\": {\n      \"type\": \"string\"\n    },\n    \"Size\": {\n      \"type\": \"string\"\n    },\n    \"State\": {\n      \"type\": \"string\"\n    },\n    \"Status\": {\n      \"type\": \"string\"\n    }\n  }\n}\n" }'
export def "docker-compose ps" [
    ...service: string,
    --dry-run,               # Execute command in dry run mode
    --all (-a),              # Show all stopped containers (including those created by the run command)
    --filter: string,        # Filter services by a property (supported filters: status)
    --status: list<string>,  # Filter services by status. Values: [paused | restarting | removing | running | dead | created | exited]
]: nothing -> table<Command: string, CreatedAt: string, Engine: string, ExitCode: int, Health: string, ID: string, Image: string, Labels: string, LocalVolumes: string, Mounts: string, Name: string, Names: string, Networks: string, Ports: string, Project: string, Publishers: oneof<table<URL: string, TargetPort: int, PublishedPort: int, Protocol: string>, nothing>, RunningFor: string, Service: string, Size: string, State: string, Status: string> {
    let text = ^docker-compose ps --format json --no-trunc ...(nus argv [...$service] {
        --dry-run: $dry_run
        --all: $all
        --filter: $filter
        --status: $status
    })
    nus decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"title\":\"Docker Compose v5.6.1 ps JSON line\",\"description\":\"ContainerContext accessors, with --format json --no-trunc. Display strings are retained as strings; Publishers may be null.\",\"type\":\"object\",\"required\":[\"Command\",\"CreatedAt\",\"Engine\",\"ExitCode\",\"Health\",\"ID\",\"Image\",\"Labels\",\"LocalVolumes\",\"Mounts\",\"Name\",\"Names\",\"Networks\",\"Ports\",\"Project\",\"Publishers\",\"RunningFor\",\"Service\",\"Size\",\"State\",\"Status\"],\"properties\":{\"Command\":{\"type\":\"string\"},\"CreatedAt\":{\"type\":\"string\"},\"Engine\":{\"type\":\"string\"},\"ExitCode\":{\"type\":\"integer\"},\"Health\":{\"type\":\"string\"},\"ID\":{\"type\":\"string\"},\"Image\":{\"type\":\"string\"},\"Labels\":{\"type\":\"string\"},\"LocalVolumes\":{\"type\":\"string\"},\"Mounts\":{\"type\":\"string\"},\"Name\":{\"type\":\"string\"},\"Names\":{\"type\":\"string\"},\"Networks\":{\"type\":\"string\"},\"Ports\":{\"type\":\"string\"},\"Project\":{\"type\":\"string\"},\"Publishers\":{\"type\":[\"array\",\"null\"],\"items\":{\"type\":\"object\",\"required\":[\"URL\",\"TargetPort\",\"PublishedPort\",\"Protocol\"],\"properties\":{\"URL\":{\"type\":\"string\"},\"TargetPort\":{\"type\":\"integer\"},\"PublishedPort\":{\"type\":\"integer\"},\"Protocol\":{\"type\":\"string\"}}}},\"RunningFor\":{\"type\":\"string\"},\"Service\":{\"type\":\"string\"},\"Size\":{\"type\":\"string\"},\"State\":{\"type\":\"string\"},\"Status\":{\"type\":\"string\"}}}" { from json --objects } --lines
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
    let text = ^docker-compose version --format json ...(nus argv [] {--dry-run: $dry_run})
    nus decoded $text "{\"type\":\"object\",\"required\":[\"version\"],\"properties\":{\"version\":{\"type\":\"string\"}}}" { from json }
}
