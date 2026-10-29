#!/usr/bin/env nusage
#USAGE about "The intent's claims, as a table to read: what each says and whether it is checked"
#USAGE flag "--status <status>" help="Only the claims of this status" { choices "open" "checked" }
#USAGE arg "[topic]" help="Only the claims of this file, as `purity` for claims/purity.nuon"

const here = path self | path dirname

let topic = $usage.args.topic
glob ($here | path join claims *.nuon)
| sort
| where {|file| $topic == null or ($file | path parse | get stem) == $topic }
| each {|file|
    open $file | each {|claim|
        {
            topic: ($file | path parse | get stem)
            id: $claim.id
            status: $claim.status
            says: $claim.says
        }
    }
}
| flatten
| where {|claim| $usage.flags.status == null or $claim.status == $usage.flags.status }
