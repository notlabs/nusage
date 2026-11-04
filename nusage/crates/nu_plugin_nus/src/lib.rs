//! nusage's commands as a Nushell plugin ([`Commands`]): each the CLI's command of the same words, with the same parameters, by the CLI's own usage spec, which `usage-rs` derives from the CLI and the plugin reads at startup.
//! A call of those words reaches the plugin when it is registered and the `nus` binary when it is not; one written `^nus`, as the modules nusage writes call it, reaches the binary.
//! Where the CLI prints and exits, a plugin command returns the data: the findings, as a table, not a line each on standard error and an exit code.

use nusage::commands::Commands;
use nusage_plugin::nu_plugin::{Plugin, PluginCommand};

pub struct NusagePlugin {
    commands: Commands,
}

impl NusagePlugin {
    /// The plugin, from the CLI's own spec.
    pub fn new() -> Result<Self, String> {
        Ok(NusagePlugin {
            commands: Commands::new()?,
        })
    }
}

impl Plugin for NusagePlugin {
    fn version(&self) -> String {
        env!("CARGO_PKG_VERSION").into()
    }

    fn commands(&self) -> Vec<Box<dyn PluginCommand<Plugin = Self>>> {
        self.commands.adapters()
    }
}
