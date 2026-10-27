//! A small model of the Nushell a generator writes, and the one printer that writes it.
//!
//! The model covers what a shim module needs: a preamble, `def`s with attributes, typed
//! parameters, an output type and a body of a few statements. Constructors carry the
//! invariants the printer relies on, so a value that exists prints as valid Nushell. The
//! layout is the one nufmt produces, so generated files pass `nufmt --dry-run` unchanged.

mod literal;
mod printer;
mod syntax;

pub use literal::{Literal, nuon};
pub use printer::print;
pub use syntax::*;
