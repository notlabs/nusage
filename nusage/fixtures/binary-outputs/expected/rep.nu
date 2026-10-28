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

# Reports, with CLI-wide outputs and a CLI-wide selector
@usage 'flag "--format <format>" help="Output format" global=#true'
@usage 'output "text" default=#true help="Readable"'
@usage 'output ("record<ok: bool>")"json" framing="json" help="One object"'
@usage 'select "--format"'
@usage 'include file="included.kdl"'
export def main []: nothing -> record<ok: bool> {
    ^rep --format json ...(nusage argv [] {}) | from json
}

# List reports
export def "rep list" [] {
    ^rep list --format json ...(nusage argv [] {}) | from json
}

# Only text
@usage 'output "json" hide=#true'
export def "rep quiet" []: nothing -> string {
    ^rep quiet ...(nusage argv [] {})
}
