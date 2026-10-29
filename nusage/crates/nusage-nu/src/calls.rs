//! The calls in a script that may run another script, as Nushell's parser reads them: what is
//! an external command and what is a definition is the parser's decision, not a pattern's.

use std::ops::Range;
use std::path::Path;

use nu_protocol::ast::{Expr, Expression, ExternalArgument, Traverse};
use nu_protocol::engine::StateWorkingSet;
use nu_protocol::{Span, Value};

use crate::check::ENGINE;

/// A word of the script as written, at its byte range in the source.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Word {
    pub text: String,
    pub span: Range<usize>,
}

/// A call that may run a script.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ScriptCall {
    /// An external command: its head and the bare words right after it, up to the first word
    /// that is not one. A head written `^x` says the external is meant and is left out.
    External { head: Word, args: Vec<Word> },
    /// `run <path>`, with the path as written.
    Run { path: Word },
}

/// The script's calls that may run a script, in source order, nested blocks included: a
/// definition's body, a closure, a subexpression. `file` is where the script lives, for what
/// the parser resolves at parse time. A script that does not parse still has calls to read;
/// its errors are Nushell's to report.
pub fn script_calls(source: &str, file: &Path) -> Vec<ScriptCall> {
    let mut engine_state = ENGINE.clone();
    let dir = file.parent().unwrap_or(Path::new(""));
    engine_state.add_env_var(
        "PWD".into(),
        Value::string(dir.to_string_lossy(), Span::unknown()),
    );
    let mut working_set = StateWorkingSet::new(&engine_state);
    let offset = working_set.next_span_start();
    let block = nu_parser::parse(
        &mut working_set,
        Some(&file.to_string_lossy()),
        source.as_bytes(),
        false,
    );
    let working_set = &working_set;
    let word = |expr: &Expression| bare_word(source, offset, expr);
    let mut calls = Vec::new();
    block.flat_map(
        working_set,
        &|expr: &Expression| match &expr.expr {
            Expr::ExternalCall(head, args) => {
                let Some(head) = word(head) else {
                    return Vec::new();
                };
                if source[..head.span.start].ends_with('^') {
                    return Vec::new();
                }
                let args = args
                    .iter()
                    .map_while(|arg| match arg {
                        ExternalArgument::Regular(expr) => word(expr),
                        ExternalArgument::Spread(_) => None,
                    })
                    .collect();
                vec![ScriptCall::External { head, args }]
            }
            Expr::Call(call) if working_set.get_decl(call.decl_id).name() == "run" => call
                .positional_iter()
                .next()
                .and_then(word)
                .map(|path| ScriptCall::Run { path })
                .into_iter()
                .collect(),
            _ => Vec::new(),
        },
        &mut calls,
    );
    calls
}

/// The expression as a word written bare, as Nushell reads a path or a name: not quoted, not
/// interpolated, not a variable.
fn bare_word(source: &str, offset: usize, expr: &Expression) -> Option<Word> {
    if !matches!(
        expr.expr,
        Expr::String(_) | Expr::GlobPattern(..) | Expr::Filepath(..)
    ) {
        return None;
    }
    let span = expr.span.start.checked_sub(offset)?..expr.span.end.checked_sub(offset)?;
    let text = source.get(span.clone())?;
    if text.is_empty() || text.starts_with(['"', '\'', '`']) {
        return None;
    }
    Some(Word {
        text: text.to_string(),
        span,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn calls(source: &str) -> Vec<ScriptCall> {
        script_calls(source, Path::new("/nowhere/script.nu"))
    }

    fn texts(call: &ScriptCall) -> Vec<&str> {
        match call {
            ScriptCall::External { head, args } => std::iter::once(head)
                .chain(args)
                .map(|word| word.text.as_str())
                .collect(),
            ScriptCall::Run { path } => vec!["run", path.text.as_str()],
        }
    }

    #[test]
    fn external_heads_and_their_bare_words() {
        let source = "let a = ./x.nu --count 1 | length\n\
                      nu ../y.nu sub $a\n\
                      def main [] { [1] | each { nusage z.nu \"quoted\" } }\n\
                      ^./skip.nu\n\
                      run w.nu --flag\n";
        let calls = calls(source);
        let found: Vec<Vec<&str>> = calls.iter().map(texts).collect();
        assert_eq!(
            found,
            [
                vec!["./x.nu", "--count", "1"],
                vec!["nu", "../y.nu", "sub"],
                vec!["nusage", "z.nu"],
                vec!["run", "w.nu"],
            ]
        );
        // The spans are the source's.
        let ScriptCall::External { head, .. } = &calls[0] else {
            panic!("an external call");
        };
        assert_eq!(&source[head.span.clone()], "./x.nu");
    }

    #[test]
    fn a_definition_is_not_an_external() {
        let source = "def \"./x.nu\" [] { 1 }\n./x.nu\n";
        assert_eq!(calls(source), []);
    }
}
