//! Scripts that call scripts. A script calls another the way it calls a binary, by its path:
//! `./x.nu ...`, `nus x.nu ...` or `nu x.nu ...`, and Nushell types none of them: an
//! external call returns text, whatever the script returned. So a call of a script whose
//! shebang names nusage is shadowed by a command named as the call writes it, which is that
//! script's typed command: its signature is the script's header, and its body binds `$usage`
//! from its parameters and `run`s the script, which returns its value in the caller's own
//! Nushell, of the type its output declares, while what it prints passes through. The
//! shadows of the scripts the called script calls are defined inside that body, since a
//! call's path is its script's, and `run` reads a script's calls where it parses it. The
//! shadows are defined where the script runs, by the interpreter and by the module, and
//! stand in its first line where Nushell checks it, so what is checked is what runs.
//! `^./x.nu` is still the external, and its text.
//!
//! A path is the caller's: `./x.nu` names the script beside the caller, wherever it runs
//! from. `run x.nu` hands a nusage script the caller's `$usage` rather than the arguments
//! after it; it is reported, not shadowed.
//!
//! Calls may go round, a script calling itself or two calling each other. A script met
//! again on the way down is not read again: its definition `run`s it, and its own calls are
//! the definitions already around it, which Nushell finds where it parses the script. That
//! holds as long as each of those names the script the call names there; where one does
//! not, the call is left the external it is, and a finding says why.

use std::collections::BTreeMap;
use std::ops::Range;
use std::path::{Component, Path, PathBuf};

use nusage_model::{Command, CommandPath, Execution};
use nusage_nu::{CommandName, Def, Expr, Ident, Params, ScriptCall, Stmt, SyntaxError, Type, Word};
use nusage_spec::{Diagnostic, Texts};

use crate::common::{Target, nu_params, relative, usage_record};

/// A command standing in for calls of one command of another script.
#[derive(Debug, Clone)]
pub struct Shadow {
    /// The call's words, as written, then the words of the called script's subcommand.
    pub name: String,
    /// The script the call names.
    pub target: PathBuf,
    /// The command, as the module for the script's tree would define it.
    pub command: Command,
    /// Where the first call of it names its script, in the caller.
    pub at: Range<usize>,
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
        let target = resolve(dir, &named.text);
        if !target.is_file() && !texts.contains_key(&target) {
            calls.findings.push(Finding {
                span: named.span.clone(),
                message: format!("{} is not a file", target.display()),
            });
            continue;
        }
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
                        command,
                        at: named.span.clone(),
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
/// a path to one, or `nus` or `nu` with one.
fn named_script<'a>(head: &'a Word, args: &'a [Word]) -> Option<(String, &'a Word)> {
    if head.text.ends_with(".nu") && is_path(&head.text) {
        return Some((head.text.clone(), head));
    }
    let script = args.first().filter(|arg| arg.text.ends_with(".nu"))?;
    matches!(head.text.as_str(), "nus" | "nu")
        .then(|| (format!("{} {}", head.text, script.text), script))
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
                .any(|word| word == "nus" || word.ends_with("/nus"))
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

/// How the scripts the definitions `run` are written.
#[derive(Debug, Clone, Copy)]
pub enum Paths<'a> {
    /// Relative to the directory of the module the definitions are in, as Nushell reads a
    /// `run` from that file.
    From(&'a Path),
    /// Absolute: for the interpreter, and for the line that stands in for a script's first.
    Absolute,
}

/// Why a definition could not be written.
#[derive(Debug)]
pub enum Unwritten {
    Syntax(SyntaxError),
    /// A script its definition would run, which cannot be read.
    Unreadable {
        script: PathBuf,
        why: String,
    },
    /// A script met again on the way down calls `name`, and the definition of that name
    /// around it is another script's, or none.
    Round {
        script: PathBuf,
        name: String,
    },
}

impl std::fmt::Display for Unwritten {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Unwritten::Syntax(err) => write!(f, "{err}"),
            Unwritten::Unreadable { script, why } => write!(f, "{}: {why}", script.display()),
            Unwritten::Round { script, name } => write!(
                f,
                "the calls come back round to {}, whose `{name}` would reach another script \
                 there; the call is left the external it is",
                script.display()
            ),
        }
    }
}

impl From<SyntaxError> for Unwritten {
    fn from(err: SyntaxError) -> Self {
        Unwritten::Syntax(err)
    }
}

/// The definitions of the shadows of `calls`, the calls of the script at `script`, as they
/// stand before the script: each with the definitions its own script needs inside its body.
/// A shadow whose definition cannot be written is taken out of `calls`, the call left the
/// external it is, and what kept it out joins the findings at its call; the definitions
/// follow the shadows that remain, one each, in order.
pub fn definitions(script: &Path, calls: &mut Calls, paths: Paths, texts: &Texts) -> Vec<Def> {
    let mut writer = Writer::new(paths, texts);
    writer.chain.push(script.to_path_buf());
    writer.scope.push(names(&calls.shadows));
    let mut defs = Vec::new();
    let mut kept = Vec::new();
    for shadow in std::mem::take(&mut calls.shadows) {
        match writer.def(&shadow) {
            Ok(def) => {
                defs.push(def);
                kept.push(shadow);
            }
            Err(why) => calls.findings.push(Finding {
                span: shadow.at.clone(),
                message: why.to_string(),
            }),
        }
    }
    calls.shadows = kept;
    defs
}

