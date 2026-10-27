//! The extern target: one `export extern` per command of a binary described by a spec file,
//! with `@structured` where the spec declares a `json` or `jsonl` output, and a helper per
//! shell-backed completer.

use nusage_model::{Command, CommandTree, Completer, Execution, Framing};
use nusage_nu::{
    Attr, AttrArg, CommandName, Def, Expr, Extern, FlagName, Item, Module, Params, Stmt,
    SyntaxError, Type,
};

use crate::common::{Target, attr_usage_alias, doc_of, nu_params, usage_attrs};

/// The module for a binary: completer helpers first, then the externs. The root is `main` and
/// a subcommand drops the binary's name, as in a script module, so `use <bin>.nu` names the
/// commands after the binary; Nushell runs the external by the name the call was typed with.
pub fn module(tree: &CommandTree) -> Result<Module, SyntaxError> {
    let mut items = Vec::new();
    let mut helpers_done = Vec::new();
    // A helper's name carries the command path when the completer is one command's own, so
    // two helpers with one name run the same program: the spec-level completer they share.
    for command in &tree.commands {
        for param in command.positionals.iter().chain(command.flags.iter()) {
            if let Some(Completer::Shell {
                name,
                run,
                descriptions,
            }) = &param.completer
                && !helpers_done.contains(name)
            {
                items.push(Item::Def(helper(name, run, *descriptions)?));
                helpers_done.push(name.clone());
            }
        }
    }
    for command in &tree.commands {
        items.push(Item::Extern(extern_of(command)?));
    }
    Ok(Module {
        preamble: vec![attr_usage_alias()?],
        items,
    })
}

/// `def "complete <name>" [] { ^sh -c <run> | lines }`, with `parse` when the lines carry
/// descriptions, which is how usage reads them.
fn helper(name: &str, run: &str, descriptions: bool) -> Result<Def, SyntaxError> {
    let mut stages = vec![
        Expr::External {
            name: "sh".into(),
            args: vec![Expr::Str("-c".into()), Expr::Str(run.to_string())],
        },
        Expr::Call {
            name: CommandName::new("lines")?,
            args: vec![],
        },
    ];
    if descriptions {
        stages.push(Expr::Call {
            name: CommandName::new("parse")?,
            args: vec![Expr::Str("{value}:{description}".into())],
        });
    }
    Ok(Def {
        export: false,
        doc: vec![],
        attrs: vec![],
        name: CommandName::definable(helper_command(name))?,
        params: Params::default(),
        io: None,
        body: vec![Stmt::Pipeline(stages)],
    })
}

pub fn helper_command(name: &str) -> String {
    format!("complete {name}")
}

fn extern_of(command: &Command) -> Result<Extern, SyntaxError> {
    if command.execution != Execution::External {
        return Err(SyntaxError(format!(
            "`{}` is a script; the extern target only wraps binaries",
            command.path
        )));
    }
    let name = if command.path.is_root() {
        "main".to_string()
    } else {
        command.path.to_string()
    };
    let params = command
        .positionals
        .iter()
        .chain(command.flags.iter())
        .map(|param| nu_params(param, Target::Extern))
        .collect::<Result<Vec<_>, _>>()?
        .concat();
    let mut attrs = usage_attrs(command)?;
    if let Some(structured) = &command.structured {
        let decode = match structured.framing {
            Framing::Json => "from json",
            Framing::Jsonl => "from json --objects",
        };
        attrs.push(Attr {
            name: FlagName::new("structured")?,
            args: vec![
                AttrArg::Words(structured.args.clone()),
                AttrArg::Block(decode.into()),
            ],
        });
    }
    let io = match &command.output {
        Some(output) => Some((Type::new("nothing")?, Type::new(output.as_str())?)),
        None => None,
    };
    Ok(Extern {
        export: true,
        doc: doc_of(command),
        attrs,
        name: CommandName::definable(name)?,
        params: Params::new(params)?,
        io,
        strict: true,
    })
}
