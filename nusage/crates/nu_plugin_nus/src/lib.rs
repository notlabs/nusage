//! nusage's commands as a Nushell plugin: the same commands as the CLI, with the same
//! parameters, by the CLI's own usage spec, which `usage-rs` derives from the CLI and the
//! plugin reads at startup. A module whose wrappers call `nus validate` calls this plugin
//! when it is registered and the `nus` binary when it is not, the words being the same;
//! the plugin's process lives across calls, so a module that checks every output pays no
//! process per check. Where the CLI prints and exits, a plugin command returns the data:
//! the findings, as a table, not a line each on standard error and an exit code.
//!
//! The commands here are the ones a module needs on the hot path, not every subcommand of
//! the CLI: those are added as a consumer asks for them.

use nusage_plugin::nu_plugin::{Plugin, PluginCommand};
use nusage_plugin::nu_protocol::engine::Command;
use nusage_plugin::{Adapter, CommandTree, Diagnostic, Native};

mod validate;

pub use validate::Validate;

/// The plugin, with the CLI's spec read into the command model its commands take their
/// signatures from.
pub struct NusagePlugin {
    tree: CommandTree,
}

impl NusagePlugin {
    /// The plugin, from the CLI's own spec.
    pub fn new() -> Result<Self, Diagnostic> {
        let tree = nusage_plugin::commands("nus", &nusage::cli::Nusage::to_kdl())?;
        Ok(NusagePlugin { tree })
    }
}

impl NusagePlugin {
    fn validate(&self) -> Validate {
        Validate::new(&self.tree).expect("the CLI's spec declares `validate`")
    }

    /// The same commands as an engine's own, for the engine a script runs in inside the
    /// plugin, where a call of one reaches this code with no plugin between.
    pub fn natives(&self) -> Vec<Box<dyn Command>> {
        vec![Box::new(Native(self.validate()))]
    }
}

impl Plugin for NusagePlugin {
    fn version(&self) -> String {
        env!("CARGO_PKG_VERSION").into()
    }

    fn commands(&self) -> Vec<Box<dyn PluginCommand<Plugin = Self>>> {
        vec![Box::new(Adapter::new(self.validate()))]
    }
}
