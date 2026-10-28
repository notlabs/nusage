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

use crate::common::{SPEC_COMPLETER, Target, attr_usage_alias, doc_of, nu_params, usage_attrs};

/// The fixed helpers every binary module carries.
const HELPERS: &str = include_str!("binary-helpers.nu");

/// The module for a binary: the helpers, the completer when a parameter wants one, then a
/// wrapper per command. `spec` is the spec file's path relative to the module's directory,
/// for the completer, which runs usage's against it.
pub fn module(tree: &CommandTree, spec: &str) -> Result<Module, SyntaxError> {
    let mut items = vec![Item::Verbatim(HELPERS.to_string())];
    let wants_completer = tree.commands.iter().any(|command| {
        command
            .positionals
            .iter()
            .chain(command.flags.iter())
            .any(|param| param.completer == Some(Completer::Spec))
    });
    if wants_completer {
        items.push(Item::Verbatim(spec_completer(&tree.bin, spec)));
    }
    for command in &tree.commands {
        let def = wrapper(tree, command)
            .map_err(|err| SyntaxError(format!("`{} {}`: {err}", tree.bin, command.path)))?;
        items.push(Item::Def(def));
    }
    Ok(Module {
        preamble: vec![attr_usage_alias()?],
        items,
    })
}

/// usage's completer as a Nushell one: the words typed so far go to `usage complete-word`
/// against the spec this module was generated from, which runs the spec's `complete`
/// commands with their templates rendered and completes `type=` paths. Nothing when the
/// `usage` CLI is not installed. Nushell hands a completer a record of where the cursor is;
/// its `command` field is the words of the call so far, the one being completed last, with
/// the call's name as one word: `demo install`, or `main` for the binary itself. usage wants
/// the binary's words, so the name is split and `main` becomes the binary.
fn spec_completer(bin: &str, spec: &str) -> String {
    format!(
        r#"# Completions from usage's own completer, against the spec this module was generated
# from, with the words typed so far. Nothing when the `usage` CLI is not installed.
def "{SPEC_COMPLETER}" [place: record] {{
    const spec = (path self | path dirname | path join {spec})
    if (which usage | is-empty) {{
        return []
    }}
    let name = $place.command | first
    let command = if $name == "main" {{ [{bin}] }} else {{ $name | split row " " }}
    let words = $place.command | skip 1
    (^usage complete-word -f $spec --shell nu -- ...$command ...$words | complete).stdout
    | lines
    | each {{|line| $line | split column "	" value description | into record }}
}}
"#,
        bin = word(bin),
        spec = word(spec)
    )
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
    // A `def` has one rest parameter; a binary declaring several variadic positionals, as
    // usage allows (`[ARGS]...` and `[-- MORE]...`), gets the first, which takes every
    // remaining word anyway, since the binary parses them.
    let mut rest_seen = false;
    let positionals: Vec<&Param> = command
        .positionals
        .iter()
        .filter(|param| {
            if param.kind != ParamKind::Rest {
                return true;
            }
            !std::mem::replace(&mut rest_seen, true)
        })
        .collect();
    let params = positionals
        .iter()
        .copied()
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
    let positionals = positionals
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
