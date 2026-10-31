//! The commands nusage serves inside Nushell: each written once as a `Run` of the kit, with
//! its signature from the CLI's own spec, and registered twice, as a native command of the
//! engine scripts run in and as the plugin's command. `nus call` runs a script in that
//! engine; `nus validate` holds documents to a schema.

use std::sync::Arc;

use nusage_plugin::nu_plugin::{Plugin, PluginCommand};
use nusage_plugin::nu_protocol::engine::Command;
use nusage_plugin::{Adapter, CommandTree, Native};

use crate::executor::Executor;

mod call;
mod validate;

pub use call::Call;
pub use validate::Validate;

/// The commands, built from the CLI's spec, sharing one executor.
#[derive(Clone)]
pub struct Commands {
    pub call: Call,
    pub validate: Validate,
}

impl Commands {
    /// The commands from the CLI's own spec, with `executor` as where `nus call` runs
    /// scripts; the executor is given the commands as its engine's own.
    pub fn new(executor: Arc<Executor>) -> Result<Self, String> {
        let tree = tree()?;
        let commands = Commands {
            call: Call::new(&tree, executor.clone())?,
            validate: Validate::new(&tree)?,
        };
        executor.register(commands.natives());
        Ok(commands)
    }

    /// The commands as an engine's own.
    pub fn natives(&self) -> Vec<Box<dyn Command>> {
        vec![
            Box::new(Native(self.call.clone())),
            Box::new(Native(self.validate.clone())),
        ]
    }

    /// The commands as a plugin's.
    pub fn adapters<P: Plugin + 'static>(&self) -> Vec<Box<dyn PluginCommand<Plugin = P>>> {
        vec![
            Box::new(Adapter::new(self.call.clone())),
            Box::new(Adapter::new(self.validate.clone())),
        ]
    }
}

/// The CLI's own spec as the command model, where the commands take their signatures.
pub fn tree() -> Result<CommandTree, String> {
    nusage_plugin::commands("nus", &crate::cli::Nusage::to_kdl()).map_err(|err| err.to_string())
}
