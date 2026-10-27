alias "attr usage" = echo

# Reports, with CLI-wide outputs and a CLI-wide selector
@usage 'flag "--format <format>" help="Output format" global=#true'
@usage 'output "text" default=#true help="Readable"'
@usage 'output ("record<ok: bool>")"json" framing="json" help="One object"'
@usage 'select "--format"'
@usage 'include file="included.kdl"'
@structured ["--format=json"] { from json }
export extern --strict main [
    --format: string@[text json],  # Output format
]: nothing -> record<ok: bool>

# List reports
@structured ["--format=json"] { from json }
export extern --strict list [
    --format: string@[text json],  # Output format
]

# Only text
@usage 'output "json" hide=#true'
export extern --strict quiet [
    --format: string@[text],  # Output format
]
