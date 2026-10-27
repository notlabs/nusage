use std::fmt::Write;

use crate::Literal;
use crate::literal::{is_bare_word, nuon, quote};
use crate::syntax::*;

const INDENT: &str = "    ";

/// Write a module as Nushell source, in nufmt's layout.
pub fn print(module: &Module) -> String {
    let mut out = String::new();
    for stmt in &module.preamble {
        write_stmt(&mut out, stmt, 0);
        out.push('\n');
    }
    for (index, def) in module.defs.iter().enumerate() {
        if index > 0 || !module.preamble.is_empty() {
            out.push('\n');
        }
        write_def(&mut out, def);
    }
    out
}

fn write_def(out: &mut String, def: &Def) {
    for (index, paragraph) in def.doc.iter().enumerate() {
        if index > 0 {
            out.push_str("#\n");
        }
        for line in paragraph {
            if line.is_empty() {
                out.push_str("#\n");
            } else {
                writeln!(out, "# {line}").expect("string write");
            }
        }
    }
    for attr in &def.attrs {
        writeln!(out, "@{} {}", attr.name.as_str(), attr_value(&attr.value)).expect("string write");
    }
    if def.export {
        out.push_str("export ");
    }
    write!(out, "def {} [", def.name.printed()).expect("string write");
    if def.params.is_empty() {
        out.push(']');
    } else {
        out.push('\n');
        let lines: Vec<(String, Option<&str>)> = def
            .params
            .iter()
            .map(|param| (param_text(param) + ",", param_doc(param)))
            .collect();
        let width = lines.iter().map(|(text, _)| text.len()).max().unwrap_or(0);
        for (text, doc) in &lines {
            out.push_str(INDENT);
            out.push_str(text);
            if let Some(doc) = doc {
                for _ in text.len()..width + 2 {
                    out.push(' ');
                }
                write!(out, "# {doc}").expect("string write");
            }
            out.push('\n');
        }
        out.push(']');
    }
    if let Some((input, output)) = &def.io {
        write!(out, ": {} -> {}", input.as_str(), output.as_str()).expect("string write");
    }
    out.push_str(" {\n");
    for stmt in &def.body {
        write_stmt(out, stmt, 1);
        out.push('\n');
    }
    out.push_str("}\n");
}

/// An attribute's value: a string single-quoted, or as a raw string when it contains `'`.
fn attr_value(value: &Literal) -> String {
    match value {
        Literal::Str(text) if !text.contains('\'') => format!("'{text}'"),
        Literal::Str(text) => {
            let mut hashes = String::from("#");
            while text.contains(&format!("'{hashes}")) {
                hashes.push('#');
            }
            format!("r{hashes}'{text}'{hashes}")
        }
        other => nuon(other),
    }
}

fn param_text(param: &Param) -> String {
    match param {
        Param::Positional {
            name,
            ty,
            optional,
            completer,
            ..
        } => {
            let mut text = name.as_str().to_string();
            if *optional {
                text.push('?');
            }
            text.push_str(": ");
            text.push_str(ty.as_str());
            if let Some(completer) = completer {
                text.push_str(&completer_text(completer));
            }
            text
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
            let mut text = format!("--{}", long.as_str());
            if let Some(short) = short {
                write!(text, " (-{short})").expect("string write");
            }
            if let Some(ty) = ty {
                text.push_str(": ");
                text.push_str(ty.as_str());
                if let Some(completer) = completer {
                    text.push_str(&completer_text(completer));
                }
            }
            if let Some(default) = default {
                text.push_str(" = ");
                text.push_str(&nuon(default));
            }
            text
        }
    }
}

fn completer_text(completer: &Completer) -> String {
    match completer {
        Completer::List(items) => {
            let words: Vec<String> = items
                .iter()
                .map(|item| {
                    if is_bare_word(item) {
                        item.clone()
                    } else {
                        quote(item)
                    }
                })
                .collect();
            format!("@[{}]", words.join(" "))
        }
        Completer::Command(name) => format!("@{}", quote(name.as_str())),
    }
}

fn param_doc(param: &Param) -> Option<&str> {
    match param {
        Param::Positional { doc, .. } | Param::Rest { doc, .. } | Param::Flag { doc, .. } => {
            doc.as_deref()
        }
    }
}

