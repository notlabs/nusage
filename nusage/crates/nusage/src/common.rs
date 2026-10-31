//! What both targets share: the attribute alias, doc comments, parameters, relative paths.

use std::path::{Component, Path, PathBuf};

use nusage_model::{Command, Completer, Param, ParamKind};
use nusage_nu::{
    Attr, CommandName, Completer as NuCompleter, FlagName, Ident, Param as NuParam, Stmt,
    SyntaxError, Type,
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
    /// A `def` that runs another script through the interpreter, named as a call writes it:
    /// as for a binary, and only static choices complete, since that script's providers
    /// and usage's completer are not where the call is.
    Call,
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
        Some(Completer::Command(_)) if target == Target::Call => None,
        Some(Completer::Command(path)) => {
            Some(NuCompleter::Command(CommandName::new(path.to_string())?))
        }
        // A script's bare `type=` says what the value is and completes nothing here.
        Some(Completer::Spec) => match target {
            Target::Binary => Some(NuCompleter::Command(CommandName::new(SPEC_COMPLETER)?)),
            Target::Script | Target::Call => None,
        },
        None => None,
    };
    let default = match target {
        Target::Script => param.default.clone(),
        Target::Binary | Target::Call => None,
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

fn absolute(path: &Path) -> PathBuf {
    if path.is_absolute() {
        path.to_path_buf()
    } else {
        std::env::current_dir().unwrap_or_default().join(path)
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

#[cfg(test)]
mod tests {
    use super::{doc_of, relative};
    use nusage_model::{Command, CommandPath, Execution};
    use std::path::Path;

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
