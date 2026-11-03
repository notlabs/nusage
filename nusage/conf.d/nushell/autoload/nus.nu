# nusage's activation for Nushell, which `mise dot apply` links beside Nushell's
# configuration as `nus.nu`, used as `config.nu` would use it: `mise` comes in, for
# `mise shell`, and the rest stays in the module.
use ($nu.default-config-dir | path join nus.nu) *
