alias "attr usage" = echo

def "complete plugin" [] {
    ^sh -c "echo \"plugin-1
plugin-2
plugin-3\"" | lines
}

def "complete exec task" [] {
    ^sh -c "echo \"build:Build it
test:Test it\"" | lines | parse "{value}:{description}"
}

# A demo CLI wrapped as externs
@usage 'flag "-v --verbose" help="Say more" global=#true count=#true'
@usage 'complete "plugin" run="echo \"plugin-1\nplugin-2\nplugin-3\""'
export extern --strict main [
    --verbose (-v),  # Say more
]

# Install a plugin
@usage 'arg "<plugin>" help="Plugin to install"'
@usage 'arg "[version]" help="Version to install" default="latest"'
@usage 'flag "-g --global" help="Install for every project"'
@usage 'flag "-d --dir <dir>" help="Install into this directory"'
export extern --strict install [
    plugin: string@"complete plugin",  # Plugin to install
    version?: string,                  # Version to install
    --verbose (-v),                    # Say more
    --global (-g),                     # Install for every project
    --dir (-d): path,                  # Install into this directory
]

# Run a task
@usage 'arg "<task>" help="Task to run"'
@usage 'arg "[args]..." help="Arguments for the task"'
@usage 'flag "-e --env <var>" help="Variable to set, repeatable" var=#true'
@usage 'complete "task" descriptions=#true run="echo \"build:Build it\ntest:Test it\""'
export extern --strict exec [
    task: string@"complete exec task",  # Task to run
    ...args: string,                    # Arguments for the task
    --verbose (-v),                     # Say more
    --env (-e): string,                 # Variable to set, repeatable
]

# Show status
@usage 'flag "--format <format>" help="Output format"'
@usage 'output "human" default=#true help="A readable report"'
@usage 'output ("record<ok: bool, tasks: list<string>>")"json" framing="json" help="One report object"'
@usage 'select "--format"'
@structured ["--format=json"] { from json }
export extern --strict status [
    --verbose (-v),                 # Say more
    --format: string@[human json],  # Output format
]: nothing -> record<ok: bool, tasks: list<string>>

# Stream events
@usage 'flag "--json" help="One JSON object per line"'
@usage 'output "text" default=#true'
@usage 'output ("table<at: datetime, kind: string>")"jsonl" framing="jsonl" select="--json"'
@structured [--json] { from json --objects }
export extern --strict events [
    --verbose (-v),  # Say more
    --json,          # One JSON object per line
]: nothing -> table<at: datetime, kind: string>
