use std::path::Path;
use std::sync::LazyLock;

use nu_protocol::engine::{EngineState, StateWorkingSet};
use nu_protocol::{DeclId, Span, Value};

use crate::SyntaxError;

/// Nushell's parser with its commands, so calls in a module resolve and type-check.
pub(crate) static ENGINE: LazyLock<EngineState> =
    LazyLock::new(|| nu_command::add_shell_command_context(nu_cmd_lang::create_default_context()));

/// Whether Nushell parses the module, as `use <name>.nu` would: the source is parsed inside
/// `module <name> { }`, which is where Nushell also rejects a definition named after the
/// module or a parser keyword, or a parameter named like a built-in variable. `dir` is where
/// the module file will live, for what the parser resolves at parse time: `run`'s path, and
/// `path self`, which is the file's own. The error names the line of generated Nushell at
/// fault.
pub fn check_module(name: &str, source: &str, dir: Option<&Path>) -> Result<(), SyntaxError> {
    with_module(name, source, dir, |_| ())
}

/// A definition of a parsed module, as Nushell sees it: what `scope commands` reports.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Decl {
    pub name: String,
    /// The first paragraph of its doc comment.
    pub description: String,
    /// The rest of its doc comment.
    pub extra_description: String,
    pub required: Vec<DeclArg>,
    pub optional: Vec<DeclArg>,
    pub rest: Option<DeclArg>,
    pub flags: Vec<DeclFlag>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeclArg {
    pub name: String,
    pub completer: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeclFlag {
    pub long: String,
    pub short: Option<char>,
    pub takes_value: bool,
    pub completer: bool,
}

/// The definitions the module declares, as Nushell parses them, after [`check_module`]'s
/// check. Nushell's own `--help` flag is left out.
pub fn signatures(name: &str, source: &str, dir: Option<&Path>) -> Result<Vec<Decl>, SyntaxError> {
    with_module(name, source, dir, |working_set| {
        (ENGINE.num_decls()..working_set.num_decls())
            .map(|id| {
                let sig = working_set.get_decl(DeclId::new(id)).signature();
                let arg = |arg: &nu_protocol::PositionalArg| DeclArg {
                    name: arg.name.clone(),
                    completer: arg.completion.is_some(),
                };
                Decl {
                    name: sig.name.clone(),
                    description: sig.description.clone(),
                    extra_description: sig.extra_description.clone(),
                    required: sig.required_positional.iter().map(arg).collect(),
                    optional: sig.optional_positional.iter().map(arg).collect(),
                    rest: sig.rest_positional.as_ref().map(arg),
                    flags: sig
                        .named
                        .iter()
                        .filter(|flag| flag.long != "help")
                        .map(|flag| DeclFlag {
                            long: flag.long.clone(),
                            short: flag.short,
                            takes_value: flag.arg.is_some(),
                            completer: flag.completion.is_some(),
                        })
                        .collect(),
                }
            })
            .collect()
    })
}

/// Parse the module as [`check_module`] describes and hand the parsed state to `read`, or
/// the first parse error, naming the line of generated Nushell at fault.
fn with_module<T>(
    name: &str,
    source: &str,
    dir: Option<&Path>,
    read: impl FnOnce(&StateWorkingSet<'_>) -> T,
) -> Result<T, SyntaxError> {
    let mut engine_state = ENGINE.clone();
    // The parser resolves against `PWD` as an absolute path.
    let dir = dir
        .and_then(|dir| std::path::absolute(dir).ok())
        .or_else(|| std::env::current_dir().ok())
        .unwrap_or_default();
    engine_state.add_env_var(
        "PWD".into(),
        Value::string(dir.to_string_lossy(), Span::unknown()),
    );
    let mut working_set = StateWorkingSet::new(&engine_state);
    let wrapped = format!("module {name} {{\n{source}\n}}\n");
    // `use` pushes the module's file for `path self` to find; a bare parse must too.
    let file = dir.join(format!("{name}.nu"));
    working_set
        .files
        .push(file.clone(), Span::unknown())
        .map_err(|err| SyntaxError(format!("cannot stage {}: {err}", file.display())))?;
    nu_parser::parse(
        &mut working_set,
        Some(&file.to_string_lossy()),
        wrapped.as_bytes(),
        false,
    );
    let Some(err) = working_set.parse_errors.first() else {
        return Ok(read(&working_set));
    };
    // The wrapper adds one line above the module's own.
    let line = wrapped[..err.span().start.min(wrapped.len())]
        .matches('\n')
        .count();
    let text = wrapped.lines().nth(line).unwrap_or("").trim();
    Err(SyntaxError(format!(
        "Nushell does not parse the generated module (line {line}: `{text}`): {err}"
    )))
}

/// Whether Nushell reserves the name for one of its own variables, such as `env`, `in` and
/// `nu`, so that no parameter can be called that. nu-parser keeps the list private; it is
/// asked through `let`.
pub fn reserved_variable(name: &str) -> bool {
    let mut working_set = StateWorkingSet::new(&ENGINE);
    let source = format!("let {name} = 1");
    nu_parser::parse(&mut working_set, None, source.as_bytes(), false);
    working_set
        .parse_errors
        .iter()
        .any(|err| matches!(err, nu_protocol::ParseError::NameIsBuiltinVar(..)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nushell_reserves_its_own_variables() {
        assert!(reserved_variable("env"));
        assert!(reserved_variable("in"));
        assert!(reserved_variable("nu"));
        assert!(!reserved_variable("environment"));
        assert!(!reserved_variable("env_"));
    }

    #[test]
    fn a_module_that_parses_passes() {
        assert!(check_module("m", "export def main [x: int] { $x }", None).is_ok());
    }

    #[test]
    fn nushell_rejections_are_reported_with_their_line() {
        let err = check_module("m", "export def run [] { 1 }", None).unwrap_err();
        assert!(
            err.0.contains("line 1") && err.0.contains("keyword"),
            "{err}"
        );
        let err = check_module("m", "export def main [--env] { 1 }", None).unwrap_err();
        assert!(err.0.contains("variable name"), "{err}");
        let err = check_module("m", "export def m [] { 1 }", None).unwrap_err();
        assert!(err.0.contains("module"), "{err}");
    }
}
