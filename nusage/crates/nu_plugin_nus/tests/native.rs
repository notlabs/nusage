//! The same command two ways: `nus validate` as a native command of an engine, and as the
//! plugin's command, from one implementation, give the same rows.

use nu_plugin_nus::NusagePlugin;
use nusage_plugin::nu_protocol::{PipelineData, Span};
use nusage_plugin::test::{harness, value};

const SCHEMA: &str = r#"{"type": "object", "properties": {"ok": {"type": "boolean"}}, "required": ["ok"], "additionalProperties": false}"#;

#[test]
fn the_native_command_answers_as_the_plugin_does() {
    let dir = std::env::temp_dir().join(format!("nu-plugin-nus-native-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let schema = dir.join("schema.json");
    std::fs::write(&schema, SCHEMA).unwrap();
    // No `to nuon` here: the plugin harness's engine has the core commands only, and the
    // values compare as they are.
    let source = format!(
        r#"'{{"ok": "yes", "more": 1}}' | nus validate {:?}"#,
        schema.to_string_lossy()
    );
    // In an engine of the plugin's own, with the command registered natively.
    let plugin = NusagePlugin::new().unwrap();
    let mut engine = nusage_plugin::command::engine(plugin.natives()).unwrap();
    let native = nusage_plugin::command::eval(
        &mut engine,
        &dir.to_string_lossy(),
        &source,
        PipelineData::empty(),
    )
    .unwrap()
    .into_value(Span::test_data())
    .unwrap();
    // Through the plugin protocol.
    let mut test = harness("nus", NusagePlugin::new().unwrap()).unwrap();
    let through_plugin = value(&mut test, &source).unwrap();
    assert_eq!(native, through_plugin);
    let paths: Vec<String> = native
        .into_list()
        .unwrap()
        .iter()
        .map(|row| {
            row.get_data_by_key("path")
                .unwrap()
                .coerce_string()
                .unwrap()
        })
        .collect();
    assert_eq!(paths, ["/ok", ""]);
    std::fs::remove_dir_all(&dir).unwrap();
}
