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

# A tool whose own spec, as `tool usage` prints it, declares no outputs or types
export def main []: nothing -> string {
    ^tool ...(nusage argv [] {})
}

# List things
@usage 'flag "-J --json" help="Print JSON"'
@usage 'arg ("string")"[name]" help="Only this one, by name"'
@usage 'output "text" default=#true'
@usage 'output ("table<name: string, size: filesize>")"json" framing="json" select="--json"'
export def "tool ls" [
    name?: string,  # Only this one, by name
]: nothing -> table<name: string, size: filesize> {
    ^tool ls --json ...(nusage argv [$name] {}) | ^nusage validate --passthrough --nu --source "tool ls stdout" --auto | from json | nusage validated | into filesize size
}
