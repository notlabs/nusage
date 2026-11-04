#!/usr/bin/env nu
#MISE description="Check schemas and their accepted and rejected examples"
#MISE alias="catalog:schemas:examples"
#MISE outputs=[]
#MISE cache={enabled=false}
use .support/lib.nu [load-suite check-examples finish]

def main [manifest: path, examples: path] {
    finish (check-examples (load-suite $manifest) (open $examples))
}
