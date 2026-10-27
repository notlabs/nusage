use std::fmt::Write;

/// A constant value, written as NUON.
#[derive(Debug, Clone, PartialEq)]
pub enum Literal {
    Null,
    Bool(bool),
    Int(i64),
    Float(f64),
    Str(String),
    List(Vec<Literal>),
}

/// Whether a string can be written as a bare word: letters, digits, `_`, `-`, `.`, not
/// starting with a digit or `-`, and not a word Nushell reads as something else.
pub fn is_bare_word(text: &str) -> bool {
    let mut chars = text.chars();
    let Some(first) = chars.next() else {
        return false;
    };
    if !(first.is_ascii_alphabetic() || first == '_') {
        return false;
    }
    if !chars.all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '-' | '.')) {
        return false;
    }
    !matches!(text, "true" | "false" | "null" | "nan" | "inf")
}

/// A string as a Nushell double-quoted literal.
pub fn quote(text: &str) -> String {
    let mut out = String::with_capacity(text.len() + 2);
    out.push('"');
    for c in text.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\t' => out.push_str("\\t"),
            '\r' => out.push_str("\\r"),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

/// A string as the shortest literal that reads back as itself: bare when possible, else quoted.
pub fn string_literal(text: &str) -> String {
    if is_bare_word(text) {
        text.to_string()
    } else {
        quote(text)
    }
}

/// The literal as NUON, on one line.
pub fn nuon(value: &Literal) -> String {
    let mut out = String::new();
    write_nuon(&mut out, value);
    out
}

fn write_nuon(out: &mut String, value: &Literal) {
    match value {
        Literal::Null => out.push_str("null"),
        Literal::Bool(b) => out.push_str(if *b { "true" } else { "false" }),
        Literal::Int(i) => write!(out, "{i}").expect("string write"),
        Literal::Float(f) => {
            if f.fract() == 0.0 && f.is_finite() {
                write!(out, "{f:.1}").expect("string write")
            } else {
                write!(out, "{f}").expect("string write")
            }
        }
        Literal::Str(s) => out.push_str(&string_literal(s)),
        Literal::List(items) => {
            out.push('[');
            for (index, item) in items.iter().enumerate() {
                if index > 0 {
                    out.push(' ');
                }
                write_nuon(out, item);
            }
            out.push(']');
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bare_words_and_quoting() {
        assert_eq!(nuon(&Literal::Str("tar".into())), "tar");
        assert_eq!(nuon(&Literal::Str("a b".into())), "\"a b\"");
        assert_eq!(nuon(&Literal::Str("true".into())), "\"true\"");
        assert_eq!(nuon(&Literal::Str("3".into())), "\"3\"");
        assert_eq!(nuon(&Literal::Str("-x".into())), "\"-x\"");
        assert_eq!(nuon(&Literal::Str("a\"b".into())), "\"a\\\"b\"");
    }

    #[test]
    fn scalars_and_lists() {
        assert_eq!(nuon(&Literal::Int(10)), "10");
        assert_eq!(nuon(&Literal::Bool(false)), "false");
        assert_eq!(nuon(&Literal::Null), "null");
        assert_eq!(nuon(&Literal::Float(2.0)), "2.0");
        assert_eq!(
            nuon(&Literal::List(vec![
                Literal::Str("x".into()),
                Literal::Str("y".into())
            ])),
            "[x y]"
        );
        assert_eq!(nuon(&Literal::List(vec![])), "[]");
    }
}
