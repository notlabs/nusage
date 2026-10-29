//! Scripts that call scripts. A script calls another the way it calls a binary, by its path:
//! `./x.nu ...`, `nusage x.nu ...` or `nu x.nu ...`, and Nushell types none of them: an
//! external call returns text, whatever the script returned. So a call of a script whose
//! shebang names nusage is shadowed by a command named as the call writes it, which is that
//! script's typed wrapper: its signature is the script's header, and it runs the script
//! through the interpreter, which hands the value back as NUON, of the type the script's
//! output declares. The value comes back through a file the call names, so what the script
//! prints passes through as any command's does. The shadows are defined where the script
//! runs, by the interpreter and by the module, and stand in its first line where Nushell
//! checks it, so what is checked is what runs. `^./x.nu` is still the external, and its text.
//!
//! A path is the caller's: `./x.nu` names the script beside the caller, wherever it runs
//! from. `run x.nu` cannot be shadowed, being Nushell's keyword, and hands a nusage script
//! the caller's `$usage` rather than the arguments after it; it is reported, not shadowed.

use std::collections::BTreeMap;
use std::ops::Range;
use std::path::{Component, Path, PathBuf};

use nusage_model::{Command, CommandPath};
use nusage_nu::{
    CommandName, Def, Expr, Ident, Params, ScriptCall, Stmt, SyntaxError, Type, Word, word,
};
use nusage_spec::Diagnostic;

use crate::binary::params_and_argv;
use crate::common::{Target, relative};

/// The variable a shadow sets for the script it runs: the file the interpreter writes the
/// script's value to, as NUON. The interpreter does not pass it on.
pub const OUTPUT_VAR: &str = "NUSAGE_OUTPUT_FILE";

/// The helper a shadow runs its script with, which names that file and reads it back.
pub const CALL_HELPER: &str = include_str!("script-call.nu");

/// A command standing in for calls of one command of another script.
#[derive(Debug, Clone)]
pub struct Shadow {
    /// The call's words, as written, then the words of the called script's subcommand.
    pub name: String,
    /// The script the call names.
    pub target: PathBuf,
    /// The subcommand's words, which select it after the script on the interpreter's argv.
    pub words: Vec<String>,
    /// The command, as the module for the script's tree would define it.
    pub command: Command,
}

/// Something about a call that a reader should know, at its byte range in the script.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Finding {
    pub span: Range<usize>,
    pub message: String,
}

/// The shadows a script needs, one per name, and what its calls of scripts got wrong.
#[derive(Debug, Clone, Default)]
pub struct Calls {
    pub shadows: Vec<Shadow>,
    pub findings: Vec<Finding>,
}

/// The calls of scripts in `source`, the text of the script at `path`. A call whose script
/// cannot be read as a nusage script is left the external it is: running it says why, and
/// so does a finding here.
pub fn scan(path: &Path, source: &str) -> Calls {
    let mut calls = Calls::default();
    // Every call of a script names a `.nu` file; most scripts have none to parse for.
    if !source.contains(".nu") {
        return calls;
    }
    let dir = path.parent().unwrap_or(Path::new(""));
    let mut shadows = BTreeMap::new();
    for call in nusage_nu::script_calls(source, path) {
        let (name, named) = match &call {
            ScriptCall::External { head, args } => match named_script(head, args) {
                Some(found) => found,
                None => continue,
            },
            ScriptCall::Run { path: named } => {
                if is_nusage_script(&resolve(dir, &named.text)) {
                    calls.findings.push(Finding {
                        span: named.span.clone(),
                        message: format!(
                            "`run` hands {} this script's `$usage`, not the arguments after \
                             it; call it by its path, `{}`, to have them parsed",
                            named.text,
                            as_path(&named.text)
                        ),
                    });
                }
                continue;
            }
        };
        let target = resolve(dir, &named.text);
        if !target.is_file() {
            calls.findings.push(Finding {
                span: named.span.clone(),
                message: format!("{} is not a file", target.display()),
            });
            continue;
        }
        if !is_nusage_script(&target) {
            continue;
        }
        match commands_of(&target) {
            Ok(commands) => {
                for (words, command) in commands {
                    let name = std::iter::once(name.as_str())
                        .chain(words.iter().map(String::as_str))
                        .collect::<Vec<_>>()
                        .join(" ");
                    shadows.entry(name.clone()).or_insert(Shadow {
                        name,
                        target: target.clone(),
                        words,
                        command,
                    });
                }
            }
            Err(err) => calls.findings.push(Finding {
                span: named.span.clone(),
                message: err.to_string(),
            }),
        }
    }
    calls.shadows = shadows.into_values().collect();
    calls
}

