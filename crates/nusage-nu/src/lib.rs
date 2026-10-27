//! A small model of the Nushell a generator writes, and the one printer that writes it.
//!
//! The model covers what a module needs: a preamble, `def`s with attributes, typed
//! parameters, an output type and a body of a few statements, and verbatim blocks. The
//! constructors carry the invariants the printer relies on; whether the result is Nushell is
//! for Nushell to say, and [`check_module`] asks its parser. The printer is a set of genco
//! templates, one per shape of output. Values are Nushell's own `Value`, written by its
//! `nuon` crate; words are quoted by Nushell's own rule from `nu-utils`.

mod check;
mod literal;
mod printer;
mod syntax;

pub use check::check_module;
pub use literal::{Value, check_default, default_text, nuon};
pub use printer::print;
pub use syntax::*;