/// The body of a definition that runs `command`'s script: the definitions of the scripts
/// it calls, `$usage` from the definition's parameters, and the script `run` with the
/// definition's input.
pub fn script_body(command: &Command, paths: Paths, texts: &Texts) -> Result<Vec<Stmt>, Unwritten> {
    Writer::new(paths, texts).body(command)
}

/// What the definitions are written with: the scripts the definition being written sits
/// inside, outermost first, and the names each of them defines around it.
struct Writer<'a> {
    paths: Paths<'a>,
    texts: &'a Texts,
    chain: Vec<PathBuf>,
    scope: Vec<Vec<(String, PathBuf)>>,
}

impl<'a> Writer<'a> {
    fn new(paths: Paths<'a>, texts: &'a Texts) -> Self {
        Writer {
            paths,
            texts,
            chain: Vec::new(),
            scope: Vec::new(),
        }
    }

    fn def(&mut self, shadow: &Shadow) -> Result<Def, Unwritten> {
        let params = shadow
            .command
            .positionals
            .iter()
            .chain(shadow.command.flags.iter())
            .map(|param| nu_params(param, Target::Call))
            .collect::<Result<Vec<_>, _>>()?
            .concat();
        Ok(Def {
            export: false,
            doc: Vec::new(),
            attrs: Vec::new(),
            name: CommandName::new(&shadow.name)?,
            params: Params::new(params)?,
            io: io(&shadow.command)?,
            body: self.body(&shadow.command)?,
        })
    }

    fn body(&mut self, command: &Command) -> Result<Vec<Stmt>, Unwritten> {
        let script = script_of(command)?;
        let mut body = Vec::new();
        if self.chain.contains(&script) {
            // Met again: Nushell finds its calls among the definitions around it.
            let shadows = self.shadows_of(&script)?;
            for shadow in &shadows {
                let around = self
                    .scope
                    .iter()
                    .rev()
                    .flatten()
                    .find(|(name, _)| name == &shadow.name);
                if around.map(|(_, target)| target) != Some(&shadow.target) {
                    return Err(Unwritten::Round {
                        script,
                        name: shadow.name.clone(),
                    });
                }
            }
        } else {
            let shadows = self.shadows_of(&script)?;
            self.chain.push(script.clone());
            self.scope.push(names(&shadows));
            let defs = shadows
                .iter()
                .map(|shadow| self.def(shadow))
                .collect::<Result<Vec<_>, _>>();
            self.scope.pop();
            self.chain.pop();
            body.extend(defs?.into_iter().map(|def| Stmt::Def(Box::new(def))));
        }
        body.push(Stmt::Let {
            name: Ident::new("usage")?,
            value: usage_record(command)?,
        });
        body.push(Stmt::Pipeline(vec![
            Expr::Var(Ident::new("in")?),
            Expr::Call {
                name: CommandName::new("run")?,
                args: vec![Expr::Str(self.path(&script))],
            },
        ]));
        Ok(body)
    }

    /// The shadows the script's own calls need, its text read from `texts` when it holds it.
    fn shadows_of(&self, script: &Path) -> Result<Vec<Shadow>, Unwritten> {
        let source = match self.texts.get(script) {
            Some(text) => text.clone(),
            None => std::fs::read_to_string(script).map_err(|err| Unwritten::Unreadable {
                script: script.to_path_buf(),
                why: err.to_string(),
            })?,
        };
        Ok(scan(script, &source, self.texts).shadows)
    }

    fn path(&self, script: &Path) -> String {
        match self.paths {
            Paths::From(base) => relative(base, script),
            Paths::Absolute => script.to_string_lossy().into_owned(),
        }
    }
}

/// The script a command runs.
fn script_of(command: &Command) -> Result<PathBuf, Unwritten> {
    match &command.execution {
        Execution::Script(script) => Ok(script.clone()),
        _ => Err(Unwritten::Syntax(SyntaxError(format!(
            "`{}` is not a script's command",
            command.path
        )))),
    }
}

