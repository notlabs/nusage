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
# spec declares, so the error names what does not match it rather than what failed to
# convert. The error is the decoding's own when the output matches, when there is no
# `nusage` to ask, or when the check did not run; then its help says why not.
def "nusage decoded" [text: string, schema: string, decode: closure]: nothing -> any {
    try {
        $text | do $decode
    } catch {|err|
        if (which nusage | is-empty) {
            error make $err
        }
        let file = mktemp --tmpdir nusage-XXXXXX.schema.json
        $schema | save --force $file
        let checked = $text | ^nusage validate $file - | complete
        rm $file
        match $checked.exit_code {
            0 => { error make $err }
            1 => {
                error make --unspanned {
                    msg: $"the output does not match its schema\n($checked.stderr | str trim)"
                }
            }
            _ => {
                let note = $"the output could not be held to its schema: nusage validate exited ($checked.exit_code)\n($checked.stderr | str trim)"
                let details = $err.details | reject url inner | update help {|d|
                    if ($d.help | is-empty) { $note } else { $"($d.help)\n\n($note)" }
                }
                let details = if ($details.code | is-empty) {
                    $details | reject code
                } else {
                    $details
                }
                if ($details.labels | is-empty) {
                    error make --unspanned ($details | reject labels)
                } else {
                    error make $details
                }
            }
        }
    }
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
    let text = ^probe status --json ...(nusage argv [] {})
    nusage decoded $text "{\"type\":\"object\",\"required\":[\"ok\",\"took\",\"at\",\"size\"],\"properties\":{\"ok\":{\"type\":\"boolean\"},\"took\":{\"type\":\"integer\",\"x-nu\":{\"type\":\"duration\",\"unit\":\"ms\"}},\"at\":{\"type\":\"string\",\"format\":\"date-time\"},\"size\":{\"type\":\"integer\",\"x-nu\":{\"type\":\"filesize\",\"unit\":\"kB\"}},\"note\":{\"type\":\"string\"},\"seen\":{\"type\":\"integer\",\"x-nu\":{\"type\":\"datetime\",\"unit\":\"sec\"}}}}" { from json | default null note | default null seen | update took {|row| $row.took | into duration --unit ms } | into datetime at | update size {|row| $row.size * 1kB } | update seen {|row| if $row.seen == null { null } else { (1970-01-01T00:00:00Z) + ($row.seen | into duration --unit sec) } } }
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
    let text = ^probe report ...(nusage argv [] {})
    nusage decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"$defs\":{\"dependency\":{\"type\":\"object\",\"required\":[\"name\",\"version\"],\"properties\":{\"name\":{\"type\":\"string\"},\"version\":{\"type\":\"string\"},\"optional\":{\"type\":\"boolean\"}}}},\"type\":\"object\",\"required\":[\"name\",\"dependencies\",\"meta\",\"tags\",\"icon\"],\"properties\":{\"name\":{\"type\":\"string\"},\"dependencies\":{\"type\":\"array\",\"items\":{\"$ref\":\"#/$defs/dependency\"}},\"meta\":{\"type\":\"object\",\"required\":[\"built\"],\"properties\":{\"built\":{\"type\":\"string\",\"format\":\"date-time\"},\"took\":{\"type\":\"number\",\"x-nu\":{\"type\":\"duration\",\"unit\":\"sec\"}}}},\"tags\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}},\"icon\":{\"type\":\"string\",\"contentEncoding\":\"base64\"},\"score\":{\"anyOf\":[{\"type\":\"number\"},{\"type\":\"null\"}]}}}" { from json | update dependencies { default null optional } | update meta { default null took } | default null score | into datetime meta.built | update meta.took {|row| if $row.meta.took == null { null } else { $row.meta.took | into duration --unit sec } } | update icon {|row| $row.icon | decode base64 } }
}

# Show the peer, when there is one
@usage 'output "json" framing="json" default=#true {
        schema #"""
{
  "oneOf": [
    {"type": "null"},
    {
      "type": "object",
      "required": ["host"],
      "properties": {
        "host": {"type": "string"},
        "port": {"type": "integer"},
        "since": {"type": "string", "format": "date-time"},
        "link": {
          "oneOf": [
            {"type": "null"},
            {"type": "object", "required": ["up"], "properties": {"up": {"type": "boolean"}, "latency": {"type": "integer", "x-nu": {"type": "duration", "unit": "ms"}}}}
          ]
        }
      }
    }
  ]
}
"""#
    }'
export def "probe peer" []: nothing -> oneof<nothing, record<host: string, port: oneof<int, nothing>, since: oneof<datetime, nothing>, link: oneof<nothing, record<up: bool, latency: oneof<duration, nothing>>>>> {
    let text = ^probe peer ...(nusage argv [] {})
    nusage decoded $text "{\"oneOf\":[{\"type\":\"null\"},{\"type\":\"object\",\"required\":[\"host\"],\"properties\":{\"host\":{\"type\":\"string\"},\"port\":{\"type\":\"integer\"},\"since\":{\"type\":\"string\",\"format\":\"date-time\"},\"link\":{\"oneOf\":[{\"type\":\"null\"},{\"type\":\"object\",\"required\":[\"up\"],\"properties\":{\"up\":{\"type\":\"boolean\"},\"latency\":{\"type\":\"integer\",\"x-nu\":{\"type\":\"duration\",\"unit\":\"ms\"}}}}]}}}]}" { from json | if $in == null { null } else { $in | default null port } | if $in == null { null } else { $in | default null since } | if $in == null { null } else { $in | default null link } | if $in == null { null } else { $in | update link {|row| if $row.link == null { null } else { $row.link | default null latency } } } | if $in == null { null } else { $in | update since {|row| if $row.since == null { null } else { $row.since | into datetime } } } | if $in == null { null } else { $in | update link {|row| if $row.link == null { null } else { $row.link | update latency {|row| if $row.latency == null { null } else { $row.latency | into duration --unit ms } } } } } }
}
