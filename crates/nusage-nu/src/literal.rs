use std::sync::LazyLock;

use nu_protocol::engine::EngineState;
use nu_protocol::{Span, Value};

/// A constant value, written as NUON by Nushell's own `nuon` crate.
#[derive(Debug, Clone, PartialEq)]
pub enum Literal {
    Null,
    Bool(bool),
    Int(i64),
    Float(f64),
    Str(String),
    List(Vec<Literal>),
}

/// `to_nuon` wants an engine state only for closures and custom values, which a literal never
/// holds; an empty one serves.
static ENGINE: LazyLock<EngineState> = LazyLock::new(EngineState::new);

fn value(literal: &Literal) -> Value {
    let span = Span::unknown();
    match literal {
        Literal::Null => Value::nothing(span),
        Literal::Bool(b) => Value::bool(*b, span),
        Literal::Int(i) => Value::int(*i, span),
        Literal::Float(f) => Value::float(*f, span),
        Literal::Str(s) => Value::string(s, span),
        Literal::List(items) => Value::list(items.iter().map(value).collect(), span),
    }
}

/// The literal as NUON, on one line, bare where Nushell reads a bare word as that value.
pub fn nuon(literal: &Literal) -> String {
    nuon::to_nuon(&ENGINE, &value(literal), nuon::ToNuonConfig::default())
        .expect("a literal has no closures or custom values")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strings_are_written_as_nuon_writes_them() {
        assert_eq!(nuon(&Literal::Str("tar".into())), "\"tar\"");
        assert_eq!(nuon(&Literal::Str("a b".into())), "\"a b\"");
    }

    #[test]
    fn scalars_and_lists() {
        assert_eq!(nuon(&Literal::Int(10)), "10");
        assert_eq!(nuon(&Literal::Bool(false)), "false");
        assert_eq!(nuon(&Literal::Null), "null");
        assert_eq!(nuon(&Literal::List(vec![])), "[]");
    }
}
