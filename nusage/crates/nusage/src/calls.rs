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
//!
//! A task of mise's is called the same way, `mise run <task> ...` or `mise r <task> ...`:
//! when the file it runs is a script nusage runs, the call is shadowed too, and the shadow
//! runs the task through mise, with its dependencies, its environment and its tools, from
//! the caller's directory, which is where mise is asked what the name means
//! ([`crate::tasks`]). A task mise finds up to date does not run and returns nothing.
//! `^mise run` is still the external, and so is a call with mise's own flags before the
//! task; one that runs more tasks after `:::` needs the caret, or the shadow takes them for
//! the script's arguments.

use std::collections::BTreeMap;
use std::ops::Range;
use std::path::{Component, Path, PathBuf};

use nusage_model::{Command, CommandPath};
use nusage_nu::{
    CommandName, Def, Expr, Ident, Params, ScriptCall, Stmt, SyntaxError, Type, Word, word,
};
use nusage_spec::{Diagnostic, Texts};

use crate::binary::params_and_argv;
use crate::common::{Target, relative};

/// The variable a shadow sets for the script it runs: the file the interpreter writes the
/// script's value to, as NUON. The interpreter does not pass it on.
pub const OUTPUT_VAR: &str = "NUSAGE_OUTPUT_FILE";

/// The variable naming the script whose value the file is for: a program that runs it, as
/// mise does a task, may run other scripts before or after it. The interpreter does not pass
/// it on either.
pub const OUTPUT_SCRIPT_VAR: &str = "NUSAGE_OUTPUT_SCRIPT";

/// The helper a shadow runs its script with, which names that file and reads it back.
pub const CALL_HELPER: &str = include_str!("script-call.nu");

/// A command standing in for calls of one command of another script.
#[derive(Debug, Clone)]
pub struct Shadow {
    /// The call's words, as written, then the words of the called script's subcommand.
    pub name: String,
    /// The script the call names.
    pub target: PathBuf,
    /// What runs it.
    pub through: Through,
    /// The subcommand's words, which select it after the script on the interpreter's argv.
    pub words: Vec<String>,
    /// The command, as the module for the script's tree would define it.
    pub command: Command,
}

/// What a shadow runs its script through.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Through {
    /// The interpreter, with the script's path.
    Nusage,
    /// mise, as the task of this name, asked from the caller's directory.
    Mise { dir: PathBuf, task: String },
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

