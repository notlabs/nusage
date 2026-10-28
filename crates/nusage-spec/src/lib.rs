//! Reading usage declarations, and assembling them into one spec.
//!
//! A script declares its interface in `#USAGE` comment lines at the top of the file, in usage's
//! own KDL; a binary is described by a `.usage.kdl` spec file. usage parses either into a
//! [`usage::Spec`] and discards KDL type annotations; this crate keeps them, and keeps each
//! node's text, because the generated module carries both. Nothing here knows that Nushell
//! exists beyond the file extension and the `mod.nu` layout.
//!
//! The entry points are [`read_header`] for one script and [`assemble`] for a script, a tree
//! or a spec file.

mod error;
mod header;
mod tree;

pub use error::Diagnostic;
pub use header::{Header, HeaderNode, ScriptHeader, read_header};
pub use tree::{Assembled, CommandPath, Provider, Source, assemble, command_at};
