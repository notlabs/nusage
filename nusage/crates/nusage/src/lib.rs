//! Typed Nushell commands from usage-annotated scripts, and typed wrappers from usage specs
//! of binaries.
//!
//! [`generate`] is the whole pipeline: assemble the source into one spec, derive the command
//! model, write the module for the target the source implies: the shim for scripts, the
//! binary target for a spec file, the HTTP target for a spec file with the mapping of a
//! service beside it. Each stage prints: [`spec`] the assembled spec, [`model`] the command
//! model, [`generate`] the module. The CLI in `main.rs` is a thin shell around it.

mod binary;
mod calls;
pub mod cli;
pub mod commands;
mod common;
mod conform;
mod http;
mod inspect;
mod interpret;
mod lsp;
mod nu;
mod prelude;
mod shim;
mod switch_overlay;
mod validate;

use std::path::{Path, PathBuf};

pub use inspect::inspect;
pub use interpret::{Parsed, interpret, parse, route};
pub use validate::validate;

pub use nusage_spec::Diagnostic;
use nusage_spec::Source;

/// Generate the module for a script, a tree of scripts, or a `.kdl` spec file.
///
/// Scripts get the shim target: a `def` per command that hands the script `$usage` and
/// `run`s it. A spec file gets the binary target: a `def` per command of the binary it
/// describes that runs the binary with the argv its parameters say and decodes the output
/// the call selected, with Nushell's reader for its media type or framing, or the pipeline
/// its `nusage-decode` node states; written as `<bin>.nu`, `use <bin>.nu *` names the commands as
/// the binary does. `out` is where the module will be written; `run` paths inside a shim are
/// relative to that file's directory, or to the current directory with `None`. The result
/// has been parsed by Nushell: what Nushell rejects is a diagnostic here, not at `use`.
pub fn generate(source: &Path, out: Option<&Path>) -> Result<String, Diagnostic> {
    generate_with(source, out, &[], None)
}

/// [`generate`], with overlays merged onto a spec file first, see
/// [`nusage_spec::assemble_with`], and with the HTTP mapping of a spec that describes a
/// service, see [`nusage_spec::assemble_http`]: then the module gets the HTTP target, a
/// `def` per command that sends the request the mapping says and decodes the response as a
/// binary's output is decoded, its body the input when the call sends one.
pub fn generate_with(
    source: &Path,
    out: Option<&Path>,
    overlays: &[PathBuf],
    http: Option<&Path>,
) -> Result<String, Diagnostic> {
    let assembled = assemble(source, overlays, http)?;
    let tree = nusage_model::model(&assembled)?;
    // Paths inside the module, a shim's `run` and a binary's spec, are relative to where it
    // will be written.
    let base = match out {
        Some(out) => out.parent().map(Path::to_path_buf).unwrap_or_default(),
        None => std::env::current_dir().map_err(|err| Diagnostic::new(source, err.to_string()))?,
    };
    let module = match &assembled.source {
        Source::Scripts { .. } => shim::module(&tree, &base),
        Source::Binary if tree.service.is_some() => http::module(&tree),
        Source::Binary => binary::module(&tree, &common::relative(&base, source)),
    }
    .map_err(|err| Diagnostic::new(source, err.to_string()))?;
    let text = nusage_nu::print(&module);
    let name = out
        .and_then(|out| out.file_stem())
        .and_then(|stem| stem.to_str())
        .unwrap_or("nus");
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
pub fn check(
    source: &Path,
    overlays: &[PathBuf],
    http: Option<&Path>,
    module: &Path,
) -> Result<(), Diagnostic> {
    let assembled = assemble(source, overlays, http)?;
    let text = std::fs::read_to_string(module)
        .map_err(|err| Diagnostic::new(module, format!("cannot read: {err}")))?;
    let name = module
        .file_stem()
        .and_then(|stem| stem.to_str())
        .unwrap_or("nus");
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

/// The source assembled, with the overlays, and the HTTP mapping when there is one.
fn assemble(
    source: &Path,
    overlays: &[PathBuf],
    http: Option<&Path>,
) -> Result<nusage_spec::Assembled, Diagnostic> {
    match http {
        Some(http) => nusage_spec::assemble_http(source, overlays, http),
        None => nusage_spec::assemble_with(source, overlays),
    }
}

/// The line that stands in for a script's first where Nushell checks it, binding `$usage`
/// with its type and defining the shadows of the scripts it calls, and what those calls get
/// wrong, each as `<script>:<line>:<column>: <what>`.
pub fn prelude(script: &Path) -> Result<(String, Vec<String>), Diagnostic> {
    let (line, calls) = prelude::line(script)?;
    let source = std::fs::read_to_string(script)
        .map_err(|err| Diagnostic::new(script, format!("cannot read: {err}")))?;
    let findings = calls
        .findings
        .iter()
        .map(|finding| {
            let before = &source[..finding.span.start];
            let line = before.matches('\n').count() + 1;
            let column = before.len() - before.rfind('\n').map_or(0, |at| at + 1) + 1;
            format!("{}:{line}:{column}: {}", script.display(), finding.message)
        })
        .collect();
    Ok((line, findings))
}

/// Serve Nushell's language server for the scripts nusage runs, on standard input and
/// output: `nu --lsp`, with `args` after it, sees a script whose shebang names nusage with
/// the line [`prelude`] writes in place of its first. The exit code is Nushell's.
pub fn lsp(args: &[String]) -> std::io::Result<i32> {
    lsp::serve(args)
}

/// Run as `nu`, as a command wrapper standing in Nushell's place starts it: `nu --lsp`
/// is nusage's language server, through kakehashi when it is on PATH, and anything else is
/// `nu` itself. The exit code is what ran's.
pub fn nu(args: &[String]) -> std::io::Result<i32> {
    nu::run(args)
}

/// The definitions the interpreter `source`s before the script: the shadows of the scripts
/// it calls, each running its script by its absolute path.
pub fn prelude_run(script: &Path) -> Result<String, Diagnostic> {
    prelude::runtime(script)
}

/// The command model derived from the source, as NUON: what a target is handed, after every
/// decision between usage's vocabulary and a Nushell signature is made and before any
/// Nushell is written. The stages of [`generate`] are each printable: [`spec`] the
/// assembled spec, this the model, [`generate`] the module.
pub fn model(
    source: &Path,
    overlays: &[PathBuf],
    http: Option<&Path>,
) -> Result<String, Diagnostic> {
    let assembled = assemble(source, overlays, http)?;
    let tree = nusage_model::model(&assembled)?;
    let json = serde_json::to_value(&tree)
        .map_err(|err| Diagnostic::new(source, format!("the model does not serialize: {err}")))?;
    Ok(nusage_nu::nuon(&nu_value(json)))
}

/// A JSON value as a Nushell one, for printing as NUON.
fn nu_value(json: serde_json::Value) -> nu_protocol::Value {
    use nu_protocol::{Span, Value};
    let span = Span::unknown();
    match json {
        serde_json::Value::Null => Value::nothing(span),
        serde_json::Value::Bool(b) => Value::bool(b, span),
        serde_json::Value::Number(n) => match n.as_i64() {
            Some(i) => Value::int(i, span),
            None => Value::float(n.as_f64().unwrap_or_default(), span),
        },
        serde_json::Value::String(s) => Value::string(s, span),
        serde_json::Value::Array(items) => {
            Value::list(items.into_iter().map(nu_value).collect(), span)
        }
        serde_json::Value::Object(fields) => {
            let mut record = nu_protocol::Record::new();
            for (key, value) in fields {
                record.push(key, nu_value(value));
            }
            Value::record(record, span)
        }
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
