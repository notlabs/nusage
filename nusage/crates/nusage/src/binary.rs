//! The binary target: one `export def` per command of a binary described by a spec file.
//! The root is `main` and a subcommand carries the binary's name, so `use <bin>.nu *` names
//! them as the binary does. A wrapper is the binary's data form, as `^tool` is its text form:
//! its body builds the binary's argv from its typed parameters, asks for the command's
//! structured output with the spec's own selector words, and decodes it to the type its
//! schema or annotation declares, so its return type is one type the parser checks. The
//! helper that builds the argv
//! ships with the module as Nushell, and a helper runs each shell-backed completer.

use nu_protocol::{Span, Value};
use nusage_model::{
    Command, CommandTree, Completer, Conversion, Decoder, Execution, Fill, Framing, Param,
    ParamKind, Structured,
};
use nusage_nu::{
    CommandName, Def, Expr, Ident, Infix, Item, Module, Param as NuParam, Params, Stmt,
    SyntaxError, Type, word,
};

use crate::common::{SPEC_COMPLETER, Target, attr_usage_alias, doc_of, nu_params, usage_attrs};

/// The fixed helpers every binary module carries, and every module whose scripts call
/// scripts.
pub(crate) const HELPERS: &str = include_str!("binary-helpers.nu");
/// The helper that holds a failed decode to the output's schema, carried when a wrapper
/// decodes a JSON document that has one.
pub(crate) const DECODED: &str = include_str!("binary-decoded.nu");

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
    if tree.commands.iter().any(|command| {
        command
            .structured
            .as_ref()
            .is_some_and(|s| s.schema.is_some())
    }) {
        items.push(Item::Verbatim(DECODED.to_string()));
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
    let (params, argv) = params_and_argv(command, Target::Binary)?;
    let io = match &command.output {
        Some(output) => Some((Type::new("nothing")?, Type::new(output.as_str())?)),
        None => None,
    };

    // `^demo status --format json ...(nusage argv [$a ...$rest] {--flag: $flag})`: the
    // selector words come first, so a `--` the caller passes still comes after them.
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

    // Then `| from json | into datetime at` for a structured output. An output with a
    // schema is decoded by `nusage decoded`, which holds the output to the schema when
    // decoding fails, line by line for JSON lines.
    let body = match &command.structured {
        Some(structured) if structured.schema.is_some() => {
            let schema: serde_json::Value =
                serde_json::from_str(structured.schema.as_deref().unwrap_or_default())
                    .map_err(|err| SyntaxError(format!("the output's schema: {err}")))?;
            let text = Ident::new("text")?;
            let mut args = vec![
                Expr::Var(text.clone()),
                Expr::Str(schema.to_string()),
                Expr::Closure(Box::new(Expr::Pipeline(decode_stages(structured)?))),
            ];
            if structured.framing == Framing::Jsonl {
                args.push(Expr::Str("--lines".into()));
            }
            vec![
                Stmt::Let {
                    name: text,
                    value: run,
                },
                Stmt::Pipeline(vec![call("nusage decoded", args)?]),
            ]
        }
        Some(structured) => {
            let mut stages = vec![run];
            stages.extend(decode_stages(structured)?);
            vec![Stmt::Pipeline(stages)]
        }
        None => vec![Stmt::Pipeline(vec![run])],
    };
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

/// A wrapper's parameters, and the argv they make: `nusage argv [$a ...$rest] {--flag:
/// $flag}`. A `def` has one rest parameter; a command declaring several variadic
/// positionals, as usage allows (`[ARGS]...` and `[-- MORE]...`), gets the first, which takes
/// every remaining word anyway, since the command parses them.
pub(crate) fn params_and_argv(
    command: &Command,
    target: Target,
) -> Result<(Vec<NuParam>, Expr), SyntaxError> {
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
        .map(|param| nu_params(param, target))
        .collect::<Result<Vec<_>, _>>()?
        .concat();
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
    // A clause's flags go before every instance of its positionals, the rest after them.
    let mut flags = Vec::new();
    let mut scoped = Vec::new();
    for param in &command.flags {
        let into = if param.clause {
            &mut scoped
        } else {
            &mut flags
        };
        into.push((flag_word(param), flag_value(param)?));
        if let Some(negate) = &param.negate {
            into.push((
                format!("--{negate}"),
                Expr::Var(Ident::new(negate.replace('-', "_"))?),
            ));
        }
    }
    let mut argv_args = vec![Expr::List(positionals), Expr::Record(flags)];
    if !scoped.is_empty() {
        argv_args.push(Expr::Record(scoped));
    }
    Ok((params, call("nusage argv", argv_args)?))
}

/// A flag's value as `nusage argv` takes it. The helper spells a flag by its value's type,
/// an `int` as a count and a `bool` as a switch, so a valued flag of a type other than text
/// goes as the list of its value, empty when absent, which it spells `--flag value`.
fn flag_value(param: &Param) -> Result<Expr, SyntaxError> {
    let var = Expr::Var(Ident::new(&param.var)?);
    if param.kind != ParamKind::Valued || matches!(param.ty.as_str(), "string" | "path") {
        return Ok(var);
    }
    Ok(Expr::Group(Box::new(Expr::Pipeline(vec![
        Expr::List(vec![var]),
        call("compact", vec![])?,
    ]))))
}

/// The flag as the binary spells it: `--dry-run`, or `-v` for a short-only flag.
fn flag_word(param: &Param) -> String {
    match (&param.long, param.short) {
        (Some(long), _) => format!("--{long}"),
        (None, Some(short)) => format!("-{short}"),
        (None, None) => format!("--{}", param.usage_name),
    }
}

/// The decoder, `from json` or the reader for the media type or the pipeline the output
/// states; then what the schema or annotation declares and the text cannot carry: first
/// `default null` for each property the schema does not require, so the field is there to
/// read; then each conversion at its cell path, `into <ty> <path>` where the value is text
/// or a count of bytes, else an `update` whose closure counts the unit and leaves `null`
/// alone where the value may be one.
pub(crate) fn decode_stages(structured: &Structured) -> Result<Vec<Expr>, SyntaxError> {
    let mut stages = vec![match &structured.decoder {
        Decoder::From { format, objects } => {
            let args = if *objects {
                vec![Expr::Str("--objects".into())]
            } else {
                vec![]
            };
            call(&format!("from {format}"), args)?
        }
        Decoder::Pipeline(pipeline) => Expr::Raw(pipeline.clone()),
    }];
    // A value that may itself be null, with fields to fill or convert under it: asked
    // once, and everything under it runs on anything else.
    let under_null = |nullable: &[usize]| nullable.first() == Some(&0);
    let nullable_value = structured.fills.iter().any(|f| under_null(&f.nullable))
        || structured
            .conversions
            .iter()
            .any(|c| under_null(&c.nullable) && !c.path.is_empty());
    let within = |nullable: &[usize]| -> Vec<usize> {
        if nullable_value {
            nullable.iter().copied().filter(|&n| n != 0).collect()
        } else {
            nullable.to_vec()
        }
    };
    let mut under = Vec::new();
    for fill in &structured.fills {
        under.push(fill_stage(&Fill {
            path: fill.path.clone(),
            nullable: within(&fill.nullable),
        })?);
    }
    for conversion in &structured.conversions {
        under.push(conversion_stage(&Conversion {
            nullable: within(&conversion.nullable),
            ..conversion.clone()
        })?);
    }
    if nullable_value {
        stages.push(unless_null(&[], under)?);
    } else {
        stages.extend(under);
    }
    Ok(stages)
}

/// `default null <field>` on the fill's record: the whole value, or `update <record> {
/// default null <field> }` below it; held off where a record on the way may be null.
fn fill_stage(fill: &Fill) -> Result<Expr, SyntaxError> {
    if let Some(&at) = fill.nullable.first() {
        let (outer, rest) = fill.path.split_at(at);
        let inner = Fill {
            path: rest.to_vec(),
            nullable: fill.nullable[1..].iter().map(|n| n - at).collect(),
        };
        return unless_null(outer, vec![fill_stage(&inner)?]);
    }
    let (parent, field) = fill.path.split_at(fill.path.len() - 1);
    let default = call(
        "default",
        vec![
            Expr::Literal(Value::nothing(Span::unknown())),
            Expr::Str(field[0].clone()),
        ],
    )?;
    if parent.is_empty() {
        return Ok(default);
    }
    call(
        "update",
        vec![
            Expr::Raw(cell_path(parent)),
            Expr::Closure(Box::new(default)),
        ],
    )
}

/// `stages` on the value at `outer` where that may be null, such as jj's `operation` with
/// `time.start` under it: a null is left as it is, and the stages run on anything else.
/// On the whole value when `outer` is empty.
fn unless_null(outer: &[String], stages: Vec<Expr>) -> Result<Expr, SyntaxError> {
    let nothing = || Expr::Literal(Value::nothing(Span::unknown()));
    let guarded = move |value: Expr| Expr::If {
        cond: Box::new(Expr::Infix {
            lhs: Box::new(value.clone()),
            op: Infix::Eq,
            rhs: Box::new(nothing()),
        }),
        then: Box::new(nothing()),
        otherwise: Box::new(Expr::Pipeline(
            std::iter::once(value).chain(stages).collect(),
        )),
    };
    if outer.is_empty() {
        return Ok(guarded(Expr::Var(Ident::new("in")?)));
    }
    let row = Ident::new("row")?;
    let body = guarded(Expr::Cell {
        var: row.clone(),
        path: outer.to_vec(),
    });
    call(
        "update",
        vec![
            Expr::Raw(cell_path(outer)),
            Expr::ClosureWith {
                param: row,
                body: Box::new(body),
            },
        ],
    )
}

fn conversion_stage(conversion: &Conversion) -> Result<Expr, SyntaxError> {
    if let Some(&at) = conversion.nullable.first()
        && at < conversion.path.len()
    {
        let (outer, rest) = conversion.path.split_at(at);
        let inner = Conversion {
            path: rest.to_vec(),
            nullable: conversion.nullable[1..].iter().map(|n| n - at).collect(),
            ..conversion.clone()
        };
        return unless_null(outer, vec![conversion_stage(&inner)?]);
    }
    let nullable = conversion.nullable.last() == Some(&conversion.path.len());
    let path = cell_path(&conversion.path);
    let plain = conversion.unit.is_none() && conversion.ty != "base64";
    if plain && !nullable {
        let args = if conversion.path.is_empty() {
            vec![]
        } else {
            vec![Expr::Raw(path)]
        };
        return call(&format!("into {}", conversion.ty), args);
    }
    // `update <path> {|row| ... }`, or on the whole value `... | <convert>`.
    let row = Ident::new("row")?;
    let value = if conversion.path.is_empty() {
        Expr::Var(Ident::new("in")?)
    } else {
        Expr::Cell {
            var: row.clone(),
            path: conversion.path.clone(),
        }
    };
    let converted = match (conversion.ty.as_str(), &conversion.unit) {
        ("base64", _) => Expr::Pipeline(vec![value.clone(), call("decode base64", vec![])?]),
        ("duration", Some(unit)) => Expr::Pipeline(vec![
            value.clone(),
            call(
                "into duration",
                vec![Expr::Str("--unit".into()), Expr::Str(unit.clone())],
            )?,
        ]),
        // The epoch plus the count, as a duration. Nushell reads a datetime literal at the
        // head of an expression only in parentheses.
        ("datetime", Some(unit)) => Expr::Infix {
            lhs: Box::new(Expr::Group(Box::new(Expr::Raw(
                "1970-01-01T00:00:00Z".into(),
            )))),
            op: Infix::Add,
            rhs: Box::new(Expr::Group(Box::new(Expr::Pipeline(vec![
                value.clone(),
                call(
                    "into duration",
                    vec![Expr::Str("--unit".into()), Expr::Str(unit.clone())],
                )?,
            ])))),
        },
        ("filesize", Some(unit)) => Expr::Infix {
            lhs: Box::new(value.clone()),
            op: Infix::Mul,
            rhs: Box::new(Expr::Raw(format!("1{unit}"))),
        },
        (ty, None) => Expr::Pipeline(vec![value.clone(), call(&format!("into {ty}"), vec![])?]),
        (ty, Some(unit)) => {
            return Err(SyntaxError(format!(
                "a {ty} counts no `{unit}`; the model should not have declared one"
            )));
        }
    };
    let body = if nullable {
        Expr::If {
            cond: Box::new(Expr::Infix {
                lhs: Box::new(value),
                op: Infix::Eq,
                rhs: Box::new(Expr::Literal(Value::nothing(Span::unknown()))),
            }),
            then: Box::new(Expr::Literal(Value::nothing(Span::unknown()))),
            otherwise: Box::new(converted),
        }
    } else {
        converted
    };
    if conversion.path.is_empty() {
        Ok(body)
    } else {
        call(
            "update",
            vec![
                Expr::Raw(path),
                Expr::ClosureWith {
                    param: row,
                    body: Box::new(body),
                },
            ],
        )
    }
}

/// A cell path as `into` and `update` take it, written as is, each part quoted when it
/// needs to be.
fn cell_path(path: &[String]) -> String {
    path.iter()
        .map(|part| word(part))
        .collect::<Vec<_>>()
        .join(".")
}

pub(crate) fn call(name: &str, args: Vec<Expr>) -> Result<Expr, SyntaxError> {
    Ok(Expr::Call {
        name: CommandName::new(name)?,
        args,
    })
}
