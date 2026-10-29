//! What a script has before its first line. Where it runs, the interpreter defines the
//! shadows of the scripts it calls ([`crate::calls`]) and binds `$usage`; where Nushell
//! checks it, as an editor does, one line stands in for the script's first, the shebang,
//! saying the same: `$usage` with its type, and the shadows as the interpreter defines them,
//! less the helpers they call. Replacing a line with a line keeps every other line where it
//! was.

use std::path::Path;

use nusage_model::{Command, Param, ParamKind};
use nusage_nu::{Item, Module, SyntaxError};
use nusage_spec::Diagnostic;

use crate::binary::HELPERS;
use crate::calls::{self, CALL_HELPER, Calls, Runner};

/// The line that stands in for the script's first, and what the script's calls of scripts
/// got wrong. The script must be one nusage runs: its shebang names it.
pub fn line(script: &Path) -> Result<(String, Calls), Diagnostic> {
    let source = read(script)?;
    if !calls::is_nusage_script(script) {
        return Err(Diagnostic::new(
            script,
            "not a script nusage runs: its first line is no shebang naming nusage",
        )
        .at_line(1));
    }
    let command = command_of(script)?;
    let calls = calls::scan(script, &source);
    let mut parts = vec![format!(
        "let usage: {} = ($env.NUSAGE_USAGE? | default \"{{}}\" | from nuon)",
        usage_type(&command)
    )];
    // Made for each check, never kept, so it can name the script where it is.
    for shadow in &calls.shadows {
        let def = calls::shadow_def(shadow, Runner::Absolute(Path::new("nusage")))
            .map_err(|err| syntax(script, err))?;
        parts.push(nusage_nu::print_line(&def));
    }
    Ok((parts.join("; "), calls))
}

/// The Nushell the interpreter runs before the script: the helpers and the shadows, which
/// run the scripts they stand for with this `nusage`. Empty when the script calls none.
pub fn runtime(script: &Path, nusage: &Path) -> Result<String, Diagnostic> {
    let source = read(script)?;
    let calls = calls::scan(script, &source);
    if calls.shadows.is_empty() {
        return Ok(String::new());
    }
    let mut items = vec![
        Item::Verbatim(HELPERS.to_string()),
        Item::Verbatim(CALL_HELPER.to_string()),
    ];
    for shadow in &calls.shadows {
        let def = calls::shadow_def(shadow, Runner::Absolute(nusage))
            .map_err(|err| syntax(script, err))?;
        items.push(Item::Def(def));
    }
    Ok(nusage_nu::print(&Module {
        preamble: Vec::new(),
        items,
    }))
}

fn read(script: &Path) -> Result<String, Diagnostic> {
    std::fs::read_to_string(script)
        .map_err(|err| Diagnostic::new(script, format!("cannot read: {err}")))
}

fn syntax(script: &Path, err: SyntaxError) -> Diagnostic {
    Diagnostic::new(script, err.to_string())
}

/// The command the script is in its tree.
fn command_of(script: &Path) -> Result<Command, Diagnostic> {
    let (root, path) = calls::place_in_tree(script)?;
    let assembled = nusage_spec::assemble(&root)?;
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
