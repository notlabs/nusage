# A binary's output decoded as the module's closure decodes it. When that fails and the
# `nusage` this module was generated with is on PATH, the output is held to the schema the
# spec declares, so the error names what does not match it rather than what failed to
# convert. The error is the decoding's own when the output matches, when there is no
# `nusage` to ask, or when the check did not run; then its help says why not.
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
                error make --unspanned {
                    msg: $"the output does not match its schema\n($checked.stderr | str trim)"
                }
            }
            _ => {
                let note = $"the output could not be held to its schema: nusage validate exited ($checked.exit_code)\n($checked.stderr | str trim)"
                let details = $err.details | reject url inner | update help {|d|
                    if ($d.help | is-empty) { $note } else { $"($d.help)\n\n($note)" }
                }
                let details = if ($details.code | is-empty) {
                    $details | reject code
                } else {
                    $details
                }
                if ($details.labels | is-empty) {
                    error make --unspanned ($details | reject labels)
                } else {
                    error make $details
                }
            }
        }
    }
}
