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

# The binary the wrappers run: its path in `$env.NUS_BINS`, a record or its NUON, when
# that names one, else the name, found on PATH.
def "nus bin" []: nothing -> string {
    let bins = $env.NUS_BINS? | default {}
    let bins = if ($bins | describe) == string { $bins | from nuon } else { $bins }
    $bins."rep"? | default rep
}

# Reports, with CLI-wide outputs and a CLI-wide selector
@usage 'flag "--format <format>" help="Output format" global=#true'
@usage 'output "text" default=#true help="Readable"'
@usage 'output ("record<ok: bool>")"json" framing="json" help="One object"'
@usage 'select "--format"'
@usage 'include file="included.kdl"'
export def main []: nothing -> record<ok: bool> {
    ^(nus bin) --format json ...(nus argv [] {}) | from json
}

# List reports
export def "rep list" [] {
    ^(nus bin) list --format json ...(nus argv [] {}) | from json
}

# Only text
@usage 'output "json" hide=#true'
export def "rep quiet" []: nothing -> string {
    ^(nus bin) quiet ...(nus argv [] {})
}
