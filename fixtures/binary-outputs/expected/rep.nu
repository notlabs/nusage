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

# Reports, with CLI-wide outputs and a CLI-wide selector
@usage 'flag "--format <format>" help="Output format" global=#true'
@usage 'output "text" default=#true help="Readable"'
@usage 'output ("record<ok: bool>")"json" framing="json" help="One object"'
@usage 'select "--format"'
@usage 'include file="included.kdl"'
export def main [
    --format: string@[text json],  # Output format
]: nothing -> oneof<string, record<ok: bool>> {
    let output = $format | default "text"
    ^rep ...(nusage argv [] {--format: $format}) | nusage decode $output {
        json: { from json }
    }
}

# List reports
export def "rep list" [
    --format: string@[text json],  # Output format
] {
    let output = $format | default "text"
    ^rep list ...(nusage argv [] {--format: $format}) | nusage decode $output {
        json: { from json }
    }
}

# Only text
@usage 'output "json" hide=#true'
export def "rep quiet" [
    --format: string@[text],  # Output format
]: nothing -> string {
    ^rep quiet ...(nusage argv [] {--format: $format})
}
