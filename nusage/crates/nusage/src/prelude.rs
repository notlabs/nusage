//! What a script has before its first line. Where it runs, the interpreter defines the
//! shadows of the scripts it calls ([`crate::calls`]) and binds `$usage`; where Nushell
//! checks it, as an editor does, one line stands in for the script's first, the shebang,
//! saying the same: `$usage` with its type, and the shadows as the interpreter defines them.
//! Replacing a line with a line keeps every other line where it was.

use std::ops::Range;
use std::path::{Path, PathBuf};

use nusage_model::{Command, Param, ParamKind};
use nusage_nu::{Item, Module};
use nusage_spec::{Diagnostic, Texts};

use crate::calls::{self, Calls, Paths};

/// The line that stands in for a script's first, and what a checker reports with it.
#[derive(Debug, Clone)]
pub struct Analysis {
    pub line: String,
    /// Where on the line each shadow is defined, by byte range, and the file that declares
    /// its command: the script it runs, or the spec of the program it runs.
    pub shadows: Vec<(Range<usize>, PathBuf)>,
    /// What the script's calls of scripts get wrong.
    pub calls: Calls,
    /// Why the header cannot be read, when it cannot: the line then binds `$usage` with no
    /// type, so the script still checks.
    pub header: Option<Diagnostic>,
}

/// The analysis of the script at `script` as `source` has it, with the other scripts it
/// reads as `texts` has them: an editor's, saved or not. The script must be one nusage runs:
/// its shebang names it.
pub fn analyze(script: &Path, source: &str, texts: &Texts) -> Result<Analysis, Diagnostic> {
    if !calls::names_nusage(source) {
        return Err(Diagnostic::new(
            script,
            "not a script nusage runs: its first line is no shebang naming nusage",
        )
        .at_line(1));
    }
    let mut texts = texts.clone();
    texts.insert(script.to_path_buf(), source.to_string());
    // What a checker needs is the type. Run as it is, the line binds the record `NUS_USAGE`
    // holds as NUON, so a harness can hold a record to the type, as the fixtures' does.
    let value = "($env.NUS_USAGE? | default \"{}\" | from nuon)";
    let (mut line, header) = match command_of(script, &texts) {
        Ok(command) => (
            format!("let usage: {} = {value}", usage_type(&command)),
            None,
        ),
        Err(err) => (format!("let usage = {value}"), Some(err)),
    };
    let mut calls = calls::scan(script, source, &texts);
    let defs = calls::definitions(script, &mut calls, Paths::Absolute, &texts);
    let mut shadows = Vec::new();
    // Made for each check, never kept, so it can name the script where it is.
    for (shadow, def) in calls.shadows.iter().zip(&defs) {
        line.push_str("; ");
        let start = line.len();
        line.push_str(&nusage_nu::print_line(def));
        // A program's command is declared in its spec, a script's in the script.
        let declared = match &shadow.runs {
            calls::Runs::Program { spec, .. } => spec.clone(),
            calls::Runs::Script => shadow.target.clone(),
        };
        shadows.push((start..line.len(), declared));
    }
    // A program call's wrapper builds its argv with helpers that run where the script runs;
    // on this one line each is its signature, which is what a check reads.
    for (name, signature) in HELPER_SIGNATURES {
        if line.contains(name) {
            line.push_str("; ");
            line.push_str(signature);
        }
    }
    Ok(Analysis {
        line,
        shadows,
        calls,
        header,
    })
}

/// The helpers a program call's wrapper calls, by name, and each as one line that has its
/// signature: `binary-helpers.nu`'s and `binary-decoded.nu`'s, which a test holds them to.
const HELPER_SIGNATURES: &[(&str, &str)] = &[
    (
        "nus argv",
        "def \"nus argv\" [positionals: list<any>, flags: record, scoped: record = {}]: nothing -> list<string> { [] }",
    ),
    (
        "nus decoded",
        "def \"nus decoded\" [text: string, schema: string, decode: closure, --lines]: nothing -> any { }",
    ),
];

