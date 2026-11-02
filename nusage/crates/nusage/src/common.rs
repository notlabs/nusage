//! What both targets share: the attribute alias, doc comments, parameters, the `$usage` a
//! script's definition builds, relative paths.

use std::path::{Component, Path, PathBuf};

use nusage_model::{Command, Completer, Param, ParamKind};
use nusage_nu::{
    Attr, CommandName, Completer as NuCompleter, Expr, FlagName, Ident, Infix, Param as NuParam,
    Stmt, SyntaxError, Type, Value,
};

/// The binary module's completer, which runs usage's against the spec.
pub const SPEC_COMPLETER: &str = "nus complete";

/// Which module a parameter is written for. In both, a counted flag is an `int` and a
/// repeatable one a `list`, since a `def`'s flags cannot repeat.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Target {
    /// A `def` that hands the script `$usage`: declared defaults apply.
    Script,
    /// A `def` that runs a binary: no defaults, since the binary applies its own, and the
    /// wrapper passes only what the call gave.
    Binary,
    /// A `def` that runs another script, named as a call writes it: it hands the script
    /// `$usage` as a module's does, so declared defaults apply, and only static choices
    /// complete, since that script's providers and usage's completer are not where the call
    /// is.
    Call,
    /// A `def` that runs a program with a spec, named as a call writes it: no defaults, as for
    /// a binary, and only static choices complete, as for a script's call.
    Program,
}

pub fn attr_usage_alias() -> Result<Stmt, SyntaxError> {
    Ok(Stmt::Alias {
        name: CommandName::new("attr usage")?,
        target: CommandName::new("echo")?,
    })
}

/// `about` as the description paragraph, `long_about` as the extra ones. A `long_about` whose
/// first paragraph says `about` again, as usage's `help` and `long_help` conventionally do,
/// gives only the rest.
pub fn doc_of(command: &Command) -> Vec<Vec<String>> {
    let mut doc = Vec::new();
    if let Some(about) = &command.about {
        doc.push(vec![about.clone()]);
    }
    if let Some(long) = &command.about_long {
        let mut paragraphs = long.split("\n\n").peekable();
        if let (Some(about), Some(first)) = (&command.about, paragraphs.peek())
            && restates(first, about)
        {
            paragraphs.next();
        }
        doc.extend(paragraphs.map(|paragraph| paragraph.lines().map(str::to_string).collect()));
    }
    doc
}

/// Whether a paragraph says `about` again: word for word, or with the period clap takes off
/// a doc comment's first paragraph to make `about` and keeps in `long_about`.
pub fn restates(paragraph: &str, about: &str) -> bool {
    let (paragraph, about) = (paragraph.trim(), about.trim());
    paragraph == about || paragraph.strip_suffix('.') == Some(about)
}

/// One `@usage` attribute per header node carried verbatim.
pub fn usage_attrs(command: &Command) -> Result<Vec<Attr>, SyntaxError> {
    command
        .attributes
        .iter()
        .map(|text| {
            Ok(Attr {
                name: FlagName::new("usage")?,
                args: vec![text.clone()],
            })
        })
        .collect()
}

/// A model parameter as Nushell parameters: the parameter itself, then the switch that
/// negates it when usage declares one.
pub fn nu_params(param: &Param, target: Target) -> Result<Vec<NuParam>, SyntaxError> {
    let completer = match &param.completer {
        Some(Completer::Inline(items)) => Some(NuCompleter::List(items.clone())),
        Some(Completer::Command(_)) if matches!(target, Target::Call | Target::Program) => None,
        Some(Completer::Command(path)) => {
            Some(NuCompleter::Command(CommandName::new(path.to_string())?))
        }
        // A script's bare `type=` says what the value is and completes nothing here.
        Some(Completer::Spec) => match target {
            Target::Binary => Some(NuCompleter::Command(CommandName::new(SPEC_COMPLETER)?)),
            Target::Script | Target::Call | Target::Program => None,
        },
        None => None,
    };
    let default = match target {
        Target::Script | Target::Call => param.default.clone(),
        Target::Binary | Target::Program => None,
    };
    let doc = param.doc.clone();
    let main = match param.kind {
        ParamKind::Required | ParamKind::Optional => NuParam::Positional {
            name: Ident::new(&param.var)?,
            ty: Type::new(param.ty.as_str())?,
            optional: param.kind == ParamKind::Optional,
            default,
            completer,
            doc,
        },
        ParamKind::Rest => NuParam::Rest {
            name: Ident::new(&param.var)?,
            ty: Type::new(param.ty.as_str())?,
            completer,
            doc,
        },
        // A switch takes no default: the shim applies a declared one when it builds `$usage`.
        ParamKind::Switch => NuParam::Flag {
            long: flag_name(param)?,
            short: param.short,
            ty: None,
            default: None,
            completer: None,
            doc,
        },
        ParamKind::Valued | ParamKind::Count => NuParam::Flag {
            long: flag_name(param)?,
            short: param.short,
            ty: Some(Type::new(param.ty.as_str())?),
            default,
            completer,
            doc,
        },
        ParamKind::Repeated => NuParam::Flag {
            long: flag_name(param)?,
            short: param.short,
            ty: Some(Type::new(format!("list<{}>", param.ty.as_str()))?),
            default,
            completer,
            doc,
        },
    };
    let mut params = vec![main];
    if let Some(negate) = &param.negate {
        params.push(NuParam::Flag {
            long: FlagName::new(negate.clone())?,
            short: None,
            ty: None,
            default: None,
            completer: None,
            doc: Some(format!("Turn off --{}", flag_name(param)?.as_str())),
        });
    }
    Ok(params)
}

