//! A small model of the Nushell a generator writes, and the one printer that writes it.
//!
//! The model covers what a module needs: a preamble, `def`s and `extern`s with attributes,
//! typed parameters, an output type and a body of a few statements. Constructors carry the
//! invariants the printer relies on, so a value that exists prints as valid Nushell. The
//! printer is a set of genco templates, one per shape of output. Values are Nushell's own
//! `Value`, written by its `nuon` crate; words are quoted by Nushell's own rule from `nu-utils`.

mod literal;
mod printer;
mod syntax;

pub use literal::{Value, check_default, default_text, nuon};
pub use printer::print;
pub use syntax::*;
