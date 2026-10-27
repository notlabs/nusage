//! Typed Nushell commands from usage-annotated scripts, and typed wrappers from usage specs
//! of binaries.
//!
//! [`generate`] is the whole pipeline: assemble the source into one spec, derive the command
//! model, write the module for the target the source implies. The CLI in `main.rs` is a thin
//! shell around it.

mod binary;
mod common;
mod shim;

use std::path::Path;

pub use nusage_spec::Diagnostic;
use nusage_spec::Source;

/// Generate the module for a script, a tree of scripts, or a `.kdl` spec file.
///
/// Scripts get the shim target: a `def` per command that hands the script `$usage` and
/// `run`s it. A spec file gets the binary target: a `def` per command of the binary it
/// describes that runs the binary with the argv its parameters say and decodes the output
/// the call selected; written as `<bin>.nu`, `use <bin>.nu *` names the commands as the
/// binary does. `out` is where the module will be written; `run` paths inside a shim are
/// relative to that file's directory, or to the current directory with `None`. The result
/// has been parsed by Nushell: what Nushell rejects is a diagnostic here, not at `use`.
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
        Source::Binary => binary::module(&tree),
    }
    .map_err(|err| Diagnostic::new(source, err.to_string()))?;
    let text = nusage_nu::print(&module);
    let name = out
        .and_then(|out| out.file_stem())
        .and_then(|stem| stem.to_str())
        .unwrap_or("nusage");
    nusage_nu::check_module(name, &text, out.and_then(Path::parent))
        .map_err(|err| Diagnostic::new(source, err.to_string()))?;
    Ok(text)
}

/// The assembled spec as usage KDL, for every tool that reads usage specs.
pub fn spec(source: &Path) -> Result<String, Diagnostic> {
    let assembled = nusage_spec::assemble(source)?;
    Ok(assembled.spec.to_string())
}
