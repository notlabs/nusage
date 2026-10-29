//! The shim target: one `export def` per command whose body builds `$usage` and `run`s the
//! script, after defining the shadows of the scripts that script calls ([`crate::calls`]):
//! inside the body, since a call's path is its script's, and `run` reads a script's calls
//! where it first parses it.

use std::path::Path;

use nusage_model::{Command, CommandTree, Execution, Param, ParamKind};
use nusage_nu::{
    CommandName, Def, Expr, Ident, Infix, Item, Module, Params, Stmt, SyntaxError, Type, Value,
};

use crate::binary::HELPERS;
use crate::calls::{self, CALL_HELPER, Runner, shadow_def};
use crate::common::{Target, attr_usage_alias, doc_of, nu_params, relative, usage_attrs};

/// The module for a command tree, with `run` paths relative to `base`.
pub fn module(tree: &CommandTree, base: &Path) -> Result<Module, SyntaxError> {
    let defs = tree
        .commands
        .iter()
        .map(|command| def(command, base))
        .collect::<Result<Vec<_>, _>>()?;
    // The shadows build their argv with the binary target's helpers, and run their scripts
    // with the call's.
    let calls = defs
        .iter()
        .any(|def| def.body.iter().any(|stmt| matches!(stmt, Stmt::Def(_))));
    let helpers = if calls {
        vec![
            Item::Verbatim(HELPERS.to_string()),
            Item::Verbatim(CALL_HELPER.to_string()),
        ]
    } else {
        Vec::new()
    };
    let items = helpers
        .into_iter()
        .chain(defs.into_iter().map(Item::Def))
        .collect();
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
        .map(|param| nu_params(param, Target::Script))
        .collect::<Result<Vec<_>, _>>()?
        .concat();
    let io = match &command.output {
        Some(output) => Some((Type::new("nothing")?, Type::new(output.as_str())?)),
        None => None,
    };
    let source = std::fs::read_to_string(body_path)
        .map_err(|err| SyntaxError(format!("cannot read {}: {err}", body_path.display())))?;
    let mut body = calls::scan(body_path, &source)
        .shadows
        .iter()
        .map(|shadow| {
            Ok(Stmt::Def(Box::new(shadow_def(
                shadow,
                Runner::Module(base),
            )?)))
        })
        .collect::<Result<Vec<_>, SyntaxError>>()?;
    body.extend([
        Stmt::Let {
            name: Ident::new("usage")?,
            value: usage_record(command)?,
        },
        Stmt::Pipeline(vec![
            Expr::Var(Ident::new("in")?),
            Expr::Call {
                name: CommandName::new("run")?,
                args: vec![Expr::Str(relative(base, body_path))],
            },
        ]),
    ]);
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
