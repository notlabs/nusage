//! Reading usage declarations, and assembling them into one spec.
//!
//! A script declares its interface in `#USAGE` comment lines at the top of the file, in usage's
//! own KDL; a binary is described by a `.usage.kdl` spec file. usage parses either into a
//! [`usage::Spec`] and discards KDL type annotations; this crate keeps them, and keeps each
//! node's text, because the generated module carries both. Nothing here knows that Nushell
//! exists beyond the file extension and the `mod.nu` layout.
//!
//! The entry points are [`read_header`] for one script and [`assemble`] for a script, a tree
//! or a spec file; [`assemble_with`] merges overlays onto a spec file first. A spec's
//! `nusage-args` hold what usage's grammar cannot, the words that ask for an output, and are
//! taken out before usage reads it.

mod args;
mod error;
mod header;
mod overlay;
mod tree;

pub use args::{NODE as ARGS_NODE, OutputArgs, flag_word};
pub use error::{Diagnostic, DiagnosticLocation};
pub use header::{Header, HeaderNode, ScriptHeader, read_header, read_subcommand_header};
pub use tree::{Assembled, CommandPath, Provider, Source, assemble, assemble_with, command_at};
