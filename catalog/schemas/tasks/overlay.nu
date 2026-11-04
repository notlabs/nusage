#!/usr/bin/env nu
#MISE description="Emit a Usage overlay from a schema suite"
#MISE alias="catalog:schemas:overlay"
#MISE outputs=[]
#MISE cache={enabled=false}
use .support/lib.nu [load-suite schema-overlay]

def main [manifest: path] {
    schema-overlay (load-suite $manifest) | print
}
