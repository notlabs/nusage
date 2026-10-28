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

# A tool whose own spec, as `tool usage` prints it, declares no outputs or types
export def main [] {
    ^tool ...(nusage argv [] {})
}

# List things
@usage 'flag "-J --json" help="Print JSON"'
@usage 'arg ("string")"[name]" help="Only this one, by name"'
@usage 'output "text" default=#true'
@usage 'output ("table<name: string, size: filesize>")"json" framing="json" select="--json"'
export def "tool ls" [
    name?: string,  # Only this one, by name
    --json (-J),    # Print JSON
]: nothing -> oneof<string, table<name: string, size: filesize>> {
    let output = if $json { "json" } else { "text" }
    ^tool ls ...(nusage argv [$name] {--json: $json}) | nusage decode $output {
        json: { from json | into filesize size }
    }
}
