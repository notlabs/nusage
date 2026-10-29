//! JSON documents held to a JSON Schema: the schema to its metaschema first, then each
//! document to the schema. A binary's output is a contract the module's types rely on, and
//! this is how a conformance suite checks the raw output before Nushell decodes it.
//!
//! A `format` is asserted, not only annotated as draft 2020-12 has it by default: the module
//! converts a `date-time` string to a datetime after decoding, so a string that is not one
//! fails the call, and a suite that let it through would hold the output to less than the
//! module relies on.

use std::io::Read;
use std::path::Path;

use serde_json::Value;

/// The findings for `documents` against the schema at `schema`, as `<document>:<path>:
/// <what>` lines; empty when every document conforms. A document named `-` is standard
/// input; no documents holds the schema alone. The error is a check that did not run: a
/// schema or document that cannot be read, or a schema its metaschema refuses, since a
/// faulty schema judges nothing.
pub fn validate(schema: &Path, documents: &[impl AsRef<Path>]) -> Result<Vec<String>, String> {
    let text =
        std::fs::read_to_string(schema).map_err(|err| format!("{}: {err}", schema.display()))?;
    let schema_json: Value =
        serde_json::from_str(&text).map_err(|err| format!("{}: {err}", schema.display()))?;
    jsonschema::meta::validate(&schema_json)
        .map_err(|err| format!("{}: {err}", schema.display()))?;
    let validator = jsonschema::options()
        .should_validate_formats(true)
        .build(&schema_json)
        .map_err(|err| format!("{}: {err}", schema.display()))?;
    let mut findings = Vec::new();
    let mut check = |name: &str, text: &str| {
        let document: Value = match serde_json::from_str(text) {
            Ok(document) => document,
            Err(err) => {
                findings.push(format!("{name}: {err}"));
                return;
            }
        };
        for error in validator.iter_errors(&document) {
            findings.push(format!("{name}:{}: {error}", error.instance_path()));
        }
    };
    for document in documents {
        let document = document.as_ref();
        let mut text = String::new();
        if document == Path::new("-") {
            std::io::stdin()
                .read_to_string(&mut text)
                .map_err(|err| format!("standard input: {err}"))?;
        } else {
            text = std::fs::read_to_string(document)
                .map_err(|err| format!("{}: {err}", document.display()))?;
        }
        check(&document.display().to_string(), &text);
    }
    Ok(findings)
}

#[cfg(test)]
mod tests {
    use super::validate;

    fn file(dir: &std::path::Path, name: &str, text: &str) -> std::path::PathBuf {
        let path = dir.join(name);
        std::fs::write(&path, text).unwrap();
        path
    }

    #[test]
    fn documents_are_held_to_the_schema_and_the_schema_to_its_metaschema() {
        let dir = std::env::temp_dir().join(format!("nusage-validate-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let schema = file(
            &dir,
            "status.schema.json",
            r#"{"$schema": "https://json-schema.org/draft/2020-12/schema", "type": "object",
                "properties": {"ok": {"type": "boolean"}}, "required": ["ok"],
                "additionalProperties": false}"#,
        );
        let good = file(&dir, "good.json", r#"{"ok": true}"#);
        let bad = file(&dir, "bad.json", r#"{"ok": "yes", "extra": 1}"#);
        let broken = file(&dir, "broken.json", "{");
        assert_eq!(validate(&schema, &[&good]).unwrap(), Vec::<String>::new());
        let findings = validate(&schema, &[&good, &bad, &broken]).unwrap();
        assert_eq!(findings.len(), 3, "{findings:?}");
        assert!(
            findings[0].starts_with(&format!("{}:/ok: ", bad.display())),
            "{findings:?}"
        );
        assert!(
            findings[1].starts_with(&format!("{}:: ", bad.display())),
            "{findings:?}"
        );
        assert!(
            findings[2].starts_with(&format!("{}: ", broken.display())),
            "{findings:?}"
        );

        // A faulty schema is no finding on the document: the check did not run.
        let faulty = file(&dir, "faulty.schema.json", r#"{"type": "whatever"}"#);
        let why = validate(&faulty, &[&good]).unwrap_err();
        assert!(
            why.starts_with(&format!("{}: ", faulty.display())),
            "{why:?}"
        );
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn a_format_is_asserted() {
        // The module would convert `at` to a datetime, and fail on the second document.
        let dir =
            std::env::temp_dir().join(format!("nusage-validate-format-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let schema = file(
            &dir,
            "event.schema.json",
            r#"{"$schema": "https://json-schema.org/draft/2020-12/schema", "type": "object",
                "properties": {"at": {"type": "string", "format": "date-time"}}}"#,
        );
        let good = file(&dir, "good.json", r#"{"at": "2026-10-28T21:31:02+02:00"}"#);
        let bad = file(&dir, "bad.json", r#"{"at": "yesterday"}"#);
        assert_eq!(validate(&schema, &[&good]).unwrap(), Vec::<String>::new());
        let findings = validate(&schema, &[&bad]).unwrap();
        assert_eq!(findings.len(), 1, "{findings:?}");
        assert!(
            findings[0].starts_with(&format!("{}:/at: ", bad.display())),
            "{findings:?}"
        );
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
