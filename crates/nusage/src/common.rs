//! What both targets share: the attribute alias, doc comments, parameters, relative paths.

use std::path::{Component, Path, PathBuf};

use nusage_model::{Command, Completer, Param, ParamKind, Value};
use nusage_nu::{
    Attr, AttrArg, CommandName, Completer as NuCompleter, FlagName, Ident, Literal,
    Param as NuParam, Stmt, SyntaxError, Type,
};

use crate::extern_::helper_command;

pub fn attr_usage_alias() -> Result<Stmt, SyntaxError> {
    Ok(Stmt::Alias {
        name: CommandName::new("attr usage")?,
        target: CommandName::new("echo")?,
    })
}

/// `about` as the description paragraph, `long_about` as the extra one.
pub fn doc_of(command: &Command) -> Vec<Vec<String>> {
    let mut doc = Vec::new();
    if let Some(about) = &command.about {
        doc.push(vec![about.clone()]);
    }
    if let Some(long) = &command.about_long {
        doc.push(long.lines().map(str::to_string).collect());
    }
    doc
}

/// One `@usage` attribute per header node carried verbatim.
pub fn usage_attrs(command: &Command) -> Result<Vec<Attr>, SyntaxError> {
    command
        .attributes
        .iter()
        .map(|text| {
            Ok(Attr {
                name: FlagName::new("usage")?,
                args: vec![AttrArg::Str(text.clone())],
            })
        })
        .collect()
}

/// A model parameter as a Nushell one. `with_defaults` is false for externs, which ignore
/// defaults and leave them to the binary.
pub fn nu_param(param: &Param, with_defaults: bool) -> Result<NuParam, SyntaxError> {
    let completer = match &param.completer {
        Some(Completer::Inline(items)) if items.is_empty() => None,
        Some(Completer::Inline(items)) => Some(NuCompleter::List(items.clone())),
        Some(Completer::Command(path)) => {
            Some(NuCompleter::Command(CommandName::new(path.to_string())?))
        }
        Some(Completer::Shell { name, .. }) => Some(NuCompleter::Command(CommandName::new(
            helper_command(name),
        )?)),
        None => None,
    };
    let default = if with_defaults {
        param.default.as_ref().map(literal)
    } else {
        None
    };
    let doc = param.doc.clone();
    Ok(match param.kind {
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
            doc,
        },
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
    })
}

fn flag_name(param: &Param) -> Result<FlagName, SyntaxError> {
    FlagName::new(
        param
            .long
            .clone()
            .unwrap_or_else(|| param.usage_name.clone()),
    )
}

fn literal(value: &Value) -> Literal {
    match value {
        Value::Null => Literal::Null,
        Value::Bool(b) => Literal::Bool(*b),
        Value::Int(i) => Literal::Int(*i),
        Value::Float(f) => Literal::Float(*f),
        Value::Str(s) => Literal::Str(s.clone()),
        Value::List(items) => Literal::List(items.iter().map(literal).collect()),
    }
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
    use super::relative;
    use std::path::Path;

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
