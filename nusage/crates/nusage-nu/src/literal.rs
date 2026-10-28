use std::sync::LazyLock;

pub use nu_protocol::Value;
use nu_protocol::engine::{EngineState, StateWorkingSet};

use crate::{SyntaxError, Type};

/// `to_nuon` wants an engine state only for closures and custom values, which a signature
/// default never holds; the parser's engine, with Nushell's keywords, serves both uses.
static ENGINE: LazyLock<EngineState> = LazyLock::new(nu_cmd_lang::create_default_context);

/// A value as NUON, on one line, written by Nushell's own `nuon` crate: bare where Nushell
/// reads a bare word as that value, quoted otherwise.
pub fn nuon(value: &Value) -> String {
    nuon::to_nuon(&ENGINE, value, nuon::ToNuonConfig::default())
        .expect("a signature default has no closures or custom values")
}

/// A value as a signature's default: its NUON, in parentheses for a datetime, which a
/// signature reads bare as something else.
pub fn default_text(value: &Value) -> String {
    match value {
        Value::Date { .. } => format!("({})", nuon(value)),
        _ => nuon(value),
    }
}

/// Whether Nushell's parser accepts the value as a default for a parameter of the type: the
/// signature `[p: <ty> = <default>]` is parsed, and its error, if any, is the answer. This is
/// the parser's own compatibility rule, coercions included, not a second one.
pub fn check_default(ty: &Type, value: &Value) -> Result<(), SyntaxError> {
    let source = format!(
        "def __nusage_probe [p: {} = {}] {{}}",
        ty.as_str(),
        default_text(value)
    );
    let mut working_set = StateWorkingSet::new(&ENGINE);
    nu_parser::parse(&mut working_set, None, source.as_bytes(), false);
    match working_set.parse_errors.first() {
        Some(err) => Err(SyntaxError(format!(
            "`{}` is not a default Nushell accepts for a `{}`: {err}",
            default_text(value),
            ty.as_str()
        ))),
        None => Ok(()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strings_are_written_as_nuon_writes_them() {
        assert_eq!(nuon(&Value::test_string("tar")), "\"tar\"");
        assert_eq!(nuon(&Value::test_string("a b")), "\"a b\"");
    }

    #[test]
    fn scalars_and_lists() {
        assert_eq!(nuon(&Value::test_int(10)), "10");
        assert_eq!(nuon(&Value::test_bool(false)), "false");
        assert_eq!(nuon(&Value::test_nothing()), "null");
        assert_eq!(nuon(&Value::test_list(vec![])), "[]");
    }

    #[test]
    fn defaults_are_judged_by_the_parser() {
        let ty = |t: &str| Type::new(t).unwrap();
        assert!(check_default(&ty("float"), &Value::test_int(1)).is_ok());
        assert!(check_default(&ty("list<string>"), &Value::test_list(vec![])).is_ok());
        assert!(
            check_default(
                &ty("list<number>"),
                &Value::test_list(vec![Value::test_int(1), Value::test_int(2)])
            )
            .is_ok()
        );
        assert!(
            check_default(
                &ty("record"),
                &Value::test_record(nu_protocol::record! { "a" => Value::test_int(1) })
            )
            .is_ok()
        );
        assert!(check_default(&ty("datetime"), &Value::test_date(Default::default())).is_ok());
        assert!(check_default(&ty("int"), &Value::test_float(1.5)).is_err());
        assert!(check_default(&ty("datetime"), &Value::test_string("latest")).is_err());
    }
}
