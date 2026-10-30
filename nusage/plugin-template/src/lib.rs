//! NAME as a Nushell plugin. The commands are declared by the usage spec beside this file,
//! `NAME.usage.kdl`, and take their signatures from it; what each does is in `commands.rs`.
//! State the plugin keeps across calls goes on [`Plugin`], which every command is handed.

use nusage_plugin::nu_plugin::PluginCommand;
use nusage_plugin::{CommandTree, Diagnostic};

mod commands;

pub use commands::Hello;

/// The spec the commands are declared by.
pub const SPEC: &str = include_str!("../NAME.usage.kdl");

pub struct Plugin {
    tree: CommandTree,
}

impl Plugin {
    pub fn new() -> Result<Self, Diagnostic> {
        Ok(Plugin {
            tree: nusage_plugin::commands("NAME", SPEC)?,
        })
    }
}

impl nusage_plugin::nu_plugin::Plugin for Plugin {
    fn version(&self) -> String {
        env!("CARGO_PKG_VERSION").into()
    }

    fn commands(&self) -> Vec<Box<dyn PluginCommand<Plugin = Self>>> {
        vec![Box::new(
            Hello::new(&self.tree).expect("the spec declares `hello`"),
        )]
    }
}
