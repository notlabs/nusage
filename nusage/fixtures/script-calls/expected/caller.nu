alias "attr usage" = echo

# Calls the script beside it, by its path and through nusage and nu
@usage 'arg "<who>"'
@usage 'output ("record<path: record<greeting: string, times: int, at: datetime>, nus: string, nu: int, at: string>")"nuon" default=#true'
export def main [
    who: string,
]: nothing -> record<path: record<greeting: string, times: int, at: datetime>, nus: string, nu: int, at: string> {
    def "./callee.nu" [
        name: string,
        --loud (-l),
        --times: int = 1,
        --chatty,          # Say what it is doing, as a script does
    ]: nothing -> record<greeting: string, times: int, at: datetime> {
        let usage = {
            cmd: []
            args: {name: $name}
            flags: {loud: $loud, times: $times, chatty: $chatty}
        }
        $in | run "../callee.nu"
    }
    def "nu callee.nu" [
        name: string,
        --loud (-l),
        --times: int = 1,
        --chatty,          # Say what it is doing, as a script does
    ]: nothing -> record<greeting: string, times: int, at: datetime> {
        let usage = {
            cmd: []
            args: {name: $name}
            flags: {loud: $loud, times: $times, chatty: $chatty}
        }
        $in | run "../callee.nu"
    }
    def "nus callee.nu" [
        name: string,
        --loud (-l),
        --times: int = 1,
        --chatty,          # Say what it is doing, as a script does
    ]: nothing -> record<greeting: string, times: int, at: datetime> {
        let usage = {
            cmd: []
            args: {name: $name}
            flags: {loud: $loud, times: $times, chatty: $chatty}
        }
        $in | run "../callee.nu"
    }
    let usage = {
        cmd: []
        args: {who: $who}
        flags: {}
    }
    $in | run "../script.nu"
}
