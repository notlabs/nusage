//! The existing script analysis as data, without generated source or execution.
use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;

use nusage_spec::{Diagnostic, Texts};
use serde_json::{Value, json};

/// Inspect the calls known to the same analysis the interpreter and language server use.
///
/// Paths are absolute, as they are in the analysis; spans are zero-based, end-exclusive
/// UTF-8 byte offsets in the caller. Calls list resolved command shadows, not every call
/// occurrence or a complete dependency graph. Header, package and call findings are data, even when
/// incomplete; failure to read the script or a missing nusage shebang is an error.
/// The wire shape is documented by `nusage/schemas/inspection.schema.json`.
pub fn inspect(script: &Path) -> Result<Value, Diagnostic> {
    inspect_with(script, false)
}

pub(crate) fn inspect_with(script: &Path, recursive: bool) -> Result<Value, Diagnostic> {
    let script =
        std::path::absolute(script).map_err(|err| Diagnostic::new(script, err.to_string()))?;
    let source = std::fs::read_to_string(&script)
        .map_err(|err| Diagnostic::new(&script, format!("cannot read: {err}")))?;
    let analysis = crate::prelude::analyze(&script, &source, &Texts::new())?;
    let graph = recursive.then(|| dependency_graph(&script, &analysis));
    let calls: Vec<_> = analysis
        .calls
        .shadows
        .iter()
        .map(|shadow| {
            json!({
                "name": shadow.name,
                "target": shadow.target,
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
    let mut report = json!({
        "script": script,
        "calls": calls,
        "findings": findings,
        "header": header,
        "module_error": analysis.modules,
    });
    if let Some(graph) = graph {
        report["graph"] = graph;
    }
    Ok(report)
}

fn dependency_graph(script: &Path, analysis: &crate::prelude::Analysis) -> Value {
    let mut nodes = BTreeMap::new();
    let mut edges = BTreeSet::new();
    let mut findings = Vec::new();
    let mut node = |kind: &str, path: &Path| {
        let id = format!("{kind}:{}", path.display());
        nodes.insert(id.clone(), json!({"id": id, "kind": kind, "path": path}));
        id
    };
    node("script", script);
    for (path, dependencies) in &analysis.dependencies.scripts {
        let from = node("script", path);
        for target in &dependencies.calls {
            edges.insert((from.clone(), node("script", target), "calls"));
        }
        for module in &dependencies.imports {
            edges.insert((from.clone(), node("module", module), "imports"));
        }
        // Preparation can add findings to the root after its first scan.
        let script_findings = if path == script && analysis.modules.is_none() {
            &analysis.calls.findings
        } else {
            &dependencies.findings
        };
        findings.extend(script_findings.iter().map(|finding| {
            json!({
                "script": path,
                "span": {"start": finding.span.start, "end": finding.span.end},
                "message": finding.message,
            })
        }));
    }
    let edges: Vec<_> = edges
        .into_iter()
        .map(|(from, to, kind)| json!({"from": from, "to": to, "kind": kind}))
        .collect();
    json!({"nodes": nodes.into_values().collect::<Vec<_>>(), "edges": edges, "findings": findings})
}
