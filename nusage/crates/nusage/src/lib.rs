//! Typed Nushell commands from usage-annotated scripts, and typed wrappers from usage specs
//! of binaries.
//!
//! [`generate`] is the whole pipeline: assemble the source into one spec, derive the command
//! model, write the module for the target the source implies. The CLI in `main.rs` is a thin
//! shell around it.

mod binary;
mod common;
mod conform;
mod interpret;
mod shim;
mod switch_overlay;

use std::path::{Path, PathBuf};

pub use interpret::{Parsed, interpret, parse};

pub use nusage_spec::Diagnostic;
use nusage_spec::Source;

/// Generate the module for a script, a tree of scripts, or a `.kdl` spec file.
///
/// Scripts get the shim target: a `def` per command that hands the script `$usage` and
/// `run`s it. A spec file gets the binary target: a `def` per command of the binary it
/// describes that runs the binary with the argv its parameters say and decodes the output
/// the call selected, with Nushell's reader for its media type or framing, or the pipeline
/// its `decode` node states; written as `<bin>.nu`, `use <bin>.nu *` names the commands as
/// the binary does. `out` is where the module will be written; `run` paths inside a shim are
/// relative to that file's directory, or to the current directory with `None`. The result
/// has been parsed by Nushell: what Nushell rejects is a diagnostic here, not at `use`.
pub fn generate(source: &Path, out: Option<&Path>) -> Result<String, Diagnostic> {
    generate_with(source, out, &[])
}

/// [`generate`], with overlays merged onto a spec file first; see
/// [`nusage_spec::assemble_with`].
pub fn generate_with(
    source: &Path,
    out: Option<&Path>,
    overlays: &[PathBuf],
) -> Result<String, Diagnostic> {
    let assembled = nusage_spec::assemble_with(source, overlays)?;
    let tree = nusage_model::model(&assembled)?;
    // Paths inside the module, a shim's `run` and a binary's spec, are relative to where it
    // will be written.
    let base = match out {
        Some(out) => out.parent().map(Path::to_path_buf).unwrap_or_default(),
        None => std::env::current_dir().map_err(|err| Diagnostic::new(source, err.to_string()))?,
    };
    let module = match &assembled.source {
        Source::Scripts { .. } => shim::module(&tree, &base),
        Source::Binary => binary::module(&tree, &common::relative(&base, source)),
    }
    .map_err(|err| Diagnostic::new(source, err.to_string()))?;
    let text = nusage_nu::print(&module);
    let name = out
        .and_then(|out| out.file_stem())
        .and_then(|stem| stem.to_str())
        .unwrap_or("nusage");
    let dir = out.and_then(Path::parent);
    nusage_nu::check_module(name, &text, dir)
        .map_err(|err| Diagnostic::new(source, err.to_string()))?;
    // What was written is held to usage's reading of the spec, not to the model's.
    let findings = conform::conform(&assembled, name, &text, dir)
        .map_err(|err| Diagnostic::new(source, err.to_string()))?;
    if !findings.is_empty() {
        return Err(Diagnostic::new(
            source,
            format!(
                "the generated module does not carry what the spec shows:\n  {}",
                findings.join("\n  ")
            ),
        ));
    }
    Ok(text)
}

/// Check a module written for the source, with overlays, against the spec as usage reads
/// it: every command the spec shows is a definition with the spec's positionals, flags and
/// completers, named as the generator names them, with its description once. [`generate`]
/// checks what it writes the same way.
pub fn check(source: &Path, overlays: &[PathBuf], module: &Path) -> Result<(), Diagnostic> {
    let assembled = nusage_spec::assemble_with(source, overlays)?;
    let text = std::fs::read_to_string(module)
        .map_err(|err| Diagnostic::new(module, format!("cannot read: {err}")))?;
    let name = module
        .file_stem()
        .and_then(|stem| stem.to_str())
        .unwrap_or("nusage");
    let findings = conform::conform(&assembled, name, &text, module.parent())
        .map_err(|err| Diagnostic::new(module, err.to_string()))?;
    if findings.is_empty() {
        Ok(())
    } else {
        Err(Diagnostic::new(
            module,
            format!(
                "does not carry what the spec shows:\n  {}",
                findings.join("\n  ")
            ),
        ))
    }
}

/// The assembled spec as usage KDL, overlays merged, for every tool that reads usage specs.
pub fn spec(source: &Path, overlays: &[PathBuf]) -> Result<String, Diagnostic> {
    let assembled = nusage_spec::assemble_with(source, overlays)?;
    Ok(assembled.spec.to_string())
}

/// An overlay declaring, for every command of the spec that has the switch, a framed output
/// the switch selects, as usage KDL: what a binary with `--json` flags and no `output`
/// declarations needs before its wrappers decode anything.
pub fn switch_overlay(
    source: &Path,
    overlays: &[PathBuf],
    switch: &str,
    framing: &str,
) -> Result<String, Diagnostic> {
    let assembled = nusage_spec::assemble_with(source, overlays)?;
    Ok(switch_overlay::switch_overlay(
        &assembled.spec,
        switch,
        framing,
    ))
}
