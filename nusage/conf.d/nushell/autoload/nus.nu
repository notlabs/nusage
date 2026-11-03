# nusage's activation for Nushell, which `mise dot apply` links beside Nushell's
# configuration as `nus.nu`, used as `config.nu` would use it: its own commands stay in the
# module.
use ($nu.default-config-dir | path join nus.nu)
