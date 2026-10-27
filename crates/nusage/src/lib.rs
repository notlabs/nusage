//! Typed Nushell commands from usage-annotated scripts.
//!
//! [`generate`] is the whole pipeline: assemble the script or tree into one spec, derive the
//! command model, write the shim module. The CLI in `main.rs` is a thin shell around it.

mod shim;

use std::path::Path;

pub use nusage_spec::Diagnostic;

/// Generate the shim module for a script or a tree.
///
/// `out` is where the module will be written; `run` paths inside it are relative to that
/// file's directory. With `None` they are relative to the current directory.
pub fn generate(source: &Path, out: Option<&Path>) -> Result<String, Diagnostic> {
    let assembled = nusage_spec::assemble(source)?;
    let tree = nusage_model::model(&assembled)?;
    let base = match out {
        Some(out) => out.parent().map(Path::to_path_buf).unwrap_or_default(),
        None => std::env::current_dir().map_err(|err| Diagnostic::new(source, err.to_string()))?,
    };
    let module =
        shim::module(&tree, &base).map_err(|err| Diagnostic::new(source, err.to_string()))?;
    Ok(nusage_nu::print(&module))
}

/// The assembled spec as usage KDL, for every tool that reads usage specs.
pub fn spec(source: &Path) -> Result<String, Diagnostic> {
    let assembled = nusage_spec::assemble(source)?;
    Ok(assembled.spec.to_string())
}
