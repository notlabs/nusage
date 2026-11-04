# Uses nusage's activation as `config.nu` would; `[dotfiles.nus-activate]` in nusage's
# `mise.toml` links both into place.
use ($nu.default-config-dir | path join nus.nu)
