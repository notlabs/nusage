//! The extern target: one `export extern` per command of a binary described by a spec file,
//! with `@structured` where the spec declares a `json` or `jsonl` output, and a helper per
//! shell-backed completer.

use nusage_model::{Command, CommandTree, Completer, Execution, Framing};
use nusage_nu::{
    Attr, AttrArg, CommandName, Def, Expr, Extern, FlagName, Item, Literal, Module, Params, Stmt,
    SyntaxError, Type,
};

use crate::common::{attr_usage_alias, doc_of, nu_param, usage_attrs};

/// The module for a binary: completer helpers first, then the externs. Import it with
/// `use <bin>.nu *`, since every extern carries the binary's name.
pub fn module(tree: &CommandTree) -> Result<Module, SyntaxError> {
    let mut items = Vec::new();
    let mut helpers_done = Vec::new();
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
        items.push(Item::Extern(extern_of(tree, command)?));
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
            args: vec![
                Expr::Literal(Literal::Str("-c".into())),
                Expr::Literal(Literal::Str(run.to_string())),
            ],
        },
        Expr::Call {
            name: CommandName::new("lines")?,
            args: vec![],
        },
    ];
    if descriptions {
        stages.push(Expr::Call {
            name: CommandName::new("parse")?,
            args: vec![Expr::Literal(Literal::Str("{value}:{description}".into()))],
        });
    }
    Ok(Def {
        export: false,
        doc: vec![],
        attrs: vec![],
        name: CommandName::new(helper_command(name))?,
        params: Params::default(),
        io: None,
        body: vec![Stmt::Pipeline(stages)],
    })
}

pub fn helper_command(name: &str) -> String {
    format!("complete {name}")
}

fn extern_of(tree: &CommandTree, command: &Command) -> Result<Extern, SyntaxError> {
    if command.execution != Execution::External {
        return Err(SyntaxError(format!(
            "`{}` is a script; the extern target only wraps binaries",
            command.path
        )));
    }
    let name = if command.path.is_root() {
        tree.bin.clone()
    } else {
        format!("{} {}", tree.bin, command.path)
    };
    // A binary applies its own defaults, and `extern` would ignore them anyway.
    let params = command
        .positionals
        .iter()
        .chain(command.flags.iter())
        .map(|param| nu_param(param, false))
        .collect::<Result<Vec<_>, _>>()?;
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
        name: CommandName::new(name)?,
        params: Params::new(params)?,
        io,
        strict: true,
    })
}
