#!/usr/bin/env nusage
#USAGE about "Emit a Usage overlay from a tool's output schema bindings"
#USAGE arg "<manifest>" help="The integration's schema suite"
use lib.nu [load-suite schema-overlay]
schema-overlay (load-suite $usage.args.manifest) | print
