alias "attr usage" = echo

# The validator's private Result envelope preserves failures across Nu's external-stream
# boundary. Only successful values reach the caller or the schema's conversions.
def "nusage validated" []: record -> any {
    let result = $in
    if "Err" in $result {
        let errors = $result.Err | each {|d|
            {
                code: $d.code
                msg: $d.message
                help: $"($d.path):($d.line? | default ''):($d.instance_path? | default '') ($d.schema_uri? | default '')"
            }
        }
        error make ($errors | first | merge {inner: ($errors | skip 1)})
    } else {
        $result.Ok
    }
}

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
@usage 'arg "[FILESETS]..." help="Only revisions touching these"'
@usage 'output "text" default=#true'
@usage 'output "json" framing="jsonl" {
        schema #"{"type": "object", "required": ["commit_id", "author"], "properties": {"commit_id": {"type": "string"}, "author": {"type": "object", "required": ["name", "timestamp"], "properties": {"name": {"type": "string"}, "timestamp": {"type": "string", "format": "date-time"}}}}}"#
    }'
export def "vcs log" [
    ...filesets: string,            # Only revisions touching these
    --repository (-R): string,      # Where to work
    --revision (-r): list<string>,  # Which revisions to show
]: nothing -> table<commit_id: string, author: record<name: string, timestamp: datetime>> {
    ^vcs log --no-graph --template "json(self) ++ \"\\n\"" ...(nusage argv [...$filesets] {--repository: $repository, --revision: $revision}) | ^nusage validate --passthrough --nu --source "vcs log stdout" --schema-json "{\"type\":\"object\",\"required\":[\"commit_id\",\"author\"],\"properties\":{\"commit_id\":{\"type\":\"string\"},\"author\":{\"type\":\"object\",\"required\":[\"name\",\"timestamp\"],\"properties\":{\"name\":{\"type\":\"string\"},\"timestamp\":{\"type\":\"string\",\"format\":\"date-time\"}}}}}" --jsonl | from json --objects | each --keep-empty { nusage validated } | into datetime author.timestamp
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
    ^vcs evolog --no-graph --template "json(self) ++ \"\\n\"" ...(nusage argv [] {--repository: $repository}) | ^nusage validate --passthrough --nu --source "vcs evolog stdout" --schema-json "{\"type\":\"object\",\"required\":[\"commit_id\",\"operation\"],\"properties\":{\"commit_id\":{\"type\":\"string\"},\"operation\":{\"anyOf\":[{\"type\":\"object\",\"required\":[\"time\"],\"properties\":{\"time\":{\"type\":\"object\",\"required\":[\"start\"],\"properties\":{\"start\":{\"type\":\"string\",\"format\":\"date-time\"}}}}},{\"type\":\"null\"}]}}}" --jsonl | from json --objects | each --keep-empty { nusage validated } | update operation {|row| if $row.operation == null { null } else { $row.operation | into datetime time.start } }
}
