//! The binary target: one `export def` per command of a binary described by a spec file.
//! The root is `main` and a subcommand carries the binary's name, so `use <bin>.nu *` names
//! them as the binary does. A wrapper is the binary's data form, as `^tool` is its text form:
//! its body builds the binary's argv from its typed parameters, asks for the command's
//! structured output with the spec's own selector words, and decodes it to the annotated
//! type, so its return type is one type the parser checks. The helper that builds the argv
//! ships with the module as Nushell, and a helper runs each shell-backed completer.

use nusage_model::{
    Command, CommandTree, Completer, Execution, Framing, Param, ParamKind, Structured,
};
use nusage_nu::{
    CommandName, Def, Expr, Ident, Item, Module, Params, Stmt, SyntaxError, Type, word,
};

use crate::common::{Target, attr_usage_alias, doc_of, nu_params, usage_attrs};

/// The fixed helpers every binary module carries.
const HELPERS: &str = include_str!("binary-helpers.nu");

/// The module for a binary: the helpers, completer helpers, then a wrapper per command.
pub fn module(tree: &CommandTree) -> Result<Module, SyntaxError> {
    let mut items = vec![Item::Verbatim(HELPERS.to_string())];
    // A helper's name carries the command's full name when the completer is one command's
    // own, so two helpers with one name run the same program: the spec's.
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
                items.push(Item::Def(completer_helper(name, run, *descriptions)?));
                helpers_done.push(name.clone());
            }
        }
    }
    for command in &tree.commands {
        items.push(Item::Def(wrapper(tree, command)?));
    }
    Ok(Module {
        preamble: vec![attr_usage_alias()?],
        items,
    })
}

/// `def "complete <name>" [] { ^sh -c <run> | lines }`, with `parse` when the lines carry
/// descriptions, which is how usage reads them.
fn completer_helper(name: &str, run: &str, descriptions: bool) -> Result<Def, SyntaxError> {
    let mut stages = vec![
        Expr::External {
            name: "sh".into(),
            args: vec![Expr::Str("-c".into()), Expr::Str(run.to_string())],
        },
        call("lines", vec![])?,
    ];
    if descriptions {
        stages.push(call(
            "parse",
            vec![Expr::Str("{value}:{description}".into())],
        )?);
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

fn wrapper(tree: &CommandTree, command: &Command) -> Result<Def, SyntaxError> {
    if command.execution != Execution::External {
        return Err(SyntaxError(format!(
            "`{}` is a script; the binary target only wraps binaries",
            command.path
        )));
    }
    let name = if command.path.is_root() {
        "main".to_string()
    } else {
        format!("{} {}", tree.bin, command.path)
    };
    let params = command
        .positionals
        .iter()
        .chain(command.flags.iter())
        .map(|param| nu_params(param, Target::Binary))
        .collect::<Result<Vec<_>, _>>()?
        .concat();
    let io = match &command.output {
        Some(output) => Some((Type::new("nothing")?, Type::new(output.as_str())?)),
        None => None,
    };

    // `^demo status --format json ...(nusage argv [$a ...$rest] {--flag: $flag})`: the
    // selector words come first, so a `--` the caller passes still comes after them.
    let positionals = command
        .positionals
        .iter()
        .map(|param| {
            let var = Expr::Var(Ident::new(&param.var)?);
            Ok(match param.kind {
                ParamKind::Rest => Expr::Spread(Box::new(var)),
                _ => var,
            })
        })
        .collect::<Result<Vec<_>, SyntaxError>>()?;
    let mut flags = Vec::new();
    for param in &command.flags {
        flags.push((flag_word(param), Expr::Var(Ident::new(&param.var)?)));
        if let Some(negate) = &param.negate {
            flags.push((
                format!("--{negate}"),
                Expr::Var(Ident::new(negate.replace('-', "_"))?),
            ));
        }
    }
    let argv = call(
        "nusage argv",
        vec![Expr::List(positionals), Expr::Record(flags)],
    )?;
    let mut args: Vec<Expr> = command
        .path
        .words()
        .iter()
        .chain(
            command
                .structured
                .iter()
                .flat_map(|structured| structured.args.iter()),
        )
        .map(|w| Expr::Str(w.clone()))
        .collect();
    args.push(Expr::Spread(Box::new(argv)));
    let run = Expr::External {
        name: tree.bin.clone(),
        args,
    };

    // Then `| from json | into datetime at` for a structured output.
    let mut stages = vec![run];
    if let Some(structured) = &command.structured {
        stages.extend(decode_stages(structured)?);
    }
    let body = vec![Stmt::Pipeline(stages)];
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

/// The flag as the binary spells it: `--dry-run`, or `-v` for a short-only flag.
fn flag_word(param: &Param) -> String {
    match (&param.long, param.short) {
        (Some(long), _) => format!("--{long}"),
        (None, Some(short)) => format!("-{short}"),
        (None, None) => format!("--{}", param.usage_name),
    }
}

/// `from json`, then `into datetime at` for what the annotation declares and JSON cannot
/// carry, at its cell path.
fn decode_stages(structured: &Structured) -> Result<Vec<Expr>, SyntaxError> {
    let mut stages = vec![match structured.framing {
        Framing::Json => call("from json", vec![])?,
        Framing::Jsonl => call("from json", vec![Expr::Str("--objects".into())])?,
    }];
    for conversion in &structured.conversions {
        let path: Vec<String> = conversion.path.iter().map(|part| word(part)).collect();
        let args = if path.is_empty() {
            vec![]
        } else {
            vec![Expr::Str(path.join("."))]
        };
        stages.push(call(&format!("into {}", conversion.ty), args)?);
    }
    Ok(stages)
}

fn call(name: &str, args: Vec<Expr>) -> Result<Expr, SyntaxError> {
    Ok(Expr::Call {
        name: CommandName::new(name)?,
        args,
    })
}