/// The line that stands in for the script's first as it is on disk, and what its calls of
/// scripts get wrong; a header that cannot be read is the error.
pub fn line(script: &Path) -> Result<(String, Calls), Diagnostic> {
    let source = read(script)?;
    let analysis = analyze(script, &source, &Texts::new())?;
    match analysis.header {
        Some(err) => Err(err),
        None => Ok((analysis.line, analysis.calls)),
    }
}

/// The Nushell the interpreter defines before the script: the shadows of the scripts it
/// calls, each running its script by its absolute path. Empty when the script calls none.
pub fn runtime(script: &Path) -> Result<String, Diagnostic> {
    let source = read(script)?;
    let mut calls = calls::scan(script, &source, &Texts::new());
    let defs = calls::definitions(script, &mut calls, Paths::Absolute, &Texts::new());
    if defs.is_empty() {
        return Ok(String::new());
    }
    let mut module = Module {
        preamble: Vec::new(),
        items: defs.into_iter().map(Item::Def).collect(),
    };
    let helpers = crate::binary::helpers_for(&nusage_nu::print(&module));
    module.items.splice(0..0, helpers);
    Ok(nusage_nu::print(&module))
}

fn read(script: &Path) -> Result<String, Diagnostic> {
    std::fs::read_to_string(script)
        .map_err(|err| Diagnostic::new(script, format!("cannot read: {err}")))
}

/// The command the script is in its tree.
fn command_of(script: &Path, texts: &Texts) -> Result<Command, Diagnostic> {
    let (root, path) = calls::place_in_tree(script)?;
    let assembled = nusage_spec::assemble_in(&root, texts)?;
    nusage_model::model(&assembled)?
        .commands
        .into_iter()
        .find(|command| command.path == path)
        .ok_or_else(|| {
            Diagnostic::new(
                script,
                format!("the tree at {} has no command `{path}`", root.display()),
            )
        })
}

/// The type of the `$usage` record the command's script sees: every declared name is
/// there, an absent value `null` unless a default applies.
pub fn usage_type(command: &Command) -> String {
    let fields = |params: &[Param]| {
        params
            .iter()
            .map(|param| format!("{}: {}", param.key, param_type(param)))
            .collect::<Vec<_>>()
            .join(", ")
    };
    format!(
        "record<cmd: list<string>, args: record<{}>, flags: record<{}>>",
        fields(&command.positionals),
        fields(&command.flags)
    )
}

fn param_type(param: &Param) -> String {
    let ty = param.ty.as_str();
    let or_null = || {
        if param.default.is_some() {
            ty.to_string()
        } else {
            format!("oneof<{ty}, nothing>")
        }
    };
    match param.kind {
        ParamKind::Required => ty.to_string(),
        ParamKind::Optional | ParamKind::Valued => or_null(),
        ParamKind::Rest | ParamKind::Repeated => format!("list<{ty}>"),
        ParamKind::Switch => "bool".to_string(),
        ParamKind::Count => "int".to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Each helper's stand-in has the signature of the helper it stands in for.
    #[test]
    fn the_helpers_stand_ins_have_their_signatures() {
        let helpers = [crate::binary::HELPERS, crate::binary::DECODED].concat();
        let signature = |text: &str, name: &str| {
            let start = text.find(&format!("def \"{name}\" [")).unwrap();
            let text = &text[start..];
            let params_end = text.find("]: ").unwrap();
            let io_end = params_end + text[params_end..].find(" {").unwrap();
            text[..io_end]
                .chars()
                .filter(|c| !c.is_whitespace() && *c != ',')
                .collect::<String>()
        };
        for (name, stand_in) in HELPER_SIGNATURES {
            assert_eq!(
                signature(stand_in, name),
                signature(&helpers, name),
                "{name}"
            );
        }
    }
}
