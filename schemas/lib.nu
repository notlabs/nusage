# Shared development tooling. Tool-specific schemas and fixtures live with each integration.
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
        let file = $manifest | path dirname | path join $output.schema
        if not ($file | path exists) {
            error make --unspanned {msg: $"Missing schema: ($file)"}
        }
    }
    $suite | insert directory ($manifest | path dirname)
}

# Embed schema text so an overlay can be merged into a spec in a different directory.
# The schema itself is still authored once, in the adjacent JSON file.
export def schema-overlay [suite: record] {
    $suite.outputs
    | where {|output| $output.attach? != false }
    | each {|output|
        let schema = open --raw ($suite.directory | path join $output.schema) | to json --raw
        let name = $output.name | to json --raw
        let framing = $output.framing | to json --raw
        let selector = $output.select | to json --raw
        let body = $"output ($name) framing=($framing) select=($selector) { schema ($schema) }"
        $output.command | reverse | reduce --fold $body {|word, inner|
            $"cmd ($word | to json --raw) { ($inner) }"
        }
    }
    | str join (char nl)
}

def validate-file [schema: path, instance: path] {
    let result = ^check-jsonschema --schemafile $schema $instance | complete
    if $result.exit_code == 0 { [] } else {
        [
            ([$result.stdout $result.stderr] | str join (char nl) | str trim)
        ]
    }
}

# Validate original stdout, before Nushell decoding can fill fields or convert values.
# A fixture's "expect" is another JSON Schema: assertions use the same vocabulary.
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

# The caller owns fixture setup and environment; the runner knows no tool-specific paths.
export def run-suite [suite: record, binary: path, cwd: path] {
    let binary = $binary | path expand
    $suite.cases | each {|case|
        let result = do {
            cd $cwd
            ^$binary ...$case.argv | complete
        }
        validate-result $suite $case $result
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
