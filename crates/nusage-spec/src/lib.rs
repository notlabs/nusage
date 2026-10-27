//! Reading usage headers from Nushell scripts, and assembling a tree of them into one spec.
//!
//! A script declares its interface in `#USAGE` comment lines at the top of the file, in usage's
//! own KDL. usage parses that into a [`usage::Spec`] and discards KDL type annotations; this
//! crate keeps them, and keeps each header node's text, because the generated module carries
//! both. Nothing here knows that Nushell exists beyond the file extension and the `mod.nu` layout.
//!
//! The two entry points are [`read_header`] for one file and [`assemble`] for a file or a tree.

mod error;
mod header;
mod tree;

pub use error::Diagnostic;
pub use header::{Header, HeaderNode, read_header};
pub use tree::{Assembled, CommandPath, Provider, assemble};
