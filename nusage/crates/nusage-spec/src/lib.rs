//! Reading usage declarations, and assembling them into one spec.
//!
//! A script declares its interface in `#USAGE` comment lines at the top of the file, in usage's own KDL; a binary is described by a `.usage.kdl` spec file. usage parses either into a [`usage::Spec`] and discards KDL type annotations; this crate keeps them, and keeps each node's text, because the generated module carries both.
//! Nothing here knows that Nushell exists beyond the file extension and the `mod.nu` layout.
//!
//! [`assemble`] and its variants read a script, a tree or a spec file; [`read_header`] reads one script.
//! What usage's grammar cannot hold inside an `output`, nusage's own nodes, is taken out before usage reads the spec.

mod args;
mod error;
mod header;
pub mod http;
mod overlay;
mod tree;

pub use args::{NODE as ARGS_NODE, OutputArgs, flag_word};
pub use error::Diagnostic;
pub use header::{
    Header, HeaderNode, ScriptHeader, Texts, read_header, read_header_in, read_subcommand_header,
};
pub use tree::{
    Assembled, CommandPath, Provider, Source, assemble, assemble_http, assemble_in, assemble_text,
    assemble_with, command_at,
};