/// The call's name and the word naming its script, for the forms that call a script:
/// a path to one, or `nusage` or `nu` with one.
fn named_script<'a>(head: &'a Word, args: &'a [Word]) -> Option<(String, &'a Word)> {
    if head.text.ends_with(".nu") && is_path(&head.text) {
        return Some((head.text.clone(), head));
    }
    let script = args.first().filter(|arg| arg.text.ends_with(".nu"))?;
    matches!(head.text.as_str(), "nusage" | "nu")
        .then(|| (format!("{} {}", head.text, script.text), script))
}

/// Whether Nushell runs the word as a path rather than looking it up as a name.
fn is_path(word: &str) -> bool {
    ["./", "../", "/", "~/"]
        .iter()
        .any(|prefix| word.starts_with(prefix))
}

/// The word as a path call: `./x.nu` for `x.nu`.
fn as_path(word: &str) -> String {
    if is_path(word) {
        word.to_string()
    } else {
        format!("./{word}")
    }
}

/// A path as the caller wrote it, against the caller's directory, folded without touching
/// the filesystem: `~` is the home directory.
fn resolve(dir: &Path, word: &str) -> PathBuf {
    let joined = match word.strip_prefix("~/") {
        Some(rest) => std::env::home_dir().unwrap_or_default().join(rest),
        None => dir.join(word),
    };
    let absolute = std::path::absolute(&joined).unwrap_or(joined);
    let mut out = PathBuf::new();
    for component in absolute.components() {
        match component {
            Component::CurDir => {}
            Component::ParentDir => {
                out.pop();
            }
            other => out.push(other),
        }
    }
    out
}

/// Whether the file is a script run by nusage: its shebang names it.
pub fn is_nusage_script(path: &Path) -> bool {
    let Ok(source) = std::fs::read_to_string(path) else {
        return false;
    };
    source.lines().next().is_some_and(|line| {
        line.strip_prefix("#!").is_some_and(|line| {
            line.split_whitespace()
                .any(|word| word == "nusage" || word.ends_with("/nusage"))
        })
    })
}

/// The command the script is in its tree, and the commands below it, each with the words
/// that select it after the script.
fn commands_of(script: &Path) -> Result<Vec<(Vec<String>, Command)>, Diagnostic> {
    let (root, path) = place_in_tree(script)?;
    let assembled = nusage_spec::assemble(&root)?;
    let tree = nusage_model::model(&assembled)?;
    let depth = path.words().len();
    Ok(tree
        .commands
        .into_iter()
        .filter(|command| command.path.words().starts_with(path.words()))
        .map(|command| (command.path.words()[depth..].to_vec(), command))
        .collect())
}

/// Where the script stands: the root of the tree it belongs to and its path in it, or the
/// script itself and the root path when no `mod.nu` lies beside it. The tree's root is the
/// outermost directory that has a `mod.nu` in each directory down to the script's.
pub fn place_in_tree(script: &Path) -> Result<(PathBuf, CommandPath), Diagnostic> {
    let script = std::path::absolute(script)
        .map_err(|err| Diagnostic::new(script, format!("cannot resolve: {err}")))?;
    let Some(mut dir) = script.parent().filter(|dir| dir.join("mod.nu").is_file()) else {
        return Ok((script, CommandPath::root()));
    };
    while let Some(parent) = dir
        .parent()
        .filter(|parent| parent.join("mod.nu").is_file())
    {
        dir = parent;
    }
    let mut words: Vec<String> = script
        .strip_prefix(dir)
        .map_err(|_| Diagnostic::new(&script, "not inside its tree"))?
        .components()
        .map(|component| component.as_os_str().to_string_lossy().into_owned())
        .collect();
    // `db/migrate.nu` is `db migrate`; `db/mod.nu` is `db`.
    if let Some(last) = words.pop()
        && last != "mod.nu"
    {
        words.push(last.trim_end_matches(".nu").to_string());
    }
    let path = words
        .iter()
        .fold(CommandPath::root(), |path, word| path.child(word));
    Ok((dir.to_path_buf(), path))
}

