# A binary's output decoded as the module's closure decodes it. When that fails and the
# `nusage` this module was generated with is on PATH, the output is held to the schema the
# spec declares, so the error names what does not match it rather than what failed to
# convert; what failed to convert follows, as the inner error. The error is the decoding's
# own when the output matches or there is no `nusage` to ask, and the inner one under why
# the output could not be held to its schema when the check did not run.
def "nusage decoded" [text: string, schema: string, decode: closure]: nothing -> any {
    try {
        $text | do $decode
    } catch {|err|
        if (which nusage | is-empty) {
            error make $err
        }
        let file = mktemp --tmpdir nusage-XXXXXX.schema.json
        $schema | save --force $file
        let checked = $text | ^nusage validate $file - | complete
        rm $file
        match $checked.exit_code {
            0 => { error make $err }
            1 => {
                $err | error make --unspanned {
                    msg: $"the output does not match its schema\n($checked.stderr | str trim)"
                }
            }
            _ => {
                $err | error make --unspanned {
                    msg: $"the output could not be held to its schema: nusage validate exited ($checked.exit_code)\n($checked.stderr | str trim)"
                }
            }
        }
    }
}
