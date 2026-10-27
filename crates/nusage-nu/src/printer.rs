//! The printer: one genco template per shape of output.
//!
//! Layout lives in the templates, where it reads as the Nushell it produces. The only rules
//! outside them are a record's breaking (a statement's value, or more than three fields, goes
//! one field per line), the alignment of parameter comments, and that documentation is
//! commented line by line: a description's lines each get a `#`, and a parameter's lines are
//! joined, since Nushell reads only the comment on the parameter's own line.

use genco::quote;

use crate::literal::{Value, nuon};
use crate::syntax::*;

genco::impl_lang! {
    /// Nushell for genco: the default four-space indentation and nothing else. Quoting is not
    /// genco's; words go through [`word`] and values through [`nuon`].
    pub Nu {
        type Config = ();
        type Format = ();
        type Item = Any;
    }
}

type Tokens = genco::Tokens<Nu>;

/// Write a module as Nushell source.
pub fn print(module: &Module) -> String {
    let tokens: Tokens = quote! {
        $(for stmt in &module.preamble => $(stmt_tokens(stmt))$['\r'])
        $(if !module.preamble.is_empty() => $['\n'])
        $(for item in &module.items join ($['\n']) => $(match item {
            Item::Def(def) => $(def_tokens(def)),
            Item::Extern(ext) => $(extern_tokens(ext)),
        }))
    };
    tokens
        .to_file_string()
        .expect("formatting into a String cannot fail")
}

