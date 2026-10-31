//! The existing script analysis as data, without generated source or execution.
use std::path::Path;

use nusage_spec::{Diagnostic, Texts};
use serde_json::{Value, json};

/// Inspect the calls known to the same analysis the interpreter and language server use.
///
/// Paths are absolute, as they are in the analysis; spans are zero-based, end-exclusive
/// UTF-8 byte offsets in the caller. Calls list resolved command shadows, not every call
/// occurrence or a complete dependency graph. Header and call findings are data, even when
/// incomplete; failure to read the script or a missing nusage shebang is an error.
/// The wire shape is documented by `nusage/schemas/inspection.schema.json`.
pub fn inspect(script: &Path) -> Result<Value, Diagnostic> {
    let script =
        std::path::absolute(script).map_err(|err| Diagnostic::new(script, err.to_string()))?;
    let source = std::fs::read_to_string(&script)
        .map_err(|err| Diagnostic::new(&script, format!("cannot read: {err}")))?;
    let analysis = crate::prelude::analyze(&script, &source, &Texts::new())?;
    let calls: Vec<_> = analysis
        .calls
        .shadows
        .iter()
        .map(|shadow| {
            let through = match &shadow.through {
                crate::calls::Through::Nusage => json!({"kind": "nus"}),
                crate::calls::Through::Mise { dir, task } => {
                    json!({"kind": "mise", "dir": dir, "task": task})
                }
            };
            json!({
                "name": shadow.name,
                "target": shadow.target,
                "through": through,
                "command": shadow.command,
            })
        })
        .collect();
    let findings: Vec<_> = analysis
        .calls
        .findings
        .iter()
        .map(|finding| {
            json!({
                "span": {"start": finding.span.start, "end": finding.span.end},
                "message": finding.message,
            })
        })
        .collect();
    let header = analysis.header.map(|finding| {
        json!({
            "path": finding.path,
            "line": finding.line,
            "message": finding.message,
        })
    });
    Ok(json!({"script": script, "calls": calls, "findings": findings, "header": header}))
}
