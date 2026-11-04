#!/usr/bin/env nu
#MISE description="Emit a CI annotation, annotated diff, or log group"
#MISE alias="nusage:report:emit"
#MISE outputs=[]
#MISE cache={enabled=false}
use .support/actions.nu *

def main [
    operation: string
    message?: string
    --file: string
    --line: int
    --end-line: int
    --title: string
] {
    match $operation {
        error | warning | notice => {
            annotate $operation $message --file $file --line $line --end-line $end_line --title $title
        }
        diff => { annotate-diff $file $title $message }
        group-start => { group-start $message }
        group-end => { group-end }
        _ => { error make --unspanned {msg: $"Unknown reporting operation: ($operation)"} }
    }
}
