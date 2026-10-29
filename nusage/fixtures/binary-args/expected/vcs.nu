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

# A version control system whose JSON is a template's, as jj's is
@usage 'flag "-R --repository <REPOSITORY>" help="Where to work" global=#true'
export def main [
    --repository (-R): string,  # Where to work
]: nothing -> string {
    ^vcs ...(nusage argv [] {--repository: $repository})
}

# Show revisions
@usage 'flag "-r --revision <REVSETS>" var=#true help="Which revisions to show"'
@usage 'flag "-T --template <TEMPLATE>" help="Render each revision with this"'
@usage 'flag "-G --no-graph" help="A flat list, not a graph"'
@usage 'flag "-n --limit" help="At most this many revisions" { arg (int)"<LIMIT>" }'
@usage 'arg "[FILESETS]..." help="Only revisions touching these"'
@usage 'output "text" default=#true'
@usage 'output "json" framing="jsonl" {
        schema #"{"type": "object", "required": ["commit_id", "author"], "properties": {"commit_id": {"type": "string"}, "author": {"type": "object", "required": ["name", "timestamp"], "properties": {"name": {"type": "string"}, "timestamp": {"type": "string", "format": "date-time"}}}}}"#
    }'
export def "vcs log" [
    ...filesets: string,            # Only revisions touching these
    --repository (-R): string,      # Where to work
    --revision (-r): list<string>,  # Which revisions to show
    --limit (-n): int,              # At most this many revisions
]: nothing -> table<commit_id: string, author: record<name: string, timestamp: datetime>> {
    let text = ^vcs log --no-graph --template "json(self) ++ \"\\n\"" ...(nusage argv [...$filesets] {--repository: $repository, --revision: $revision, --limit: ([$limit] | compact)})
    nusage decoded $text "{\"type\":\"object\",\"required\":[\"commit_id\",\"author\"],\"properties\":{\"commit_id\":{\"type\":\"string\"},\"author\":{\"type\":\"object\",\"required\":[\"name\",\"timestamp\"],\"properties\":{\"name\":{\"type\":\"string\"},\"timestamp\":{\"type\":\"string\",\"format\":\"date-time\"}}}}}" { from json --objects | into datetime author.timestamp } --lines
}

# Show how a change evolved
@usage 'flag "-T --template <TEMPLATE>" help="Render each entry with this"'
@usage 'flag "-G --no-graph" help="A flat list, not a graph"'
@usage 'output "json" framing="jsonl" {
        schema #"{"type": "object", "required": ["commit_id", "operation"], "properties": {"commit_id": {"type": "string"}, "operation": {"anyOf": [{"type": "object", "required": ["time"], "properties": {"time": {"type": "object", "required": ["start"], "properties": {"start": {"type": "string", "format": "date-time"}}}}}, {"type": "null"}]}}}"#
    }'
export def "vcs evolog" [
    --repository (-R): string,  # Where to work
]: nothing -> table<commit_id: string, operation: oneof<record<time: record<start: datetime>>, nothing>> {
    let text = ^vcs evolog --no-graph --template "json(self) ++ \"\\n\"" ...(nusage argv [] {--repository: $repository})
    nusage decoded $text "{\"type\":\"object\",\"required\":[\"commit_id\",\"operation\"],\"properties\":{\"commit_id\":{\"type\":\"string\"},\"operation\":{\"anyOf\":[{\"type\":\"object\",\"required\":[\"time\"],\"properties\":{\"time\":{\"type\":\"object\",\"required\":[\"start\"],\"properties\":{\"start\":{\"type\":\"string\",\"format\":\"date-time\"}}}}},{\"type\":\"null\"}]}}}" { from json --objects | update operation {|row| if $row.operation == null { null } else { $row.operation | into datetime time.start } } } --lines
}
