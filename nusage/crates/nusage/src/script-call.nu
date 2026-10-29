# A script run as a call of it: the interpreter writes the script's value as NUON to the file
# named here and the call reads it back once the script is done, so what the script prints
# passes through as any command's does.
def "nusage call" [nusage: string, script: path, ...args: string]: any -> any {
    let file = $nu.temp-dir | path join $"nusage-(random uuid).nuon"
    $in | with-env {NUSAGE_OUTPUT_FILE: $file} { ^$nusage $script ...$args }
    let value = open --raw $file | from nuon
    rm $file
    $value
}