/// The calls of scripts in `source`, the text of the script at `path`, with each script it
/// calls read from `texts` when that holds it. A call whose script cannot be read as a
/// nusage script is left the external it is: running it says why, and so does a finding
/// here.
pub fn scan(path: &Path, source: &str, texts: &Texts) -> Calls {
    let mut calls = Calls::default();
    // Every call of a script names a `.nu` file or mise; most scripts have none to parse for.
    if !source.contains(".nu") && !source.contains("mise") {
        return calls;
    }
    let dir = path.parent().unwrap_or(Path::new(""));
    let mut shadows = BTreeMap::new();
    for call in nusage_nu::script_calls(source, path) {
        let (name, named, target, through) = match &call {
            ScriptCall::External { head, args } => {
                if let Some((name, named)) = named_script(head, args) {
                    let target = resolve(dir, &named.text);
                    if !target.is_file() && !texts.contains_key(&target) {
                        calls.findings.push(Finding {
                            span: named.span.clone(),
                            message: format!("{} is not a file", target.display()),
                        });
                        continue;
                    }
                    (name, named, target, Through::Nusage)
                } else if let Some((name, named)) = named_task(head, args) {
                    match crate::tasks::task(dir, &named.text) {
                        Ok(Some(task)) => (
                            name,
                            named,
                            task.file,
                            Through::Mise {
                                dir: dir.to_path_buf(),
                                task: task.name,
                            },
                        ),
                        Ok(None) => continue,
                        Err(message) => {
                            calls.findings.push(Finding {
                                span: named.span.clone(),
                                message,
                            });
                            continue;
                        }
                    }
                } else {
                    continue;
                }
            }
            ScriptCall::Run { path: named } => {
                if runs_with_nusage(&resolve(dir, &named.text), texts) {
                    calls.findings.push(Finding {
                        span: named.span.clone(),
                        message: format!(
                            "`run {}` hands the script this one's `$usage`, not the arguments \
                             after it; call it as `{}` instead, without `run`, to have them \
                             parsed",
                            named.text,
                            as_path(&named.text)
                        ),
                    });
                }
                continue;
            }
        };
        if !runs_with_nusage(&target, texts) {
            continue;
        }
        match commands_of(&target, texts) {
            Ok(commands) => {
                for (words, command) in commands {
                    let name = std::iter::once(name.as_str())
                        .chain(words.iter().map(String::as_str))
                        .collect::<Vec<_>>()
                        .join(" ");
                    shadows.entry(name.clone()).or_insert(Shadow {
                        name,
                        target: target.clone(),
                        through: through.clone(),
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

/// The call's name and the word naming its task, for `mise run <task>` and `mise r <task>`:
/// the task first after `run`, before any flag of mise's own.
fn named_task<'a>(head: &'a Word, args: &'a [Word]) -> Option<(String, &'a Word)> {
    let [run, task, ..] = args else {
        return None;
    };
    let named = head.text == "mise"
        && matches!(run.text.as_str(), "run" | "r")
        && !task.text.starts_with('-')
        && task.text != ":::";
    named.then(|| (format!("mise {} {}", run.text, task.text), task))
}

/// Whether Nushell runs the word as a path rather than looking it up as a name: relative to
/// here or to home, or absolute, and on Windows with a backslash too.
fn is_path(word: &str) -> bool {
    let prefixes: &[&str] = if cfg!(windows) {
        &["./", "../", "~/", ".\\", "..\\", "~\\"]
    } else {
        &["./", "../", "~/"]
    };
    prefixes.iter().any(|prefix| word.starts_with(prefix))
        || word.starts_with('/')
        || Path::new(word).is_absolute()
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
    let home = word
        .strip_prefix("~/")
        .or_else(|| word.strip_prefix("~\\").filter(|_| cfg!(windows)));
    let joined = match home {
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
    std::fs::read_to_string(path).is_ok_and(|source| names_nusage(&source))
}

/// Whether a script's text opens with a shebang naming nusage.
pub fn names_nusage(source: &str) -> bool {
    source.lines().next().is_some_and(|line| {
        line.strip_prefix("#!").is_some_and(|line| {
            line.split_whitespace()
                .any(|word| word == "nusage" || word.ends_with("/nusage"))
        })
    })
}

/// [`is_nusage_script`], for the text `texts` holds for the file when it holds one.
fn runs_with_nusage(path: &Path, texts: &Texts) -> bool {
    match texts.get(path) {
        Some(text) => names_nusage(text),
        None => is_nusage_script(path),
    }
}

/// The command the script is in its tree, and the commands below it, each with the words
/// that select it after the script.
fn commands_of(script: &Path, texts: &Texts) -> Result<Vec<(Vec<String>, Command)>, Diagnostic> {
    let (root, path) = place_in_tree(script)?;
    let assembled = nusage_spec::assemble_in(&root, texts)?;
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
    /// `nusage` and mise on `PATH`.
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
    // A path from the module's directory, as the module's own file has it.
    let mut from_module = |name: &str, path: &Path| -> Result<Expr, SyntaxError> {
        let Runner::Module(base) = runner else {
            return Ok(Expr::Str(path.to_string_lossy().into_owned()));
        };
        body.push(Stmt::Const {
            name: Ident::new(name)?,
            value: Expr::Raw(format!("path self {}", word(&relative(base, path)))),
        });
        Ok(Expr::Var(Ident::new(name)?))
    };
    let script = from_module("script", &shadow.target)?;
    let mut args = vec![script.clone()];
    match &shadow.through {
        Through::Nusage => args.extend([
            Expr::Str(match runner {
                Runner::Module(_) => "nusage".into(),
                Runner::Absolute(nusage) => nusage.to_string_lossy().into_owned(),
            }),
            script,
        ]),
        Through::Mise { dir, task } => args.extend([
            Expr::Str("mise".into()),
            // Quoted: bare, it would be a flag of `nusage call`'s own.
            Expr::Raw(r#""-C""#.into()),
            from_module("dir", dir)?,
            Expr::Str("run".into()),
            Expr::Str(task.clone()),
        ]),
    }
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

    #[test]
    fn the_forms_that_run_a_task() {
        let word = |text: &str| Word {
            text: text.into(),
            span: 0..text.len(),
        };
        let named = |head: &str, args: &[&str]| {
            let args: Vec<Word> = args.iter().map(|arg| word(arg)).collect();
            named_task(&word(head), &args).map(|(name, task)| (name, task.text.clone()))
        };
        assert_eq!(
            named("mise", &["run", "build", "--release"]),
            Some(("mise run build".into(), "build".into()))
        );
        assert_eq!(
            named("mise", &["r", "//app:test"]),
            Some(("mise r //app:test".into(), "//app:test".into()))
        );
        // mise's own flags before the task, no task, or another command of mise's.
        assert_eq!(named("mise", &["run", "-q", "build"]), None);
        assert_eq!(named("mise", &["run"]), None);
        assert_eq!(named("mise", &["tasks", "build"]), None);
        assert_eq!(named("nu", &["run", "build"]), None);
    }

    #[test]
    fn a_task_runs_through_mise_from_the_callers_directory() {
        let fixture = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../fixtures/script-calls");
        let callee = fixture.join("callee.nu");
        let (words, command) = commands_of(&callee, &Texts::new()).unwrap().remove(0);
        let shadow = Shadow {
            name: "mise run greet".into(),
            target: callee.clone(),
            through: Through::Mise {
                dir: fixture.clone(),
                task: "greet".into(),
            },
            words,
            command,
        };
        let module = nusage_nu::print_line(
            &shadow_def(&shadow, Runner::Module(&fixture.join("expected"))).unwrap(),
        );
        assert!(
            module.contains(
                r#"const script = path self "../callee.nu"; const dir = path self ".."; $in | nusage call $script mise "-C" $dir run greet ...(nusage argv"#
            ),
            "{module}"
        );
        let absolute = nusage_nu::print_line(
            &shadow_def(&shadow, Runner::Absolute(Path::new("/bin/nusage"))).unwrap(),
        );
        assert!(
            absolute.contains(&format!(
                "nusage call {} mise \"-C\" {} run greet ...(",
                word(&callee.to_string_lossy()),
                word(&fixture.to_string_lossy())
            )),
            "{absolute}"
        );
    }

    #[test]
    fn a_backslash_makes_a_path_on_windows_alone() {
        // Elsewhere it is a character of the name, which Nushell looks up on PATH.
        for word in [".\\x.nu", "..\\x.nu", "~\\x.nu"] {
            assert_eq!(is_path(word), cfg!(windows), "{word}");
        }
        assert!(is_path("/x.nu"));
        if cfg!(windows) {
            assert!(is_path("C:\\x.nu"));
        }
    }
}
