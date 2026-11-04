# The runner of an output-schema suite; a package keeps its schemas, manifest and examples
# beside it. A suite is a NUON manifest: `format: 1`, the `tool`, and the `baseline` the
# schemas were written from. `outputs` bind schemas to the tool's outputs: an `id`, the
# `command` words, the output `name`, the `select` switch or, where no switch asks for the
# output, the list of words that do (declared as `nusage-args`), the `framing` (`json` or
# `jsonl`), the `schema` file beside the manifest, the `source` it was written from, and
# `attach: false` for an output checked but not declared in the overlay. `cases` run the tool:
# an `id`, the `output`, the whole `argv`, the `exit_codes` accepted, an `expect` schema the
# output must also satisfy, and `records` for a JSON lines count. `run-suite` holds the tool's
# raw stdout to the schemas through `nus validate` before anything decodes it.
export def load-suite [manifest: path] {
    let manifest = $manifest | path expand
    let suite = open $manifest
    if $suite.format != 1 {
        error make --unspanned {msg: $"Unsupported schema suite format: ($suite.format)"}
    }
    if ($suite.outputs | get id | uniq | length) != ($suite.outputs | length) {
        error make --unspanned {msg: "Schema output IDs must be unique"}
    }
    for output in $suite.outputs {
        if $output.framing not-in [json jsonl] {
            error make --unspanned {msg: $"Unsupported framing: ($output.framing)"}
        }
        if ($output.select | describe) not-in [string list<string>] {
            error make --unspanned {msg: $"($output.id): `select` is a switch or a list of words"}
        }
        let file = $manifest | path dirname | path join $output.schema
        if not ($file | path exists) {
            error make --unspanned {msg: $"Missing schema: ($file)"}
        }
    }
    $suite | insert directory ($manifest | path dirname)
}

# The overlay declares each attached output with its schema embedded, so where the overlay
# and the spec sit cannot change how a schema file resolves. A `select` that is a switch is
# usage's `select`; a list of words, such as jj's `--no-graph --template ...`, is nusage's
# `nusage-args`, which nusage passes for the output and usage never reads.
export def schema-overlay [suite: record] {
    $suite.outputs
    | where {|output| $output.attach? != false }
    | each {|output|
        let schema = open --raw ($suite.directory | path join $output.schema) | to json --raw
        let name = $output.name | to json --raw
        let framing = $output.framing | to json --raw
        let body = if ($output.select | describe) == string {
            let selector = $output.select | to json --raw
            $"output ($name) framing=($framing) select=($selector) { schema ($schema) }"
        } else {
            let words = $output.select | each { to json --raw } | str join " "
            $"output ($name) framing=($framing) { nusage-args ($words); schema ($schema) }"
        }
        $output.command | reverse | reduce --fold $body {|word, inner|
            $"cmd ($word | to json --raw) { ($inner) }"
        }
    }
    | str join (char nl)
}

def validate-file [schema: path, instance: path] {
    let result = ^nus validate $schema $instance | complete
    if $result.exit_code == 0 { [] } else {
        [
            ([$result.stdout $result.stderr] | str join (char nl) | str trim)
        ]
    }
}

# The binary's raw stdout, before anything decodes it, held to the output's schema and to
# the case's `expect`, another JSON Schema.
export def validate-result [suite: record, case: record, result: record] {
    let matches = $suite.outputs | where id == $case.output
    if ($matches | length) != 1 {
        error make --unspanned {msg: $"Unknown output in case ($case.id): ($case.output)"}
    }
    let output = $matches | first
    let scratch = mktemp -d
    let checked = try {
        mut errors = []
        if $result.exit_code not-in $case.exit_codes {
            $errors = $errors | append $"exit ($result.exit_code), expected ($case.exit_codes | to nuon): ($result.stderr | str trim)"
        }
        let schema = $suite.directory | path join $output.schema
        let assertion = $scratch | path join expect.json
        if $case.expect? != null {
            $case.expect | to json | save $assertion
        }
        let documents = if $output.framing == jsonl {
            $result.stdout | lines
        } else {
            [$result.stdout]
        }
        if ($documents | length) == 0 {
            $errors = $errors | append "No JSON documents were emitted"
        }
        for item in ($documents | enumerate) {
            let instance = $scratch | path join $"($item.index).json"
            $item.item | save $instance
            $errors = $errors | append (validate-file $schema $instance)
            if $case.expect? != null {
                $errors = $errors | append (validate-file $assertion $instance)
            }
        }
        if $case.records? != null and ($documents | length) != $case.records {
            $errors = $errors | append $"Expected ($case.records) records, got ($documents | length)"
        }
        {
            id: $case.id
            ok: ($errors | is-empty)
            exit_code: $result.exit_code
            errors: $errors
        }
    } catch {|err|
        rm -r $scratch
        error make --unspanned {msg: $err.msg}
    }
    rm -r $scratch
    $checked
}

# The suite's schemas held to their metaschema, then documents read from the serializers
# held to their output's schema: `{id, output, document, valid}`, where `valid: false` is a
# shape the schema must refuse. A document is written on one line, as a JSON lines record is.
export def check-examples [suite: record, examples: list<record>] {
    for file in ($suite.outputs | get schema | uniq) {
        let checked = ^nus validate ($suite.directory | path join $file) | complete
        if $checked.exit_code != 0 {
            error make --unspanned {
                msg: ($checked.stderr | str trim)
            }
        }
    }
    $examples | each {|example|
        let case = {id: $example.id, output: $example.output, exit_codes: [0]}
        let stdout = $example.document | to json --raw
        let result = validate-result $suite $case {stdout: $stdout, stderr: "", exit_code: 0}
        let ok = $result.ok == $example.valid
        {
            id: $example.id
            ok: $ok
            exit_code: 0
            errors: (if $ok { [] } else { [$"Expected valid=($example.valid): ($result.errors | str join '; ')"] })
        }
    }
}

export def finish [results: list<record>] {
    print ($results | select id ok exit_code)
    let failures = $results | where ok == false
    if ($failures | is-not-empty) {
        let details = $failures | each {|row| $"($row.id): ($row.errors | str join '; ')" } | str join (char nl)
        error make --unspanned {msg: $details}
    }
}