/// How a shadow reaches the script it runs.
#[derive(Debug, Clone, Copy)]
pub enum Runner<'a> {
    /// From a module in this directory: the script relative to the module's file, and the
    /// `nusage` on `PATH`.
    Module(&'a Path),
    /// The script by its absolute path, run by this `nusage`, a path or a name on `PATH`: for
    /// the interpreter, and for the line that stands in for a script's first.
    Absolute(&'a Path),
}

/// The shadow as a definition: the called command's parameters, as a wrapper of a binary
/// has them, and a body that hands its input and argv to [`CALL_HELPER`]'s `nusage call`.
pub fn shadow_def(shadow: &Shadow, runner: Runner) -> Result<Def, SyntaxError> {
    let (params, argv) = params_and_argv(&shadow.command, Target::Call)?;
    let mut body = Vec::new();
    let (program, script) = match runner {
        Runner::Module(base) => {
            body.push(Stmt::Const {
                name: Ident::new("script")?,
                value: Expr::Raw(format!(
                    "path self {}",
                    word(&relative(base, &shadow.target))
                )),
            });
            (Expr::Str("nusage".into()), Expr::Var(Ident::new("script")?))
        }
        Runner::Absolute(nusage) => (
            Expr::Str(nusage.to_string_lossy().into_owned()),
            Expr::Str(shadow.target.to_string_lossy().into_owned()),
        ),
    };
    let mut args = vec![program, script];
    args.extend(shadow.words.iter().cloned().map(Expr::Str));
    args.push(Expr::Spread(Box::new(argv)));
    body.push(Stmt::Pipeline(vec![
        Expr::Var(Ident::new("in")?),
        Expr::Call {
            name: CommandName::new("nusage call")?,
            args,
        },
    ]));
    Ok(Def {
        export: false,
        doc: Vec::new(),
        attrs: Vec::new(),
        name: CommandName::new(&shadow.name)?,
        params: Params::new(params)?,
        io: io(&shadow.command)?,
        body,
    })
}

/// A script takes no input of its own and returns what its output declares.
fn io(command: &Command) -> Result<Option<(Type, Type)>, SyntaxError> {
    Ok(match &command.output {
        Some(output) => Some((Type::new("nothing")?, Type::new(output.as_str())?)),
        None => None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn paths_are_the_callers() {
        let dir = Path::new("/a/b");
        assert_eq!(resolve(dir, "./x.nu"), Path::new("/a/b/x.nu"));
        assert_eq!(resolve(dir, "x.nu"), Path::new("/a/b/x.nu"));
        assert_eq!(resolve(dir, "../c/./x.nu"), Path::new("/a/c/x.nu"));
        assert_eq!(resolve(dir, "/d/x.nu"), Path::new("/d/x.nu"));
    }

    #[test]
    fn the_forms_that_call_a_script() {
        let word = |text: &str| Word {
            text: text.into(),
            span: 0..text.len(),
        };
        let named = |head: &str, args: &[&str]| {
            let args: Vec<Word> = args.iter().map(|arg| word(arg)).collect();
            named_script(&word(head), &args).map(|(name, script)| (name, script.text.clone()))
        };
        assert_eq!(
            named("./x.nu", &["--flag"]),
            Some(("./x.nu".into(), "./x.nu".into()))
        );
        assert_eq!(
            named("nu", &["x.nu", "sub"]),
            Some(("nu x.nu".into(), "x.nu".into()))
        );
        assert_eq!(
            named("nusage", &["../y.nu"]),
            Some(("nusage ../y.nu".into(), "../y.nu".into()))
        );
        // A bare name is looked up on PATH, and `nu` with something else is not a script.
        assert_eq!(named("x.nu", &[]), None);
        assert_eq!(named("nu", &["-c", "x.nu"]), None);
        assert_eq!(as_path("x.nu"), "./x.nu");
        assert_eq!(as_path("../x.nu"), "../x.nu");
    }
}
