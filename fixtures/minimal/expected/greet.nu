# Greet someone
export def main [
    name: string,  # Who to greet
    --loud (-l),   # Shout the greeting
    --times: int,  # How many times to greet
] {
    let usage = {
        cmd: []
        args: {name: $name}
        flags: {loud: $loud, times: $times}
    }
    $in | run ../script.nu
}
