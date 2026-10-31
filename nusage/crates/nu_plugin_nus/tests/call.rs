//! `nus call` through the plugin: the script-calls fixture run by the plugin's executor,
//! in process through the harness and through the built plugin under Nushell.

use std::path::{Path, PathBuf};

use nu_plugin_nus::NusagePlugin;
use nusage_plugin::nu_protocol::Value;
use nusage_plugin::test::{harness, value};

fn fixture() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../fixtures/script-calls")
        .canonicalize()
        .unwrap()
}

#[test]
fn the_plugin_runs_a_script_in_process() {
    let script = fixture().join("script.nu");
    let script = format!("{:?}", script.to_string_lossy());
    let mut test = harness("nus", NusagePlugin::new().unwrap()).unwrap();
    let out = value(&mut test, &format!("nus call {script} nus {script} ana"));
    match out {
        Ok(value) => {
            assert_eq!(
                value.get_data_by_key("nus").unwrap(),
                Value::test_string("HELLO ANA")
            );
        }
        // The harness may run the plugin over standard output, where a script may not
        // print; then the refusal says so, and the built plugin below is the check.
        Err(err) => assert!(err.to_string().contains("standard output"), "{err}"),
    }
}

/// The built plugin under the Nushell on PATH: a script with a nested call, its print
/// passing through, its value typed. Skipped without `nu`, except in CI, where it fails.
#[test]
fn the_binary_runs_scripts_under_nushell() {
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
    let script = fixture().join("script.nu");
    let script = format!("{:?}", script.to_string_lossy());
    let plugin = env!("CARGO_BIN_EXE_nu_plugin_nus");
    let code = format!("nus call {script} nus {script} ana | to nuon");
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
    assert!(stdout.contains("callee: greeting ana"), "{stdout}");
    assert!(
        stdout.contains("nus: \"HELLO ANA\"") && stdout.contains("at: datetime"),
        "{stdout}"
    );
    // The print comes before the value, as it does from the interpreter.
    assert!(
        stdout.find("callee:").unwrap() < stdout.find("{path:").unwrap(),
        "{stdout}"
    );
}
