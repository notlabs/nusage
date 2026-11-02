//! nusage's commands as a Nushell plugin: the same commands as the CLI, with the same
//! parameters, by the CLI's own usage spec, which `usage-rs` derives from the CLI and the
//! plugin reads at startup. A module whose wrappers call `nus validate` calls this plugin
//! when it is registered and the `nus` binary when it is not, the words being the same;
//! the plugin's process lives across calls, so a module that checks every output pays no
//! process per check. Where the CLI prints and exits, a plugin command returns the data:
//! the findings, as a table, not a line each on standard error and an exit code.

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
