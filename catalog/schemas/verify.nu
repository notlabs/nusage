#!/usr/bin/env nusage
#USAGE about "Exercise the shared schema checker with valid and deliberately invalid output"
use std/assert
use lib.nu [validate-result schema-overlay]

const directory = path self | path dirname | path join fixtures

let suite = {
    directory: $directory
    outputs: [
        {
            id: status
            name: json
            command: [status]
            select: --json
            framing: json
            schema: status.schema.json
        }
        {
            id: events
            name: events
            command: [events]
            select: --events
            framing: jsonl
            schema: status.schema.json
        }
    ]
}

let cases = [
    {
        id: valid
        output: status
        exit_codes: [0]
        stdout: '{"ok":true}'
        code: 0
        passes: true
    }
    {
        id: missing-required
        output: status
        exit_codes: [0]
        stdout: '{}'
        code: 0
        passes: false
    }
    {
        id: extra-field
        output: status
        exit_codes: [0]
        stdout: '{"ok":true,"extra":1}'
        code: 0
        passes: false
    }
    {
        id: trailing-document
        output: status
        exit_codes: [0]
        stdout: '{"ok":true} {}'
        code: 0
        passes: false
    }
    {
        id: expected-failure
        output: status
        exit_codes: [3]
        stdout: '{"ok":false}'
        code: 3
        passes: true
    }
    {
        id: wrong-exit
        output: status
        exit_codes: [0]
        stdout: '{"ok":true}'
        code: 3
        passes: false
    }
    {
        id: optional-disappeared
        output: status
        exit_codes: [0]
        stdout: '{"ok":true}'
        code: 0
        passes: false
        expect: {
            required: [note]
        }
    }
    {
        id: events
        output: events
        exit_codes: [0]
        stdout: "{\"ok\":true}\n{\"ok\":false}\n"
        code: 0
        passes: true
        records: 2
    }
    {
        id: invalid-event
        output: events
        exit_codes: [0]
        stdout: "{\"ok\":true}\n{}\n"
        code: 0
        passes: false
        records: 2
    }
]
for case in $cases {
    let result = (validate-result
        $suite
        $case
        {stdout: $case.stdout, stderr: "", exit_code: $case.code}
    )
    assert equal $result.ok $case.passes $"($case.id): ($result | to nuon)"
}
let overlay = schema-overlay $suite
assert ($overlay | str contains 'cmd "status"')
assert ($overlay | str contains 'framing="jsonl"')
assert not ($overlay | str contains 'schema file=')
# Words no switch spells are the output's `nusage-args`, as written.
let worded = schema-overlay ($suite | update outputs {|suite|
    $suite.outputs | update select {|output| [--no-graph --template 'json(self) ++ "\n"'] }
})
assert (
    $worded
    | str contains 'nusage-args "--no-graph" "--template" "json(self) ++ \"\\n\""; schema'
) $worded
assert not ($worded | str contains 'select=')
print $"schemas: ($cases | length) validation cases passed; overlay embeds its schemas"