/// The `$usage` record a script's definition builds from its parameters, as usage would bind
/// them: `{cmd, args, flags}`, every declared name present, keyed as the script reads it.
pub fn usage_record(command: &Command) -> Result<Expr, SyntaxError> {
    let cmd = Expr::Literal(Value::test_list(
        command
            .path
            .words()
            .iter()
            .map(Value::test_string)
            .collect(),
    ));
    let field = |param: &Param| -> Result<(String, Expr), SyntaxError> {
        Ok((param.key.clone(), param_value(param)?))
    };
    let args = command
        .positionals
        .iter()
        .map(field)
        .collect::<Result<Vec<_>, _>>()?;
    let flags = command
        .flags
        .iter()
        .map(field)
        .collect::<Result<Vec<_>, _>>()?;
    Ok(Expr::Record(vec![
        ("cmd".into(), cmd),
        ("args".into(), Expr::Record(args)),
        ("flags".into(), Expr::Record(flags)),
    ]))
}

/// What a parameter contributes to `$usage`: its variable, except for a switch usage declares
/// on by default, which stays on unless its `negate` flag is given, as usage's own parsers
/// read it. A switch with a `negate` flag and no default is on when given and not negated.
fn param_value(param: &Param) -> Result<Expr, SyntaxError> {
    let var = Expr::Var(Ident::new(&param.var)?);
    if param.kind != ParamKind::Switch {
        return Ok(var);
    }
    let on_by_default = matches!(&param.default, Some(Value::Bool { val: true, .. }));
    let negated = match &param.negate {
        Some(negate) => Expr::Call {
            name: CommandName::new("not")?,
            args: vec![Expr::Var(Ident::new(negate.replace('-', "_"))?)],
        },
        None => {
            return Ok(if on_by_default {
                Expr::Literal(Value::test_bool(true))
            } else {
                var
            });
        }
    };
    Ok(Expr::Group(Box::new(if on_by_default {
        negated
    } else {
        Expr::Infix {
            lhs: Box::new(var),
            op: Infix::And,
            rhs: Box::new(negated),
        }
    })))
}

/// The flag as Nushell spells it; a flag with no long name is spelled by its usage name.
fn flag_name(param: &Param) -> Result<FlagName, SyntaxError> {
    FlagName::new(
        param
            .nushell_long()
            .unwrap_or_else(|| param.usage_name.clone()),
    )
}

/// `target` relative to the directory `base`, with forward slashes, without touching the
/// filesystem: both are made absolute against the current directory and folded first.
pub fn relative(base: &Path, target: &Path) -> String {
    let base = fold(&absolute(base));
    let target = fold(&absolute(target));
    let base: Vec<_> = base.components().collect();
    let target: Vec<_> = target.components().collect();
    let common = base
        .iter()
        .zip(target.iter())
        .take_while(|(a, b)| a == b)
        .count();
    let mut parts: Vec<String> = Vec::new();
    for _ in common..base.len() {
        parts.push("..".to_string());
    }
    for component in &target[common..] {
        parts.push(component.as_os_str().to_string_lossy().into_owned());
    }
    if parts.is_empty() {
        ".".to_string()
    } else {
        parts.join("/")
    }
}

/// The path absolute and as the filesystem has it, symlinks resolved: Nushell resolves a
/// module's directory before it follows a relative `run` or `path self` from it, so a chain
/// of `..` counted on a path with a symlink in it, `/var` for `/private/var` on macOS or a
/// temporary directory elsewhere, would land one level off. What does not exist yet, the
/// module about to be written, is resolved as far as it exists and kept as named below that.
fn absolute(path: &Path) -> PathBuf {
    let path = if path.is_absolute() {
        path.to_path_buf()
    } else {
        std::env::current_dir().unwrap_or_default().join(path)
    };
    let mut rest = Vec::new();
    let mut existing = path.as_path();
    loop {
        if let Ok(real) = std::fs::canonicalize(existing) {
            let mut out = real;
            for component in rest.iter().rev() {
                out.push(component);
            }
            return out;
        }
        match (existing.parent(), existing.file_name()) {
            (Some(parent), Some(name)) => {
                rest.push(name.to_os_string());
                existing = parent;
            }
            _ => return path,
        }
    }
}

