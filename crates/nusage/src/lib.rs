//! Typed Nushell commands from usage-annotated scripts, and typed externs from usage specs.
//!
//! [`generate`] is the whole pipeline: assemble the source into one spec, derive the command
//! model, write the module for the target the source implies. The CLI in `main.rs` is a thin
//! shell around it.

mod common;
mod extern_;
mod shim;

use std::path::Path;

pub use nusage_spec::Diagnostic;
use nusage_spec::Source;

/// Generate the module for a script, a tree of scripts, or a `.kdl` spec file.
///
/// Scripts get the shim target: a `def` per command that hands the script `$usage` and
/// `run`s it. A spec file gets the extern target: an `extern` per command of the binary it
/// describes. `out` is where the module will be written; `run` paths inside a shim are
/// relative to that file's directory, or to the current directory with `None`.
pub fn generate(source: &Path, out: Option<&Path>) -> Result<String, Diagnostic> {
    let assembled = nusage_spec::assemble(source)?;
    let tree = nusage_model::model(&assembled)?;
    let module = match &assembled.source {
        Source::Scripts { .. } => {
            let base = match out {
                Some(out) => out.parent().map(Path::to_path_buf).unwrap_or_default(),
                None => std::env::current_dir()
                    .map_err(|err| Diagnostic::new(source, err.to_string()))?,
            };
            shim::module(&tree, &base)
        }
        Source::Binary => extern_::module(&tree),
    }
    .map_err(|err| Diagnostic::new(source, err.to_string()))?;
    Ok(nusage_nu::print(&module))
}

/// The assembled spec as usage KDL, for every tool that reads usage specs.
pub fn spec(source: &Path) -> Result<String, Diagnostic> {
    let assembled = nusage_spec::assemble(source)?;
    Ok(assembled.spec.to_string())
}
