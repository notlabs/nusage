# schemas

The runner of an output-schema suite, `lib.nu`, which says what a suite's manifest holds, and `overlay.nu <manifest>`, which prints the overlay declaring each attached output with its schema embedded, for `nus generate --overlay`.
Each package keeps its suite beside it, under `lib/<tool>/schemas/`.
