#!/usr/bin/env -S nu --stdin
#MISE description="Validate captured case results from JSON on stdin against a schema suite"
#MISE alias="nusage:schemas:validate"
#MISE outputs=[]
#MISE cache={enabled=false}
use std/assert
use .support/lib.nu [load-suite validate-result finish]

def main [manifest: path] {
    let results = $in | from json
    let suite = load-suite $manifest
    assert equal ($results | get id | sort) ($suite.cases | get id | sort) "Results must cover each suite case exactly once"
    finish ($results | each {|result|
        let case = $suite.cases | where id == $result.id | first
        validate-result $suite $case $result
    })
}