fn write_stmt(out: &mut String, stmt: &Stmt, depth: usize) {
    let indent = INDENT.repeat(depth);
    out.push_str(&indent);
    match stmt {
        Stmt::Alias { name, target } => {
            write!(out, "alias {} = {}", name.printed(), target.printed()).expect("string write")
        }
        Stmt::Let { name, value } => {
            write!(out, "let {} = ", name.as_str()).expect("string write");
            write_expr(out, value, depth, true);
        }
        Stmt::Pipeline(stages) => {
            for (index, stage) in stages.iter().enumerate() {
                if index > 0 {
                    out.push_str(" | ");
                }
                write_expr(out, stage, depth, false);
            }
        }
    }
}

/// nufmt's record layout: a record that is a statement's value goes one field per line; a
/// nested record stays on one line up to three fields.
fn write_expr(out: &mut String, expr: &Expr, depth: usize, statement_value: bool) {
    match expr {
        Expr::Var(name) => write!(out, "${}", name.as_str()).expect("string write"),
        Expr::Literal(value) => out.push_str(&nuon(value)),
        Expr::Path(path) => {
            if is_bare_path(path) {
                out.push_str(path);
            } else {
                out.push_str(&quote(path));
            }
        }
        Expr::List(items) => {
            out.push('[');
            for (index, item) in items.iter().enumerate() {
                if index > 0 {
                    out.push(' ');
                }
                write_expr(out, item, depth, false);
            }
            out.push(']');
        }
        Expr::Record(fields) => {
            if statement_value || fields.len() > 3 {
                out.push_str("{\n");
                let inner = INDENT.repeat(depth + 1);
                for (key, value) in fields {
                    out.push_str(&inner);
                    write!(out, "{}: ", key.as_str()).expect("string write");
                    write_expr(out, value, depth + 1, false);
                    out.push('\n');
                }
                out.push_str(&INDENT.repeat(depth));
                out.push('}');
            } else {
                out.push('{');
                for (index, (key, value)) in fields.iter().enumerate() {
                    if index > 0 {
                        out.push_str(", ");
                    }
                    write!(out, "{}: ", key.as_str()).expect("string write");
                    write_expr(out, value, depth, false);
                }
                out.push('}');
            }
        }
        Expr::Call { name, args } => {
            out.push_str(&name.printed());
            for arg in args {
                out.push(' ');
                write_expr(out, arg, depth, false);
            }
        }
    }
}

/// A path that Nushell reads as one bare word: no spaces, quotes or shell-significant
/// characters.
fn is_bare_path(path: &str) -> bool {
    !path.is_empty()
        && path.chars().all(|c| {
            c.is_ascii_alphanumeric() || matches!(c, '_' | '-' | '.' | '/' | '\\' | ':' | '~')
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ident(s: &str) -> Ident {
        Ident::new(s).unwrap()
    }

    #[test]
    fn prints_a_def_in_nufmt_layout() {
        let def = Def {
            export: true,
            doc: vec![vec!["Greet someone".into()]],
            attrs: vec![Attr {
                name: FlagName::new("usage").unwrap(),
                value: Literal::Str("arg \"<name>\" help=\"Who\"".into()),
            }],
            name: CommandName::new("main").unwrap(),
            params: Params::new(vec![
                Param::Positional {
                    name: ident("name"),
                    ty: Type::new("string").unwrap(),
                    optional: false,
                    completer: None,
                    doc: Some("Who".into()),
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
                    ]),
                },
                Stmt::Pipeline(vec![
                    Expr::Var(ident("in")),
                    Expr::Call {
                        name: CommandName::new("run").unwrap(),
                        args: vec![Expr::Path("../script.nu".into())],
                    },
                ]),
            ],
        };
        let module = Module {
            preamble: vec![Stmt::Alias {
                name: CommandName::new("attr usage").unwrap(),
                target: CommandName::new("echo").unwrap(),
            }],
            defs: vec![def],
        };
        let expected = "\
alias \"attr usage\" = echo

# Greet someone
@usage 'arg \"<name>\" help=\"Who\"'
export def main [
    name: string,  # Who
    --loud (-l),   # Shout
] {
    let usage = {
        cmd: []
        args: {name: $name}
    }
    $in | run ../script.nu
}
";
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
            completer: None,
            doc: None,
        };
        assert!(Params::new(vec![flag, positional]).is_err());
    }
}
