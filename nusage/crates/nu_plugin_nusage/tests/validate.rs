//! `nusage validate` through the plugin, in process: the CLI's interface, answering with the
//! findings as rows.

use nu_plugin_nusage::NusagePlugin;
use nusage_plugin::nu_protocol::{ListStream, Signals, Span, Value, record};
use nusage_plugin::test::{harness, value};

fn schema_file(name: &str, text: &str) -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!("nu-plugin-nusage-{name}-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let file = dir.join("schema.json");
    std::fs::write(&file, text).unwrap();
    file
}

const SCHEMA: &str = r#"{"type": "object", "properties": {"ok": {"type": "boolean"}}, "required": ["ok"], "additionalProperties": false}"#;

fn rows(value: &Value) -> Vec<(String, Option<i64>, String)> {
    value
        .clone()
        .into_list()
        .unwrap()
        .iter()
        .map(|row| {
            (
                row.get_data_by_key("document")
                    .unwrap()
                    .coerce_string()
                    .unwrap(),
                row.get_data_by_key("line").unwrap().as_int().ok(),
                row.get_data_by_key("path")
                    .unwrap()
                    .coerce_string()
                    .unwrap(),
            )
        })
        .collect()
}

#[test]
fn the_signature_is_the_clis() {
    let plugin = NusagePlugin::new().unwrap();
    let test = harness("nusage", plugin).unwrap();
    let state = test.engine_state();
    let decl = state.get_decl(state.find_decl(b"nusage validate", &[]).unwrap());
    let signature = decl.signature();
    // The CLI's words: its positionals, its flag, its description.
    assert_eq!(
        signature.description,
        "Hold JSON documents to a JSON Schema"
    );
    assert_eq!(signature.required_positional[0].name, "schema");
    assert_eq!(
        signature.rest_positional.as_ref().unwrap().name,
        "documents"
    );
    assert!(
        signature
            .named
            .iter()
            .any(|flag| flag.long == "lines" && flag.arg.is_none())
    );
    assert!(signature.extra_description.contains("exit code 2"));
}

#[test]
fn documents_are_held_to_the_schema_as_rows() {
    let schema = schema_file("rows", SCHEMA);
    let schema_word = format!("{:?}", schema.to_string_lossy());
    let mut test = harness("nusage", NusagePlugin::new().unwrap()).unwrap();
    // Text input, one document: a finding at its path, no line.
    let found = value(
        &mut test,
        &format!(r#"'{{"ok": "yes"}}' | nusage validate {schema_word}"#),
    )
    .unwrap();
    assert_eq!(
        rows(&found),
        [("input".to_string(), None, "/ok".to_string())]
    );
    // A value as the document it is, conforming: no rows.
    let none = value(
        &mut test,
        &format!("{{ok: true}} | nusage validate {schema_word}"),
    )
    .unwrap();
    assert!(none.into_list().unwrap().is_empty());
    // Lines: each is a document, and a finding names its line; text that is not JSON is a
    // finding with no path.
    let lines = value(
        &mut test,
        &format!("\"{{\\\"ok\\\": true}}\\n\\n{{\\\"ok\\\": 1}}\\nnope\\n\" | nusage validate --lines {schema_word}"),
    )
    .unwrap();
    assert_eq!(
        rows(&lines),
        [
            ("input".to_string(), Some(3), "/ok".to_string()),
            ("input".to_string(), Some(4), String::new()),
        ]
    );
    // A stream of values: one document per item, numbered.
    let items = vec![
        Value::test_record(record! {"ok" => Value::test_bool(true)}),
        Value::test_record(record! {"ok" => Value::test_int(2)}),
    ];
    let stream = test
        .eval_with(
            &format!("nusage validate {schema_word}"),
            ListStream::new(items.into_iter(), Span::test_data(), Signals::empty()).into(),
        )
        .unwrap()
        .into_value(Span::test_data())
        .unwrap();
    assert_eq!(
        rows(&stream),
        [("input".to_string(), Some(2), "/ok".to_string())]
    );
    // A list value is the one document it is, a JSON array.
    let array = value(
        &mut test,
        &format!("[{{ok: true}}] | nusage validate {schema_word}"),
    )
    .unwrap();
    assert_eq!(rows(&array), [("input".to_string(), None, String::new())]);
    // A document by its path, named as given.
    let doc = schema.with_file_name("doc.json");
    std::fs::write(&doc, r#"{"ok": true, "extra": 1}"#).unwrap();
    let by_path = value(
        &mut test,
        &format!("nusage validate {schema_word} {:?}", doc.to_string_lossy()),
    )
    .unwrap();
    assert_eq!(
        rows(&by_path),
        [(doc.to_string_lossy().to_string(), None, String::new())]
    );
    std::fs::remove_dir_all(schema.parent().unwrap()).unwrap();
}

#[test]
fn a_schema_that_holds_nothing_is_an_error() {
    let schema = schema_file("bad", r#"{"type": "whatever"}"#);
    let mut test = harness("nusage", NusagePlugin::new().unwrap()).unwrap();
    let err = value(
        &mut test,
        &format!("'{{}}' | nusage validate {:?}", schema.to_string_lossy()),
    )
    .unwrap_err();
    assert!(err.to_string().contains("not in the dialect"), "{err}");
    std::fs::remove_dir_all(schema.parent().unwrap()).unwrap();
}

/// The built plugin under the Nushell on PATH, registered for one run with `--plugins`:
/// the handshake, the signature as Nushell reads it, and a call. Skipped without `nu`,
/// except in CI, where it fails.
#[test]
fn the_binary_serves_nushell() {
    if std::process::Command::new("nu")
        .arg("--version")
        .output()
        .is_err()
    {
        assert!(
            std::env::var("CI").as_deref() != Ok("true"),
            "nu is not on PATH"
        );
        eprintln!("skipped: nu is not on PATH");
        return;
    }
    let schema = schema_file("binary", SCHEMA);
    let plugin = env!("CARGO_BIN_EXE_nu_plugin_nusage");
    let code = format!(
        r#"'{{"ok": "yes"}}' | nusage validate {:?} | to nuon"#,
        schema.to_string_lossy()
    );
    let output = std::process::Command::new("nu")
        .args(["-n", "--plugins", &format!("[{plugin:?}]"), "-c", &code])
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let stdout = String::from_utf8_lossy(&output.stdout);
    // The findings as a table, one row: the input, at `/ok`.
    assert!(stdout.contains("[input, null, /ok,"), "{stdout}");
    std::fs::remove_dir_all(schema.parent().unwrap()).unwrap();
}
