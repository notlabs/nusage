# schemas

The `nusage:schemas:overlay` task prints the overlay declaring each attached output with its schema embedded, for `nus generate --overlay`.
`nusage:schemas:examples` checks a suite's examples; `nusage:schemas:validate` checks captured case results supplied as JSON on stdin.
The suite format is described in the tasks' private `.support/lib.nu`.
Each package keeps its suite beside it, under `lib/<tool>/schemas/`.
