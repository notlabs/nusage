#!/usr/bin/env nusage
#USAGE about "Exercise the shared schema checker with valid and deliberately invalid output"
use std/assert
use lib.nu [validate-result]

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
    let result = validate-result $suite $case {stdout: $case.stdout, stderr: "", exit_code: $case.code}
    assert equal $result.ok $case.passes $"($case.id): ($result | to nuon)"
}
print $"schemas: ($cases | length) validation cases passed"
