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

# A tool with text outputs no reader covers: each declares the pipeline that decodes it
export def main []: nothing -> string {
    ^wc ...(nusage argv [] {})
}

# List things, one per line as `name size`
@usage 'output ("table<name: string, size: filesize>")"text" default=#true {
    decode "lines | parse \"{name} {size}\""
}'
export def "wc ls" []: nothing -> table<name: string, size: filesize> {
    ^wc ls ...(nusage argv [] {}) | lines | parse "{name} {size}" | into filesize size
}

# Disk use, one per line as `size path`
@usage 'output ("table<size: filesize, path: string>")"text" default=#true {
        decode "detect columns --no-headers | rename size path"
    }'
export def "wc du" []: nothing -> table<size: filesize, path: string> {
    ^wc du ...(nusage argv [] {}) | detect columns --no-headers | rename size path | into filesize size
}