fn names(shadows: &[Shadow]) -> Vec<(String, PathBuf)> {
    shadows
        .iter()
        .map(|shadow| (shadow.name.clone(), shadow.target.clone()))
        .collect()
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
            named("nus", &["../y.nu"]),
            Some(("nus ../y.nu".into(), "../y.nu".into()))
        );
        // A bare name is looked up on PATH, and `nu` with something else is not a script.
        assert_eq!(named("x.nu", &[]), None);
        assert_eq!(named("nu", &["-c", "x.nu"]), None);
        assert_eq!(as_path("x.nu"), "./x.nu");
        assert_eq!(as_path("../x.nu"), "../x.nu");
    }

    /// A directory of its own for a test's scripts.
    fn scripts(files: &[(&str, &str)]) -> PathBuf {
        use std::sync::atomic::{AtomicUsize, Ordering};
        static NEXT: AtomicUsize = AtomicUsize::new(0);
        let dir = std::env::temp_dir().join(format!(
            "nusage-calls-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        std::fs::create_dir_all(&dir).unwrap();
        for (name, text) in files {
            let file = dir.join(name);
            std::fs::create_dir_all(file.parent().unwrap()).unwrap();
            std::fs::write(file, text).unwrap();
        }
        dir
    }

    fn written(script: &Path) -> (Vec<String>, Vec<Finding>) {
        let source = std::fs::read_to_string(script).unwrap();
        let mut calls = scan(script, &source, &Texts::new());
        let defs = definitions(script, &mut calls, Paths::Absolute, &Texts::new());
        (
            defs.iter().map(nusage_nu::print_line).collect(),
            calls.findings,
        )
    }

    #[test]
    fn a_definition_binds_usage_from_its_parameters_and_runs_the_script() {
        let fixture = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../fixtures/script-calls");
        let (defs, findings) = written(&fixture.join("script.nu"));
        assert!(findings.is_empty(), "{findings:?}");
        let path = resolve(&fixture, "callee.nu");
        let def = defs
            .iter()
            .find(|def| def.starts_with("def \"./callee.nu\""))
            .expect("the path call's definition");
        assert!(
            def.contains("--times: int = 1"),
            "a declared default applies: {def}"
        );
        assert!(
            def.contains(
                "let usage = { cmd: [] args: {name: $name} flags: {loud: $loud, times: $times, chatty: $chatty} }"
            ),
            "{def}"
        );
        assert!(
            def.ends_with(&format!("$in | run {:?} }}", path.to_string_lossy())),
            "{def}"
        );
    }

    #[test]
    fn the_scripts_a_called_script_calls_are_defined_inside_its_definition() {
        let shebang = "#!/usr/bin/env nus\n";
        let dir = scripts(&[
            ("main.nu", &format!("{shebang}./a/a.nu\n./b.nu\n")),
            ("b.nu", &format!("{shebang}\"root b\"\n")),
            ("a/a.nu", &format!("{shebang}./b.nu\n")),
            ("a/b.nu", &format!("{shebang}\"a/b\"\n")),
        ]);
        let (defs, findings) = written(&dir.join("main.nu"));
        assert!(findings.is_empty(), "{findings:?}");
        let a = defs
            .iter()
            .find(|def| def.starts_with("def \"./a/a.nu\""))
            .unwrap();
        // `a.nu`'s own `./b.nu` is its sibling, defined where only its run sees it.
        let inner = format!(
            "def \"./b.nu\" [] {{ let usage = {{ cmd: [] args: {{}} flags: {{}} }}; $in | run {:?} }}",
            dir.join("a/b.nu").to_string_lossy()
        );
        assert!(a.contains(&inner), "{a}");
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn a_script_met_again_runs_with_the_definitions_around_it() {
        let shebang = "#!/usr/bin/env nus\n#USAGE arg \"<n>\"\n";
        let dir = scripts(&[
            ("a.nu", &format!("{shebang}./b.nu 1\n")),
            ("b.nu", &format!("{shebang}./a.nu 0\n")),
        ]);
        let (defs, findings) = written(&dir.join("a.nu"));
        assert!(findings.is_empty(), "{findings:?}");
        assert_eq!(defs.len(), 1);
        // `b.nu`'s `./a.nu` is defined inside, and `a.nu`'s `./b.nu` there is the one around.
        let a_again = format!(
            "def \"./a.nu\" [n: string] {{ let usage = {{ cmd: [] args: {{n: $n}} flags: {{}} }}; $in | run {:?} }}",
            dir.join("a.nu").to_string_lossy()
        );
        assert!(defs[0].contains(&a_again), "{}", defs[0]);
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn a_round_whose_names_reach_other_scripts_is_left_external() {
        let shebang = "#!/usr/bin/env nus\n";
        // `x/a.nu` calls `./c.nu` (its sibling) and `../y/b.nu`; `y/b.nu` calls `./c.nu` (its
        // own sibling) and `../x/a.nu`. Met again inside `b.nu`'s definition, `a.nu`'s
        // `./c.nu` would reach `y/c.nu`.
        let dir = scripts(&[
            ("x/a.nu", &format!("{shebang}./c.nu\n../y/b.nu\n")),
            ("x/c.nu", &format!("{shebang}1\n")),
            ("y/b.nu", &format!("{shebang}./c.nu\n../x/a.nu\n")),
            ("y/c.nu", &format!("{shebang}2\n")),
        ]);
        let (defs, findings) = written(&dir.join("x/a.nu"));
        assert!(defs.iter().any(|def| def.starts_with("def \"./c.nu\"")));
        assert!(!defs.iter().any(|def| def.starts_with("def \"../y/b.nu\"")));
        assert_eq!(findings.len(), 1, "{findings:?}");
        assert!(
            findings[0].message.contains("come back round"),
            "{findings:?}"
        );
        std::fs::remove_dir_all(dir).unwrap();
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
