use std::sync::LazyLock;

pub use nu_protocol::Value;
use nu_protocol::engine::EngineState;

/// `to_nuon` wants an engine state only for closures and custom values, which a signature
/// default never holds; an empty one serves.
static ENGINE: LazyLock<EngineState> = LazyLock::new(EngineState::new);

/// A value as NUON, on one line, written by Nushell's own `nuon` crate: bare where Nushell
/// reads a bare word as that value, quoted otherwise.
pub fn nuon(value: &Value) -> String {
    nuon::to_nuon(&ENGINE, value, nuon::ToNuonConfig::default())
        .expect("a signature default has no closures or custom values")
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
}
