alias "attr usage" = echo

# Bundle files
@usage 'arg "<file>..." help="Files to bundle"'
@usage 'flag "-t --tag <tag>" var=#true help="Tag to attach, repeatable"'
@usage 'flag "-v --verbose" count=#true help="Log more, repeatable"'
@usage 'flag "--format <format>" default="tar" help="Archive format" { choices "tar" "zip" }'
export def main [
    ...file: path,                     # Files to bundle
    --tag (-t): list<string> = [],     # Tag to attach, repeatable
    --verbose (-v): int = 0,           # Log more, repeatable
    --format: string@[tar zip] = tar,  # Archive format
] {
    let usage = {
        cmd: []
        args: {file: $file}
        flags: {tag: $tag, verbose: $verbose, format: $format}
    }
    $in | run ../script.nu
}