fn fold(path: &Path) -> PathBuf {
    let mut out = PathBuf::new();
    for component in path.components() {
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

/// The user's cache directory, as each platform has one.
pub fn cache_dir() -> PathBuf {
    let var = |name: &str| std::env::var_os(name).filter(|value| !value.is_empty());
    if cfg!(windows) {
        if let Some(dir) = var("LOCALAPPDATA") {
            return PathBuf::from(dir);
        }
    } else if cfg!(target_os = "macos") {
        if let Some(home) = var("HOME") {
            return PathBuf::from(home).join("Library/Caches");
        }
    } else if let Some(dir) = var("XDG_CACHE_HOME") {
        return PathBuf::from(dir);
    } else if let Some(home) = var("HOME") {
        return PathBuf::from(home).join(".cache");
    }
    std::env::temp_dir()
}

/// FNV-1a over `bytes`, in hexadecimal: a name for contents that is the same from one build
/// of nusage to the next.
pub fn fnv1a(bytes: impl IntoIterator<Item = u8>) -> String {
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for byte in bytes {
        hash = (hash ^ u64::from(byte)).wrapping_mul(0x0100_0000_01b3);
    }
    format!("{hash:016x}")
}

#[cfg(test)]
mod tests {
    use super::{doc_of, relative};
    use nusage_model::{Command, CommandPath, Execution};
    use std::path::Path;

    /// A module written under a symlink runs its scripts by the real directory's depth, as
    /// Nushell resolves the directory before it follows the path.
    #[cfg(unix)]
    #[test]
    fn relative_paths_count_from_the_real_directory() {
        let dir = std::env::temp_dir().join(format!("nusage-relative-{}", std::process::id()));
        let real = dir.join("real/x/y/z");
        std::fs::create_dir_all(&real).unwrap();
        let target = dir.join("scripts/callee.nu");
        std::fs::create_dir_all(target.parent().unwrap()).unwrap();
        std::fs::write(&target, "").unwrap();
        let shallow = dir.join("shallow");
        std::os::unix::fs::symlink(&real, &shallow).unwrap();
        // Through the symlink, the base is one directory deep; really it is four.
        assert_eq!(
            relative(&shallow, &target),
            relative(&real, &target),
            "the symlink and the directory it names are one base"
        );
        assert!(relative(&shallow, &target).starts_with("../../../../scripts/"));
        // A base that does not exist yet is resolved as far as it does.
        assert_eq!(
            relative(&shallow.join("new"), &target),
            relative(&real.join("new"), &target)
        );
        std::fs::remove_dir_all(&dir).unwrap();
    }

    fn command(about: &str, long: &str) -> Command {
        Command {
            path: CommandPath::default(),
            about: Some(about.to_string()),
            about_long: Some(long.to_string()),
            positionals: vec![],
            flags: vec![],
            output: None,
            structured: None,
            clause: None,
            attributes: vec![],
            execution: Execution::External,
            is_provider: false,
        }
    }

    #[test]
    fn a_repeated_about_is_said_once() {
        // usage's convention, and clap's: `about` is the doc comment's first paragraph with
        // its period taken off.
        for long in [
            "Abandon a revision\n\nMore.",
            "Abandon a revision.\n\nMore.",
        ] {
            assert_eq!(
                doc_of(&command("Abandon a revision", long)),
                [vec!["Abandon a revision"], vec!["More."]]
            );
        }
        // A first paragraph that only opens with the same words says more than `about`.
        assert_eq!(
            doc_of(&command(
                "Abandon a revision",
                "Abandon a revision, rebasing descendants"
            )),
            [
                vec!["Abandon a revision"],
                vec!["Abandon a revision, rebasing descendants"]
            ]
        );
    }

    #[test]
    fn relative_paths() {
        assert_eq!(
            relative(Path::new("/a/b/expected"), Path::new("/a/b/script.nu")),
            "../script.nu"
        );
        assert_eq!(
            relative(
                Path::new("/a/b/expected"),
                Path::new("/a/b/mycli/db/migrate.nu")
            ),
            "../mycli/db/migrate.nu"
        );
        assert_eq!(relative(Path::new("/a"), Path::new("/a/x.nu")), "x.nu");
    }
}
