//! Documents held to a schema, and a schema to the dialect.
//!
//! A `format` is asserted, not only annotated as draft 2020-12 has it by default: a reader
//! converts a `date-time` string to a datetime after decoding, so a string that is not one
//! would fail the conversion, and a check that let it through would hold the document to
//! less than the reader relies on.

use std::sync::LazyLock;

use jsonschema::{Registry, Resource, Validator};
use serde_json::Value;

use crate::dialect::{DIALECT_SCHEMA, VOCABULARY_META_ID, VOCABULARY_SCHEMA};

/// Why a schema cannot hold documents.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[non_exhaustive]
pub enum SchemaError {
    /// The schema is not written in the dialect: what its meta-schema found, at the path in
    /// the schema.
    #[error("not in the dialect: {path}: {what}")]
    Dialect {
        /// A JSON pointer into the schema.
        path: String,
        /// The meta-schema's finding.
        what: String,
    },
    /// The schema cannot be compiled into a validator.
    #[error("{0}")]
    Compile(String),
}

/// Something in a document the schema does not allow.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Finding {
    /// A JSON pointer to the value in the document; empty for the whole document.
    pub path: String,
    /// What the schema found.
    pub what: String,
}

/// The dialect's meta-schema as a validator: a schema is an instance of it.
static DIALECT: LazyLock<Validator> = LazyLock::new(|| {
    let vocabulary: Value =
        serde_json::from_str(VOCABULARY_SCHEMA).expect("the vocabulary is JSON");
    let registry = Registry::new()
        .add(VOCABULARY_META_ID, Resource::from_contents(vocabulary))
        .expect("the vocabulary names itself")
        .prepare()
        .expect("the vocabulary is a schema");
    let dialect: Value = serde_json::from_str(DIALECT_SCHEMA).expect("the dialect is JSON");
    jsonschema::options()
        .with_registry(&registry)
        .build(&dialect)
        .expect("the dialect is a schema")
});

/// Whether the schema is written in the dialect: draft 2020-12, with `x-nu` where and as
/// the vocabulary allows. The first thing wrong with it when not.
pub fn conforms(schema: &Value) -> Result<(), SchemaError> {
    DIALECT
        .validate(schema)
        .map_err(|err| SchemaError::Dialect {
            path: err.instance_path().to_string(),
            what: err.to_string(),
        })
}

/// A schema that holds documents.
#[derive(Debug)]
pub struct Schema {
    validator: Validator,
}

impl Schema {
    /// The schema, held to the dialect first, since a faulty schema judges nothing.
    pub fn new(schema: &Value) -> Result<Self, SchemaError> {
        conforms(schema)?;
        let validator = jsonschema::options()
            .should_validate_formats(true)
            .build(schema)
            .map_err(|err| SchemaError::Compile(err.to_string()))?;
        Ok(Schema { validator })
    }

    /// Everything in the document the schema does not allow; empty when it conforms.
    pub fn findings(&self, document: &Value) -> Vec<Finding> {
        self.validator
            .iter_errors(document)
            .map(|err| Finding {
                path: err.instance_path().to_string(),
                what: err.to_string(),
            })
            .collect()
    }

    /// Whether the document conforms.
    pub fn is_valid(&self, document: &Value) -> bool {
        self.validator.is_valid(document)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn documents_are_held_to_the_schema() {
        let schema = Schema::new(&json!({
            "type": "object",
            "properties": {"ok": {"type": "boolean"}, "at": {"type": "string", "format": "date-time"}},
            "required": ["ok"],
            "additionalProperties": false
        }))
        .unwrap();
        assert!(schema.is_valid(&json!({"ok": true, "at": "2026-10-28T21:31:02+02:00"})));
        let findings = schema.findings(&json!({"ok": "yes", "at": "yesterday", "extra": 1}));
        let paths: Vec<&str> = findings.iter().map(|f| f.path.as_str()).collect();
        assert_eq!(paths, ["/ok", "/at", ""], "{findings:?}");
    }

    #[test]
    fn a_schema_is_held_to_the_dialect() {
        // Draft 2020-12 as it is.
        assert!(Schema::new(&json!({"type": "whatever"})).is_err());
        // The vocabulary: `x-nu` on a number, with a type and a unit of it, nested anywhere.
        let good = json!({"type": "object", "properties": {"took": {"type": "integer",
            "x-nu": {"type": "duration", "unit": "ms"}}}});
        assert_eq!(conforms(&good), Ok(()));
        for (bad, at) in [
            (
                json!({"type": "integer", "x-nu": {"type": "duration"}}),
                "/x-nu",
            ),
            (
                json!({"type": "integer", "x-nu": {"type": "duration", "unit": "parsecs"}}),
                "/x-nu/unit",
            ),
            (
                json!({"type": "string", "x-nu": {"type": "duration", "unit": "ms"}}),
                "/type",
            ),
            (
                json!({"type": "integer", "x-nu": {"type": "weight", "unit": "kg"}}),
                "/x-nu/type",
            ),
            (
                json!({"type": "object", "properties": {"size": {"type": "integer",
                "x-nu": {"type": "filesize", "unit": "lb"}}}}),
                "/properties/size/x-nu/unit",
            ),
            (
                json!({"type": "array", "items": {"anyOf": [{"type": "number",
                "x-nu": {"unit": "sec"}}]}}),
                "/items/anyOf/0/x-nu",
            ),
        ] {
            match conforms(&bad) {
                Err(SchemaError::Dialect { path, .. }) => assert_eq!(path, at, "{bad}"),
                other => panic!("{bad}: {other:?}"),
            }
        }
    }

    #[test]
    fn the_units_are_the_vocabularys() {
        // The meta-schema spells the units the reader accepts, and no others.
        let vocabulary: Value = serde_json::from_str(VOCABULARY_SCHEMA).unwrap();
        let listed = |kind: &str| -> Vec<String> {
            vocabulary["properties"]["x-nu"]["allOf"]
                .as_array()
                .unwrap()
                .iter()
                .find(|rule| rule["if"]["properties"]["type"]["const"] == kind)
                .unwrap()["then"]["properties"]["unit"]["enum"]
                .as_array()
                .unwrap()
                .iter()
                .map(|unit| unit.as_str().unwrap().to_string())
                .collect()
        };
        assert_eq!(listed("duration"), crate::UNITS_OF_DURATION);
        assert_eq!(listed("datetime"), crate::UNITS_OF_DATETIME);
        assert_eq!(listed("filesize"), crate::UNITS_OF_FILESIZE);
    }
}
