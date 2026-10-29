# A binary's output decoded as the module's closure decodes it. When that fails and the
# `nusage` this module was generated with is on PATH, the output is held to the schema the
# spec declares first, so the error names what does not match it rather than what failed
# to convert.
def "nusage decoded" [text: string, schema: string, decode: closure]: nothing -> any {
    try {
        $text | do $decode
    } catch {|err|
        if (which nusage | is-empty) {
            error make --unspanned {msg: $err.msg}
        }
        let file = mktemp --tmpdir nusage-XXXXXX.schema.json
        $schema | save --force $file
        let checked = $text | ^nusage validate $file - | complete
        rm $file
        if $checked.exit_code == 0 {
            error make --unspanned {msg: $err.msg}
        }
        error make --unspanned {
            msg: $"the output does not match its schema\n($checked.stderr | str trim)"
        }
    }
}
