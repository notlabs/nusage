alias "attr usage" = echo

# A value as an argv word: a datetime in ISO 8601, anything else as Nushell writes it.
def "nusage word" []: any -> string {
    if ($in | describe --detailed | get type) == datetime {
        $in | format date "%+"
    } else {
        $in | into string
    }
}

# The argv for a wrapper's parameters: positionals in order, absent ones dropped, then each
# flag by its value: a switch once when on, a count that many times, a list once per item
# with its value, any other value once with its value; null and false add nothing.
def "nusage argv" [positionals: list<any>, flags: record]: nothing -> list<string> {
    let flags = $flags | transpose name value | each {|flag|
        match ($flag.value | describe --detailed | get type) {
            bool => (if $flag.value { [$flag.name] } else { [] })
            int => (0..<$flag.value | each { $flag.name })
            list => ($flag.value | each {|value| [$flag.name ($value | nusage word)] } | flatten)
            nothing => []
            _ => [$flag.name ($flag.value | nusage word)]
        }
    } | flatten
    ($positionals | compact | each { nusage word }) ++ $flags
}

# A wrapper's output: decoded by the decoder named by the output the call selected, when
# there is one for it, else as the binary printed it.
def "nusage decode" [output: any, decoders: record] {
    if ($decoders | get -o $output) == null {
        $in
    } else {
        do ($decoders | get $output)
    }
}

def "complete plugin" [] {
    ^sh -c "echo \"plugin-1
plugin-2
plugin-3\"" | lines
}

def "complete demo run task" [] {
    ^sh -c "echo \"build:Build it
test:Test it\"" | lines | parse "{value}:{description}"
}

# A demo CLI
@usage 'flag "-v --verbose" help="Say more" global=#true count=#true'
@usage 'complete "plugin" run="echo \"plugin-1\nplugin-2\nplugin-3\""'
export def main [
    --verbose (-v): int,  # Say more
] {
    ^demo ...(nusage argv [] {--verbose: $verbose})
}

# Install a plugin
@usage 'arg "<plugin>" help="Plugin to install"'
@usage 'arg "[version]" help="Version to install" default="latest"'
@usage 'flag "-g --global" help="Install for every project"'
@usage 'flag "-d --dir <dir>" help="Install into this directory"'
export def "demo install" [
    plugin: string@"complete plugin",  # Plugin to install
    version?: string,                  # Version to install
    --verbose (-v): int,               # Say more
    --global (-g),                     # Install for every project
    --dir (-d): path,                  # Install into this directory
] {
    ^demo install ...(nusage argv [$plugin $version] {--verbose: $verbose, --global: $global, --dir: $dir})
}

# Run a task
@usage 'arg "<task>" help="Task to run"'
@usage 'arg "[args]..." help="Arguments for the task"'
@usage 'flag "-e --set <var>" help="Variable to set, repeatable" var=#true'
@usage 'complete "task" descriptions=#true run="echo \"build:Build it\ntest:Test it\""'
export def "demo run" [
    task: string@"complete demo run task",  # Task to run
    ...args: string,                        # Arguments for the task
    --verbose (-v): int,                    # Say more
    --set (-e): list<string>,               # Variable to set, repeatable
] {
    ^demo run ...(nusage argv [$task ...$args] {--verbose: $verbose, --set: $set})
}

# Show status
@usage 'flag "--format <format>" help="Output format"'
@usage 'output "human" default=#true help="A readable report"'
@usage 'output ("record<ok: bool, tasks: list<string>>")"json" framing="json" help="One report object"'
@usage 'select "--format"'
export def "demo status" [
    --verbose (-v): int,            # Say more
    --format: string@[human json],  # Output format
]: nothing -> oneof<string, record<ok: bool, tasks: list<string>>> {
    let output = $format | default "human"
    ^demo status ...(nusage argv [] {--verbose: $verbose, --format: $format}) | nusage decode $output {
        json: { from json }
    }
}

# Stream events
@usage 'flag "--json" help="One JSON object per line"'
@usage 'output "text" default=#true'
@usage 'output ("table<at: datetime, kind: string>")"jsonl" framing="jsonl" select="--json"'
export def "demo events" [
    --verbose (-v): int,  # Say more
    --json,               # One JSON object per line
]: nothing -> oneof<string, table<at: datetime, kind: string>> {
    let output = if $json { "jsonl" } else { "text" }
    ^demo events ...(nusage argv [] {--verbose: $verbose, --json: $json}) | nusage decode $output {
        jsonl: { from json --objects | into datetime at }
    }
}
