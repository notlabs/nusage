# Bundle files
export def main [
    ...file: path,                      # Files to bundle
    --tag (-t): list<string> = [],      # Tag to attach, repeatable
    --verbose (-v): int = 0,            # Log more, repeatable
    --format: string@[tar zip] = tar,   # Archive format
] {
    let usage = {
        cmd: []
        args: {file: $file}
        flags: {tag: $tag, verbose: $verbose, format: $format}
    }
    $in | do { source ../script.nu }
}
