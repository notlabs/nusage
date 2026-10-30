//! The dialect's meta-schemas, and schemas of other dialects read as this one.
//!
//! The identifiers are names, not locations: nothing is fetched from them. A schema that
//! declares `"$schema": DIALECT_ID` says it is written in the dialect; one that declares
//! nothing is read as if it did, since `x-nu` means nothing in any other.

use serde_json::{Map, Value};

/// The dialect: draft 2020-12 with the Nushell vocabulary.
pub const DIALECT_ID: &str = "https://github.com/notlabs/nusage/schema/nu/dialect";
/// The Nushell vocabulary, as a dialect's `$vocabulary` names it.
pub const VOCABULARY_ID: &str = "https://github.com/notlabs/nusage/schema/nu/vocab";
/// The vocabulary's meta-schema: what `x-nu` may say, and where it may stand.
pub const VOCABULARY_META_ID: &str = "https://github.com/notlabs/nusage/schema/nu/meta/vocab";

/// The dialect's meta-schema, as JSON text: draft 2020-12's and the vocabulary's together.
pub const DIALECT_SCHEMA: &str = include_str!("dialect/dialect.schema.json");
/// The vocabulary's meta-schema, as JSON text.
pub const VOCABULARY_SCHEMA: &str = include_str!("dialect/vocab.schema.json");

/// Rewrite an OpenAPI 3.0 schema object into draft 2020-12, in place, so the reader and
/// the validator take it as the dialect: `nullable: true` becomes `null` among the types,
/// a boolean `exclusiveMinimum` or `exclusiveMaximum` becomes the bound itself, and
/// `example` becomes `examples`. Subschemas are rewritten too. OpenAPI 3.1 schemas are
/// draft 2020-12 already and come through unchanged.
pub fn from_openapi_30(schema: &mut Value) {
    let Some(object) = schema.as_object_mut() else {
        return;
    };
    if object.remove("nullable") == Some(Value::Bool(true)) {
        make_nullable(object);
    }
    for (bound, exclusive) in [
        ("minimum", "exclusiveMinimum"),
        ("maximum", "exclusiveMaximum"),
    ] {
        match object.get(exclusive) {
            Some(Value::Bool(true)) => {
                if let Some(limit) = object.remove(bound) {
                    object.insert(exclusive.into(), limit);
                } else {
                    object.remove(exclusive);
                }
            }
            Some(Value::Bool(false)) => {
                object.remove(exclusive);
            }
            _ => {}
        }
    }
    if let Some(example) = object.remove("example")
        && let Some(examples) = object
            .entry("examples")
            .or_insert_with(|| Value::Array(Vec::new()))
            .as_array_mut()
    {
        examples.push(example);
    }
    for key in ["properties", "patternProperties", "$defs", "definitions"] {
        if let Some(Value::Object(members)) = object.get_mut(key) {
            for member in members.values_mut() {
                from_openapi_30(member);
            }
        }
    }
    for key in ["allOf", "anyOf", "oneOf", "prefixItems"] {
        if let Some(Value::Array(members)) = object.get_mut(key) {
            for member in members {
                from_openapi_30(member);
            }
        }
    }
    for key in ["items", "additionalProperties", "not", "if", "then", "else"] {
        if let Some(member) = object.get_mut(key) {
            from_openapi_30(member);
        }
    }
}

/// `null` among the schema's types: added to `type`, or as a member beside a `$ref` or a
/// union that stands for the type.
fn make_nullable(object: &mut Map<String, Value>) {
    match object.get_mut("type") {
        Some(Value::String(one)) => {
            let one = std::mem::take(one);
            object.insert(
                "type".into(),
                Value::Array(vec![Value::String(one), Value::String("null".into())]),
            );
        }
        Some(Value::Array(many)) => {
            if !many.iter().any(|ty| ty == "null") {
                many.push(Value::String("null".into()));
            }
        }
        _ => {
            let null = serde_json::json!({"type": "null"});
            for union in ["anyOf", "oneOf"] {
                if let Some(Value::Array(members)) = object.get_mut(union) {
                    members.push(null);
                    return;
                }
            }
            let rest = std::mem::take(object);
            object.insert(
                "anyOf".into(),
                Value::Array(vec![Value::Object(rest), null]),
            );
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn the_meta_schemas_are_json_and_name_themselves() {
        let dialect: Value = serde_json::from_str(DIALECT_SCHEMA).unwrap();
        assert_eq!(dialect["$id"], DIALECT_ID);
        assert_eq!(dialect["$vocabulary"][VOCABULARY_ID], true);
        let vocab: Value = serde_json::from_str(VOCABULARY_SCHEMA).unwrap();
        assert_eq!(vocab["$id"], VOCABULARY_META_ID);
    }

    #[test]
    fn openapi_30_reads_as_the_dialect() {
        let mut schema = json!({
            "type": "object",
            "properties": {
                "name": {"type": "string", "nullable": true, "example": "x"},
                "peer": {"$ref": "#/$defs/peer", "nullable": true},
                "count": {"type": "integer", "minimum": 0, "exclusiveMinimum": true},
                "ratio": {"type": "number", "maximum": 1, "exclusiveMaximum": false},
                "tags": {"type": "array", "items": {"type": "string", "nullable": true}}
            }
        });
        from_openapi_30(&mut schema);
        assert_eq!(
            schema,
            json!({
                "type": "object",
                "properties": {
                    "name": {"type": ["string", "null"], "examples": ["x"]},
                    "peer": {"anyOf": [{"$ref": "#/$defs/peer"}, {"type": "null"}]},
                    "count": {"type": "integer", "exclusiveMinimum": 0},
                    "ratio": {"type": "number", "maximum": 1},
                    "tags": {"type": "array", "items": {"type": ["string", "null"]}}
                }
            })
        );
    }
}
