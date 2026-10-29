#!/usr/bin/env nusage
#USAGE about "The workflows by jactionlint, and the handwritten Nushell and the TOML as the formatters want them, with what they would change shown"
# The formatters' own checks name a file and no more; a lint has to say what is wrong where,
# so each file is formatted again and the difference printed, and as an annotation on the
# file when run in GitHub Actions.
let in_actions = ($env.GITHUB_ACTIONS? | default "") == "true"
mut failed = []

def annotate [file: string, message: string] {
    print $"::error file=($file)::($message)"
}

print "$ jactionlint"
let workflows = ^jactionlint | complete
print --no-newline $workflows.stdout
if $workflows.exit_code != 0 {
    $failed = $failed | append "jactionlint"
}

print "$ nufmt"
let scripts = ^git ls-files "*.nu" | lines | where $it !~ "/expected/"
for file in $scripts {
    # nufmt ends what it reads from standard input without the newline it writes to a file.
    let content = open --raw $file | str trim --right --char (char nl)
    let formatted = $content | ^nufmt --stdin | str trim --right --char (char nl)
    if $formatted != $content {
        if $in_actions {
            annotate $file "not formatted as nufmt wants; `jj fix` writes it"
        }
        $formatted + (char nl) | ^diff --unified --label $file --label $"($file) as nufmt wants" $file -
        $failed = $failed | append $"nufmt: ($file)"
    }
}

print "$ taplo fmt --check --diff"
let toml = ^taplo fmt --check --diff | complete
print --no-newline $toml.stdout
if $toml.exit_code != 0 {
    if $in_actions {
        for file in (
            $toml.stderr
            | parse --regex "(?m)^(?:ERROR|error).*?(?<file>\\S+\\.toml)"
            | get file
            | uniq
        ) {
            annotate $file "not formatted as taplo wants; `jj fix` writes it"
        }
    }
    print --no-newline $toml.stderr
    $failed = $failed | append "taplo"
}

if ($failed | is-not-empty) {
    error make --unspanned {msg: $"lint failed: ($failed | str join ', ')"}
}
