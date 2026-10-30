# A script run as a call of it, by a program that runs it, nusage or mise: the interpreter
# running `script` writes its value as NUON to the file named here and the call reads it back
# once the program is done, so what the script prints passes through as any command's does.
# A task mise found up to date did not run, and has no value.
def "nusage call" [script: string, program: string, ...args: string]: any -> any {
    let file = $nu.temp-dir | path join $"nusage-(random uuid).nuon"
    $in | with-env {NUSAGE_OUTPUT_FILE: $file, NUSAGE_OUTPUT_SCRIPT: $script} { ^$program ...$args }
    if not ($file | path exists) {
        return
    }
    let value = open --raw $file | from nuon
    rm $file
    $value
}
