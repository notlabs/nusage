//! The commands nusage serves inside Nushell, as the plugin's: each written once as a `Run`
//! of the kit, with its signature from the CLI's own spec. `nus validate` holds documents to
//! a schema.

use nusage_plugin::nu_plugin::{Plugin, PluginCommand};
use nusage_plugin::{Adapter, CommandTree};

mod validate;

pub use validate::Validate;

/// The commands, built from the CLI's spec.
#[derive(Clone)]
pub struct Commands {
    pub validate: Validate,
}

impl Commands {
    /// The commands from the CLI's own spec.
    pub fn new() -> Result<Self, String> {
        let tree = tree()?;
        Ok(Commands {
            validate: Validate::new(&tree)?,
        })
    }

    /// The commands as a plugin's.
    pub fn adapters<P: Plugin + 'static>(&self) -> Vec<Box<dyn PluginCommand<Plugin = P>>> {
        vec![Box::new(Adapter::new(self.validate.clone()))]
    }
}

/// The CLI's own spec as the command model, where the commands take their signatures.
pub fn tree() -> Result<CommandTree, String> {
    nusage_plugin::commands("nus", &crate::cli::Nusage::to_kdl()).map_err(|err| err.to_string())
}
