//! Values across the boundary: a JSON document as the value a command returns, and a value
//! as the JSON document a schema is held to. JSON is what the CLI reads and writes, so a
//! plugin that answers as the CLI does meets it here.

use nu_protocol::{LabeledError, Record, Span, Value};

/// A JSON document as a value: an object a record with the document's key order, an array
/// a list, a number an int when it is one.
pub fn from_json(json: serde_json::Value, span: Span) -> Value {
    match json {
        serde_json::Value::Null => Value::nothing(span),
        serde_json::Value::Bool(b) => Value::bool(b, span),
        serde_json::Value::Number(n) => match n.as_i64() {
            Some(i) => Value::int(i, span),
            None => Value::float(n.as_f64().unwrap_or_default(), span),
        },
        serde_json::Value::String(s) => Value::string(s, span),
        serde_json::Value::Array(items) => Value::list(
            items
                .into_iter()
                .map(|item| from_json(item, span))
                .collect(),
            span,
        ),
        serde_json::Value::Object(fields) => {
            let mut record = Record::new();
            for (key, value) in fields {
                record.push(key, from_json(value, span));
            }
            Value::record(record, span)
        }
    }
}

/// A value as a JSON document, as `to json` writes it: a date in RFC 3339, a filesize its
/// bytes, a duration its nanoseconds. A value JSON has no form for is an error at the
/// value.
pub fn to_json(value: &Value) -> Result<serde_json::Value, LabeledError> {
    Ok(match value {
        Value::Nothing { .. } => serde_json::Value::Null,
        Value::Bool { val, .. } => serde_json::Value::Bool(*val),
        Value::Int { val, .. } => serde_json::Value::from(*val),
        Value::Filesize { val, .. } => serde_json::Value::from(val.get()),
        Value::Duration { val, .. } => serde_json::Value::from(*val),
        Value::Float { val, .. } => serde_json::Number::from_f64(*val)
            .map(serde_json::Value::Number)
            .unwrap_or(serde_json::Value::Null),
        Value::String { val, .. } => serde_json::Value::String(val.clone()),
        Value::Glob { val, .. } => serde_json::Value::String(val.clone()),
        Value::Date { val, .. } => serde_json::Value::String(val.to_rfc3339()),
        Value::List { vals, .. } => {
            serde_json::Value::Array(vals.iter().map(to_json).collect::<Result<_, _>>()?)
        }
        Value::Record { val, .. } => {
            let mut fields = serde_json::Map::new();
            for (key, value) in val.iter() {
                fields.insert(key.clone(), to_json(value)?);
            }
            serde_json::Value::Object(fields)
        }
        other => {
            return Err(
                LabeledError::new(format!("a {} has no JSON form", other.get_type()))
                    .with_label("this value", other.span()),
            );
        }
    })
}

/// A JSON document in one spelling for one value: object keys sorted, so that two documents
/// that say the same thing are the same text, as a key or a hash wants.
pub fn canonical(json: &serde_json::Value) -> String {
    fn sorted(json: &serde_json::Value) -> serde_json::Value {
        match json {
            serde_json::Value::Array(items) => {
                serde_json::Value::Array(items.iter().map(sorted).collect())
            }
            serde_json::Value::Object(fields) => {
                let mut keys: Vec<&String> = fields.keys().collect();
                keys.sort();
                let mut out = serde_json::Map::new();
                for key in keys {
                    out.insert(key.clone(), sorted(&fields[key]));
                }
                serde_json::Value::Object(out)
            }
            other => other.clone(),
        }
    }
    sorted(json).to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn values_round_trip_through_json() {
        let json = json!({"ok": true, "n": 3, "x": 1.5, "s": "a", "l": [1, null], "r": {"b": "c"}});
        let value = from_json(json.clone(), Span::test_data());
        assert_eq!(to_json(&value).unwrap(), json);
        assert_eq!(to_json(&Value::test_filesize(2048)).unwrap(), json!(2048));
        assert!(
            to_json(&Value::test_closure(nu_protocol::engine::Closure {
                block_id: nu_protocol::BlockId::new(0),
                captures: Vec::new(),
            }))
            .is_err()
        );
    }

    #[test]
    fn canonical_sorts_keys_at_every_depth() {
        let a = json!({"b": {"y": 1, "x": [{"q": 1, "p": 2}]}, "a": 0});
        let b = json!({"a": 0, "b": {"x": [{"p": 2, "q": 1}], "y": 1}});
        assert_eq!(canonical(&a), canonical(&b));
        assert_eq!(canonical(&a), r#"{"a":0,"b":{"x":[{"p":2,"q":1}],"y":1}}"#);
    }
}
