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

# A script run as a call of it, by a program that runs it, nusage or mise: the interpreter
# running `script` writes its value as NUON to the file named here and the call reads it back
# once the program is done, so what the script prints passes through as any command's does.
# A task mise found up to date did not run, and has no value.
def "nus call" [script: string, program: string, ...args: string]: any -> any {
    let file = $nu.temp-dir | path join $"nusage-(random uuid).nuon"
    $in | with-env {NUS_OUTPUT_FILE: $file, NUS_OUTPUT_SCRIPT: $script} { ^$program ...$args }
    if not ($file | path exists) {
        return
    }
    let value = open --raw $file | from nuon
    rm $file
    $value
}

# Calls the script beside it, by its path and through nusage and nu
@usage 'arg "<who>"'
@usage 'output ("record<path: record<greeting: string, times: int, at: datetime>, nus: string, nu: int, at: string>")"nuon" default=#true'
export def main [
    who: string,
]: nothing -> record<path: record<greeting: string, times: int, at: datetime>, nus: string, nu: int, at: string> {
    def "./callee.nu" [
        name: string,
        --loud (-l),
        --times: int,
        --chatty,      # Say what it is doing, as a script does
    ]: nothing -> record<greeting: string, times: int, at: datetime> {
        const script = path self "../callee.nu"
        $in | nus call $script nus $script ...(nus argv [$name] {--loud: $loud, --times: ([$times] | compact), --chatty: $chatty})
    }
    def "nu callee.nu" [
        name: string,
        --loud (-l),
        --times: int,
        --chatty,      # Say what it is doing, as a script does
    ]: nothing -> record<greeting: string, times: int, at: datetime> {
        const script = path self "../callee.nu"
        $in | nus call $script nus $script ...(nus argv [$name] {--loud: $loud, --times: ([$times] | compact), --chatty: $chatty})
    }
    def "nus callee.nu" [
        name: string,
        --loud (-l),
        --times: int,
        --chatty,      # Say what it is doing, as a script does
    ]: nothing -> record<greeting: string, times: int, at: datetime> {
        const script = path self "../callee.nu"
        $in | nus call $script nus $script ...(nus argv [$name] {--loud: $loud, --times: ([$times] | compact), --chatty: $chatty})
    }
    let usage = {
        cmd: []
        args: {who: $who}
        flags: {}
    }
    $in | run "../script.nu"
}
