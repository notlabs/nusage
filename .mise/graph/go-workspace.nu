# The ignored `go.work` over every Go module in the workspace's source directories, which
# mise's Go provider discovers projects from.
use common.nu *

def prepare [root: string] {
    cd $root
    if not ("go.work" | path exists) {
        checked go work init | ignore
    }
    let previous = checked go work edit -json | from json | get -o Use | default []
    if ($previous | is-not-empty) {
        checked go work edit ...($previous | get DiskPath | each {|p| $"-dropuse=($p)" }) | ignore
    }
    if ("go.mod" | path exists) {
        checked go work use . | ignore
    }
    # Hidden directories hold managed artifacts, and `target` holds build output such as
    # `cargo package` copies; neither holds the workspace's own modules.
    let sources = glob "[!.]*" --no-file --no-symlink
    | where {|p| ($p | path type) == dir and ($p | path basename) != target }
    if ($sources | is-not-empty) {
        checked go work use -r ...$sources | ignore
    }
}

def main [root: path = "."] {
    try { prepare ($root | path expand) } catch {|err| $err | report-failure go-workspace }
}
