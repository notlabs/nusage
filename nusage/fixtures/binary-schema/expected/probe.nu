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

# A CLI whose outputs declare JSON Schemas
export def main []: nothing -> string {
    ^probe ...(nusage argv [] {})
}

# Show status
@usage 'flag "--json" help="As JSON"'
@usage 'output "text" default=#true'
@usage 'output "json" framing="json" select="--json" {
        schema #"""
{
  "type": "object",
  "required": ["ok", "took", "at", "size"],
  "properties": {
    "ok": {"type": "boolean"},
    "took": {"type": "integer", "x-nu": {"type": "duration", "unit": "ms"}},
    "at": {"type": "string", "format": "date-time"},
    "size": {"type": "integer", "x-nu": {"type": "filesize", "unit": "kB"}},
    "note": {"type": "string"},
    "seen": {"type": "integer", "x-nu": {"type": "datetime", "unit": "sec"}}
  }
}
"""#
    }'
export def "probe status" []: nothing -> record<ok: bool, took: duration, at: datetime, size: filesize, note: oneof<string, nothing>, seen: oneof<datetime, nothing>> {
    ^probe status --json ...(nusage argv [] {}) | from json | default null note | default null seen | update took {|row| $row.took | into duration --unit ms } | into datetime at | update size {|row| $row.size * 1kB } | update seen {|row| if $row.seen == null { null } else { (1970-01-01T00:00:00Z) + ($row.seen | into duration --unit sec) } }
}

# Stream events
@usage 'flag "--json" help="One JSON object per line"'
@usage 'output "text" default=#true'
@usage 'output "jsonl" framing="jsonl" select="--json" {
        schema file="events.schema.json"
    }'
export def "probe events" []: nothing -> table<at: datetime, kind: string, detail: oneof<string, nothing>> {
    ^probe events --json ...(nusage argv [] {}) | from json --objects | default null detail | update at {|row| (1970-01-01T00:00:00Z) + ($row.at | into duration --unit sec) }
}

# Describe the project
@usage 'output "json" framing="json" default=#true {
        schema file="report.schema.json"
    }'
export def "probe report" []: nothing -> record<name: string, dependencies: table<name: string, version: string, optional: oneof<bool, nothing>>, meta: record<built: datetime, took: oneof<duration, nothing>>, tags: list<string>, icon: binary, score: oneof<float, nothing>> {
    ^probe report ...(nusage argv [] {}) | from json | update dependencies { default null optional } | update meta { default null took } | default null score | into datetime meta.built | update meta.took {|row| if $row.meta.took == null { null } else { $row.meta.took | into duration --unit sec } } | update icon {|row| $row.icon | decode base64 }
}
