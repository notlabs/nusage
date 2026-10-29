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

# Calls the script beside it, by its path and through nusage and nu
@usage 'arg "<who>"'
@usage 'output ("record<path: record<greeting: string, times: int, at: datetime>, nusage: string, nu: int, at: string>")"nuon" default=#true'
export def main [
    who: string,
]: nothing -> record<path: record<greeting: string, times: int, at: datetime>, nusage: string, nu: int, at: string> {
    def "./callee.nu" [
        name: string,
        --loud (-l),
        --times: int,
    ]: nothing -> record<greeting: string, times: int, at: datetime> {
        const script = path self "../callee.nu"
        with-env {NUSAGE_OUTPUT: nuon} { ^nusage $script ...(nusage argv [$name] {--loud: $loud, --times: ([$times] | compact)}) } | from nuon
    }
    def "nu callee.nu" [
        name: string,
        --loud (-l),
        --times: int,
    ]: nothing -> record<greeting: string, times: int, at: datetime> {
        const script = path self "../callee.nu"
        with-env {NUSAGE_OUTPUT: nuon} { ^nusage $script ...(nusage argv [$name] {--loud: $loud, --times: ([$times] | compact)}) } | from nuon
    }
    def "nusage callee.nu" [
        name: string,
        --loud (-l),
        --times: int,
    ]: nothing -> record<greeting: string, times: int, at: datetime> {
        const script = path self "../callee.nu"
        with-env {NUSAGE_OUTPUT: nuon} { ^nusage $script ...(nusage argv [$name] {--loud: $loud, --times: ([$times] | compact)}) } | from nuon
    }
    let usage = {
        cmd: []
        args: {who: $who}
        flags: {}
    }
    $in | run "../script.nu"
}
