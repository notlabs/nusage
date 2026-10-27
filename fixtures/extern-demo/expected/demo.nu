alias "attr usage" = echo

def "complete plugin" [] {
    ^sh -c "echo \"plugin-1
plugin-2
plugin-3\"" | lines
}

def "complete task" [] {
    ^sh -c "echo \"build:Build it
test:Test it\"" | lines | parse "{value}:{description}"
}

# A demo CLI wrapped as externs
@usage 'flag "-v --verbose" help="Say more" global=#true'
@usage 'complete "plugin" run="echo \"plugin-1\nplugin-2\nplugin-3\""'
@usage 'complete "task" descriptions=#true run="echo \"build:Build it\ntest:Test it\""'
export extern --strict demo [
    --verbose (-v),  # Say more
]

# Install a plugin
@usage 'arg "<plugin>" help="Plugin to install"'
@usage 'arg "[version]" help="Version to install" default="latest"'
@usage 'flag "-g --global" help="Install for every project"'
@usage 'flag "-d --dir <dir>" help="Install into this directory"'
export extern --strict "demo install" [
    plugin: string@"complete plugin",  # Plugin to install
    version?: string,                  # Version to install
    --verbose (-v),                    # Say more
    --global (-g),                     # Install for every project
    --dir (-d): path,                  # Install into this directory
]

# Run a task
@usage 'arg "<task>" help="Task to run"'
@usage 'arg "[args]..." help="Arguments for the task"'
export extern --strict "demo run" [
    task: string@"complete task",  # Task to run
    ...args: string,               # Arguments for the task
    --verbose (-v),                # Say more
]

# Show status
@usage 'flag "--format <format>" help="Output format"'
@usage 'output "human" default=#true help="A readable report"'
@usage 'output ("record<ok: bool, tasks: list<string>>")"json" framing="json" help="One report object"'
@usage 'select "--format"'
@structured ["--format=json"] { from json }
export extern --strict "demo status" [
    --verbose (-v),                 # Say more
    --format: string@[human json],  # Output format
]: nothing -> record<ok: bool, tasks: list<string>>

# Stream events
@usage 'flag "--json" help="One JSON object per line"'
@usage 'output "text" default=#true'
@usage 'output ("table<at: datetime, kind: string>")"jsonl" framing="jsonl" select="--json"'
@structured [--json] { from json --objects }
export extern --strict "demo events" [
    --verbose (-v),  # Say more
    --json,          # One JSON object per line
]: nothing -> table<at: datetime, kind: string>