/// The comment paragraphs and attribute lines above a definition.
fn head(doc: &[Vec<String>], attrs: &[Attr]) -> Tokens {
    quote! {
        $(for paragraph in doc join (#$['\r']) =>
            $(for line in paragraph.iter().flat_map(|line| line.split('\n')) => $(comment(line))$['\r'])
        )
        $(for attr in attrs =>
            @$(attr.name.as_str())$(for arg in &attr.args => $[' ']$(attr_arg(arg)))$['\r']
        )
    }
}

fn comment(line: &str) -> String {
    if line.is_empty() {
        "#".to_string()
    } else {
        format!("# {line}")
    }
}

fn def_tokens(def: &Def) -> Tokens {
    quote! {
        $(head(&def.doc, &def.attrs))
        $(if def.export => export$[' '])def $(def.name.printed()) $(signature(&def.params, &def.io)) {
            $(for stmt in &def.body join ($['\r']) => $(stmt_tokens(stmt)))
        }
    }
}

fn extern_tokens(ext: &Extern) -> Tokens {
    quote! {
        $(head(&ext.doc, &ext.attrs))
        $(if ext.export => export$[' '])extern $(if ext.strict => --strict$[' '])$(ext.name.printed()) $(signature(&ext.params, &ext.io))
    }
}

/// `[` one parameter per line `]`, trailing comments aligned two columns past the longest
/// parameter, then `: input -> output` when declared.
fn signature(params: &Params, io: &Option<(Type, Type)>) -> Tokens {
    let texts: Vec<String> = params.iter().map(|param| param_text(param) + ",").collect();
    let width = texts.iter().map(String::len).max().unwrap_or(0);
    let lines: Vec<String> = texts
        .iter()
        .zip(params.iter())
        .map(|(text, param)| match param_doc(param) {
            Some(doc) => format!("{text}{}# {doc}", " ".repeat(width + 2 - text.len())),
            None => text.clone(),
        })
        .collect();
    let io =
        quote!($(if let Some((input, output)) = io => : $(input.as_str()) -> $(output.as_str())));
    if params.is_empty() {
        return quote!([]$io);
    }
    quote! {
        [
            $(for line in lines join ($['\r']) => $line)
        ]$io
    }
}

/// An attribute argument: a string single-quoted so it reads as written, or as a raw string
/// when it contains `'`; words bare where they can be; a block as given.
fn attr_arg(arg: &AttrArg) -> String {
    match arg {
        AttrArg::Str(text) if !text.contains('\'') => format!("'{text}'"),
        AttrArg::Str(text) => {
            let mut hashes = String::from("#");
            while text.contains(&format!("'{hashes}")) {
                hashes.push('#');
            }
            format!("r{hashes}'{text}'{hashes}")
        }
        AttrArg::Words(words) => format!(
            "[{}]",
            words.iter().map(|w| word(w)).collect::<Vec<_>>().join(" ")
        ),
        AttrArg::Block(text) => format!("{{ {text} }}"),
    }
}

/// A parameter as written in a signature, without its comment.
fn param_text(param: &Param) -> String {
    let completer_text = |completer: &Option<Completer>| match completer {
        Some(Completer::List(items)) => {
            format!(
                "@[{}]",
                items
                    .iter()
                    .map(|item| word(item))
                    .collect::<Vec<_>>()
                    .join(" ")
            )
        }
        Some(Completer::Command(name)) => format!("@{}", name.printed()),
        None => String::new(),
    };
    // A signature reads a bare datetime with a time of day as something else; in parentheses
    // it is the datetime.
    let default_text = |default: &Option<Value>| match default {
        Some(value @ Value::Date { .. }) => format!(" = ({})", nuon(value)),
        Some(value) => format!(" = {}", nuon(value)),
        None => String::new(),
    };
    match param {
        Param::Positional {
            name,
            ty,
            optional,
            default,
            completer,
            ..
        } => {
            let mark = if *optional && default.is_none() {
                "?"
            } else {
                ""
            };
            format!(
                "{}{mark}: {}{}{}",
                name.as_str(),
                ty.as_str(),
                completer_text(completer),
                default_text(default)
            )
        }
        Param::Rest { name, ty, .. } => format!("...{}: {}", name.as_str(), ty.as_str()),
        Param::Flag {
            long,
            short,
            ty,
            default,
            completer,
            ..
        } => {
            let short = short.map(|c| format!(" (-{c})")).unwrap_or_default();
            let typed = match ty {
                Some(ty) => format!(": {}{}", ty.as_str(), completer_text(completer)),
                None => String::new(),
            };
            format!("--{}{short}{typed}{}", long.as_str(), default_text(default))
        }
    }
}

/// A parameter's documentation on one line: Nushell reads only the comment beside it.
fn param_doc(param: &Param) -> Option<String> {
    let doc = match param {
        Param::Positional { doc, .. } | Param::Rest { doc, .. } | Param::Flag { doc, .. } => {
            doc.as_deref()?
        }
    };
    Some(
        doc.split('\n')
            .map(str::trim)
            .filter(|line| !line.is_empty())
            .collect::<Vec<_>>()
            .join(" "),
    )
}

fn stmt_tokens(stmt: &Stmt) -> Tokens {
    match stmt {
        Stmt::Alias { name, target } => quote!(alias $(name.printed()) = $(target.printed())),
        Stmt::Let { name, value } => quote!(let $(name.as_str()) = $(expr_tokens(value, true))),
        Stmt::Pipeline(stages) => {
            quote!($(for stage in stages join ( | ) => $(expr_tokens(stage, false))))
        }
    }
}

/// An expression; `statement_value` is a record that is the whole right side of a `let`.
fn expr_tokens(expr: &Expr, statement_value: bool) -> Tokens {
    match expr {
        Expr::Var(name) => quote!($(format!("${}", name.as_str()))),
        Expr::Literal(value) => quote!($(nuon(value))),
        Expr::Str(text) => quote!($(word(text))),
        Expr::List(items) => {
            quote!([$(for item in items join ($[' ']) => $(expr_tokens(item, false)))])
        }
        Expr::Record(fields) if statement_value || fields.len() > 3 => quote! {
            {
                $(for (key, value) in fields join ($['\r']) => $(key.as_str()): $(expr_tokens(value, false)))
            }
        },
        Expr::Record(fields) => {
            quote!({$(for (key, value) in fields join (, ) => $(key.as_str()): $(expr_tokens(value, false)))})
        }
        Expr::Call { name, args } => {
            quote!($(name.printed())$(for arg in args => $[' ']$(expr_tokens(arg, false))))
        }
        Expr::External { name, args } => {
            quote!(^$(name.as_str())$(for arg in args => $[' ']$(expr_tokens(arg, false))))
        }
        Expr::Group(inner) => quote!(($(expr_tokens(inner, false)))),
        Expr::Infix { lhs, op, rhs } => {
            quote!($(expr_tokens(lhs, false)) $(op.as_str()) $(expr_tokens(rhs, false)))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ident(s: &str) -> Ident {
        Ident::new(s).unwrap()
    }

    #[test]
    fn prints_a_def() {
        let def = Def {
            export: true,
            doc: vec![
                vec!["Greet someone".into()],
                vec!["Loudly, if asked.\nOr not.".into()],
            ],
            attrs: vec![Attr {
                name: FlagName::new("usage").unwrap(),
                args: vec![AttrArg::Str("arg \"<name>\" help=\"Who\"".into())],
            }],
            name: CommandName::new("main").unwrap(),
            params: Params::new(vec![
                Param::Positional {
                    name: ident("name"),
                    ty: Type::new("string").unwrap(),
                    optional: false,
                    default: None,
                    completer: None,
                    doc: Some("Who\nby name".into()),
                },
                Param::Flag {
                    long: FlagName::new("loud").unwrap(),
                    short: Some('l'),
                    ty: None,
                    default: None,
                    completer: None,
                    doc: Some("Shout".into()),
                },
            ])
            .unwrap(),
            io: None,
            body: vec![
                Stmt::Let {
                    name: ident("usage"),
                    value: Expr::Record(vec![
                        (ident("cmd"), Expr::List(vec![])),
                        (
                            ident("args"),
                            Expr::Record(vec![(ident("name"), Expr::Var(ident("name")))]),
                        ),
                        (
                            ident("flags"),
                            Expr::Record(vec![(
                                ident("loud"),
                                Expr::Group(Box::new(Expr::Call {
                                    name: CommandName::new("not").unwrap(),
                                    args: vec![Expr::Var(ident("loud"))],
                                })),
                            )]),
                        ),
                    ]),
                },
                Stmt::Pipeline(vec![
                    Expr::Var(ident("in")),
                    Expr::Call {
                        name: CommandName::new("run").unwrap(),
                        args: vec![Expr::Str("../script.nu".into())],
                    },
                ]),
            ],
        };
        let module = Module {
            preamble: vec![Stmt::Alias {
                name: CommandName::new("attr usage").unwrap(),
                target: CommandName::new("echo").unwrap(),
            }],
            items: vec![Item::Def(def)],
        };
        let expected = r#"alias "attr usage" = echo

# Greet someone
#
# Loudly, if asked.
# Or not.
@usage 'arg "<name>" help="Who"'
export def main [
    name: string,  # Who by name
    --loud (-l),   # Shout
] {
    let usage = {
        cmd: []
        args: {name: $name}
        flags: {loud: (not $loud)}
    }
    $in | run "../script.nu"
}
"#;
        assert_eq!(print(&module), expected);
    }

    #[test]
    fn prints_an_extern_with_structured_output_and_a_bare_helper() {
        let helper = Def {
            export: false,
            doc: vec![],
            attrs: vec![],
            name: CommandName::new("complete region").unwrap(),
            params: Params::default(),
            io: None,
            body: vec![Stmt::Pipeline(vec![
                Expr::External {
                    name: "sh".into(),
                    args: vec![Expr::Str("-c".into()), Expr::Str("demo regions".into())],
                },
                Expr::Call {
                    name: CommandName::new("lines").unwrap(),
                    args: vec![],
                },
            ])],
        };
        let ext = Extern {
            export: true,
            doc: vec![vec!["Show status".into()]],
            attrs: vec![Attr {
                name: FlagName::new("structured").unwrap(),
                args: vec![
                    AttrArg::Words(vec!["--format=json".into()]),
                    AttrArg::Block("from json".into()),
                ],
            }],
            name: CommandName::new("demo status").unwrap(),
            params: Params::new(vec![Param::Flag {
                long: FlagName::new("format").unwrap(),
                short: None,
                ty: Some(Type::new("string").unwrap()),
                default: None,
                completer: Some(Completer::List(vec!["human".into(), "json".into()])),
                doc: Some("Output format".into()),
            }])
            .unwrap(),
            io: Some((
                Type::new("nothing").unwrap(),
                Type::new("record<ok: bool>").unwrap(),
            )),
            strict: true,
        };
        let module = Module {
            preamble: vec![],
            items: vec![Item::Def(helper), Item::Extern(ext)],
        };
        let expected = r#"def "complete region" [] {
    ^sh -c "demo regions" | lines
}

# Show status
@structured ["--format=json"] { from json }
export extern --strict "demo status" [
    --format: string@[human json],  # Output format
]: nothing -> record<ok: bool>
"#;
        assert_eq!(print(&module), expected);
    }

    #[test]
    fn params_must_be_ordered() {
        let flag = Param::Flag {
            long: FlagName::new("x").unwrap(),
            short: None,
            ty: None,
            default: None,
            completer: None,
            doc: None,
        };
        let positional = Param::Positional {
            name: ident("a"),
            ty: Type::new("string").unwrap(),
            optional: false,
            default: None,
            completer: None,
            doc: None,
        };
        assert!(Params::new(vec![flag, positional]).is_err());
    }
}
