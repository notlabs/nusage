//! The shim target: one `export def` per command whose body builds `$usage` and `run`s the
//! script.

use std::path::Path;

use nusage_model::{Command, CommandTree, Execution};
use nusage_nu::{
    CommandName, Def, Expr, Ident, Item, Literal, Module, Params, Stmt, SyntaxError, Type,
};

use crate::common::{attr_usage_alias, doc_of, nu_param, relative, usage_attrs};

/// The module for a command tree, with `run` paths relative to `base`.
pub fn module(tree: &CommandTree, base: &Path) -> Result<Module, SyntaxError> {
    let items = tree
        .commands
        .iter()
        .map(|command| def(command, base).map(Item::Def))
        .collect::<Result<Vec<_>, _>>()?;
    Ok(Module {
        preamble: vec![attr_usage_alias()?],
        items,
    })
}

fn def(command: &Command, base: &Path) -> Result<Def, SyntaxError> {
    let Execution::Script(body_path) = &command.execution else {
        return Err(SyntaxError(format!(
            "`{}` is an external command; the shim target only wraps scripts",
            command.path
        )));
    };
    let name = if command.path.is_root() {
        "main".to_string()
    } else {
        command.path.to_string()
    };
    let params = command
        .positionals
        .iter()
        .chain(command.flags.iter())
        .map(|param| nu_param(param, true))
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
                args: vec![Expr::Path(relative(base, body_path))],
            },
        ]),
    ];
    Ok(Def {
        export: true,
        doc: doc_of(command),
        attrs: usage_attrs(command)?,
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
    let field = |param: &nusage_model::Param| -> Result<(Ident, Expr), SyntaxError> {
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
