//! The shim target: one `export def` per command whose body builds `$usage` and `run`s the
//! script.

use std::path::{Component, Path, PathBuf};

use nusage_model::{Command, CommandTree, Completer, Param, ParamKind, Value};
use nusage_nu::{
    Attr, CommandName, Completer as NuCompleter, Def, Expr, FlagName, Ident, Literal, Module,
    Param as NuParam, Params, Stmt, SyntaxError, Type,
};

/// The module for a command tree, with `run` paths relative to `base`.
pub fn module(tree: &CommandTree, base: &Path) -> Result<Module, SyntaxError> {
    let preamble = vec![Stmt::Alias {
        name: CommandName::new("attr usage")?,
        target: CommandName::new("echo")?,
    }];
    let defs = tree
        .commands
        .iter()
        .map(|command| def(command, base))
        .collect::<Result<Vec<_>, _>>()?;
    Ok(Module { preamble, defs })
}

fn def(command: &Command, base: &Path) -> Result<Def, SyntaxError> {
    let name = if command.path.is_root() {
        "main".to_string()
    } else {
        command.path.to_string()
    };
    let mut doc = Vec::new();
    if let Some(about) = &command.about {
        doc.push(vec![about.clone()]);
    }
    if let Some(long) = &command.about_long {
        doc.push(long.lines().map(str::to_string).collect());
    }
    let attrs = command
        .attributes
        .iter()
        .map(|text| {
            Ok(Attr {
                name: FlagName::new("usage")?,
                value: Literal::Str(text.clone()),
            })
        })
        .collect::<Result<Vec<_>, SyntaxError>>()?;
    let params = command
        .positionals
        .iter()
        .chain(command.flags.iter())
        .map(nu_param)
        .collect::<Result<Vec<_>, _>>()?;
    let io = match &command.output {
        Some(output) => Some((Type::new("nothing")?, Type::new(output.as_str())?)),
        None => None,
    };
    let body = vec![
        Stmt::Let {
            name: Ident::new("usage")?,
            value: usage_record(command)?,
        },
        Stmt::Pipeline(vec![
            Expr::Var(Ident::new("in")?),
            Expr::Call {
                name: CommandName::new("run")?,
                args: vec![Expr::Path(relative(base, &command.body))],
            },
        ]),
    ];
    Ok(Def {
        export: true,
        doc,
        attrs,
        name: CommandName::new(name)?,
        params: Params::new(params)?,
        io,
        body,
    })
}

fn usage_record(command: &Command) -> Result<Expr, SyntaxError> {
    let cmd = Expr::List(
        command
            .path
            .words()
            .iter()
            .map(|word| Expr::Literal(Literal::Str(word.clone())))
            .collect(),
    );
    let field = |param: &Param| -> Result<(Ident, Expr), SyntaxError> {
        Ok((Ident::new(&param.var)?, Expr::Var(Ident::new(&param.var)?)))
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
        (Ident::new("cmd")?, cmd),
        (Ident::new("args")?, Expr::Record(args)),
        (Ident::new("flags")?, Expr::Record(flags)),
    ]))
}

fn nu_param(param: &Param) -> Result<NuParam, SyntaxError> {
    let completer = match &param.completer {
        Some(Completer::Inline(items)) => Some(NuCompleter::List(items.clone())),
        Some(Completer::Command(path)) => {
            Some(NuCompleter::Command(CommandName::new(path.to_string())?))
        }
        None => None,
    };
    let doc = param.doc.clone();
    Ok(match param.kind {
        ParamKind::Required | ParamKind::Optional => NuParam::Positional {
            name: Ident::new(&param.var)?,
            ty: Type::new(param.ty.as_str())?,
            optional: param.kind == ParamKind::Optional,
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
            default: param.default.as_ref().map(literal),
            completer,
            doc,
        },
        ParamKind::Repeated => NuParam::Flag {
            long: flag_name(param)?,
            short: param.short,
            ty: Some(Type::new(format!("list<{}>", param.ty.as_str()))?),
            default: param.default.as_ref().map(literal),
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
fn relative(base: &Path, target: &Path) -> String {
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
