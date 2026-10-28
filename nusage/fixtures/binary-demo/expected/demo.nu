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

# Completions from usage's own completer, against the spec this module was generated
# from, with the words typed so far. Nothing when the `usage` CLI is not installed.
def "nusage complete" [place: record] {
    const spec = (path self | path dirname | path join "../demo.usage.kdl")
    if (which usage | is-empty) {
        return []
    }
    let name = $place.command | first
    let command = if $name == "main" { [demo] } else { $name | split row " " }
    let words = $place.command | skip 1
    (^usage complete-word -f $spec --shell nu -- ...$command ...$words | complete).stdout
    | lines
    | each {|line| $line | split column "	" value description | into record }
}

# A demo CLI
@usage 'flag "-v --verbose" help="Say more" global=#true count=#true'
@usage 'complete "plugin" run="echo \"plugin-1\nplugin-2\nplugin-3\""'
export def main [
    --verbose (-v): int,  # Say more
]: nothing -> string {
    ^demo ...(nusage argv [] {--verbose: $verbose})
}

# Install a plugin
@usage 'arg "<plugin>" help="Plugin to install"'
@usage 'arg "[version]" help="Version to install" default="latest"'
@usage 'flag "-g --global" help="Install for every project"'
@usage 'flag "-d --dir <dir>" help="Install into this directory"'
@usage 'flag "--env <env>" help="Environment to install into"'
export def "demo install" [
    plugin: string@"nusage complete",  # Plugin to install
    version?: string,                  # Version to install
    --verbose (-v): int,               # Say more
    --global (-g),                     # Install for every project
    --dir (-d): path,                  # Install into this directory
    --env_: string,                    # Environment to install into
]: nothing -> string {
    ^demo install ...(nusage argv [$plugin $version] {
        --verbose: $verbose
        --global: $global
        --dir: $dir
        --env: $env_
    })
}

# Run a task
@usage 'arg "<task>" help="Task to run"'
@usage 'arg "[args]..." help="Arguments for the task"'
@usage 'flag "-e --set <var>" help="Variable to set, repeatable" var=#true'
@usage 'complete "task" descriptions=#true run="echo \"build:Build it\ntest:Test it\""'
export def "demo run" [
    task: string@"nusage complete",  # Task to run
    ...args: string,                 # Arguments for the task
    --verbose (-v): int,             # Say more
    --set (-e): list<string>,        # Variable to set, repeatable
]: nothing -> string {
    ^demo run ...(nusage argv [$task ...$args] {--verbose: $verbose, --set: $set})
}

# Show status
@usage 'flag "--format <format>" help="Output format"'
@usage 'output "human" default=#true help="A readable report"'
@usage 'output ("record<ok: bool, tasks: list<string>>")"json" framing="json" help="One report object"'
@usage 'select "--format"'
export def "demo status" [
    --verbose (-v): int,  # Say more
]: nothing -> record<ok: bool, tasks: list<string>> {
    ^demo status --format json ...(nusage argv [] {--verbose: $verbose}) | from json
}

# Stream events
@usage 'flag "--json" help="One JSON object per line"'
@usage 'output "text" default=#true'
@usage 'output ("table<at: datetime, kind: string>")"jsonl" framing="jsonl" select="--json"'
export def "demo events" [
    --verbose (-v): int,  # Say more
]: nothing -> table<at: datetime, kind: string> {
    ^demo events --json ...(nusage argv [] {--verbose: $verbose}) | from json --objects | into datetime at
}

# Tag items
@usage 'clause "items" {
        flag "-l --label <label>" help="Label for the item that follows"
        arg "<item>" help="Item to tag"
    }'
export def "demo tag" [
    ...item: string,       # Item to tag
    --verbose (-v): int,   # Say more
    --label (-l): string,  # Label for the item that follows
]: nothing -> string {
    ^demo tag ...(nusage argv [...$item] {--verbose: $verbose} {--label: $label})
}
