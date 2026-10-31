//! `nus model` prints what a target is handed, as NUON a script reads back: the stage
//! between the assembled spec and the module.

use std::path::{Path, PathBuf};
use std::process::Command;

use nu_protocol::{Span, Value};

fn fixtures() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../fixtures")
}

fn model(args: &[&str]) -> Value {
    let output = Command::new(env!("CARGO_BIN_EXE_nus"))
        .arg("model")
        .args(args)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    nuon::from_nuon(
        &String::from_utf8_lossy(&output.stdout),
        Some(Span::unknown()),
    )
    .expect("nus model prints NUON")
}

fn at(value: &Value, path: &[&str]) -> Value {
    path.iter().fold(value.clone(), |value, key| {
        value
            .get_data_by_key(key)
            .unwrap_or_else(|| panic!("no `{key}` in {value:?}"))
    })
}

#[test]
fn a_script_model_carries_its_parameters_and_what_runs() {
    let script = fixtures().join("minimal/script.nu");
    let tree = model(&[script.to_str().unwrap()]);
    assert_eq!(at(&tree, &["bin"]).coerce_string().unwrap(), "greet");
    assert!(at(&tree, &["service"]).is_nothing());
    let root = at(&tree, &["commands"]).into_list().unwrap().remove(0);
    let flags = at(&root, &["flags"]).into_list().unwrap();
    let times = flags
        .iter()
        .find(|flag| at(flag, &["usage_name"]).coerce_string().unwrap() == "times")
        .unwrap();
    // A default as NUON text, a kind and a type as words.
    assert_eq!(at(times, &["default"]).coerce_string().unwrap(), "1");
    assert_eq!(at(times, &["kind"]).coerce_string().unwrap(), "valued");
    assert_eq!(at(times, &["ty"]).coerce_string().unwrap(), "int");
    // What runs: the script, by its path.
    let run = at(&root, &["execution", "script"]).coerce_string().unwrap();
    assert!(run.ends_with("script.nu"), "{run}");
}

#[test]
fn a_service_model_carries_the_requests() {
    let dir = fixtures().join("http-petstore");
    let tree = model(&[
        dir.join("petstore.usage.kdl").to_str().unwrap(),
        "--http",
        dir.join("petstore.http.kdl").to_str().unwrap(),
    ]);
    assert_eq!(
        at(&tree, &["service", "base"]).coerce_string().unwrap(),
        "https://petstore.example.com/v1"
    );
    assert_eq!(
        at(&tree, &["service", "auths"]).into_list().unwrap(),
        [Value::test_string("bearer")]
    );
    let commands = at(&tree, &["commands"]).into_list().unwrap();
    assert_eq!(
        at(&commands[0], &["execution"]).coerce_string().unwrap(),
        "service"
    );
    let show = commands
        .iter()
        .find(|command| {
            at(command, &["path"]).into_list().unwrap() == [Value::test_string("show-pet-by-id")]
        })
        .unwrap();
    let request = at(show, &["execution", "request"]);
    assert_eq!(at(&request, &["method"]).coerce_string().unwrap(), "get");
    assert_eq!(
        at(&request, &["path"]).coerce_string().unwrap(),
        "/pets/{petId}"
    );
    let wire = at(&request, &["params"]).into_list().unwrap().remove(0);
    assert_eq!(at(&wire, &["location"]).coerce_string().unwrap(), "path");
    assert_eq!(at(&wire, &["var"]).coerce_string().unwrap(), "pet_id");
    // The structured output, decoded `from json` with the schema's conversions.
    assert_eq!(
        at(show, &["structured", "decoder", "from", "format"])
            .coerce_string()
            .unwrap(),
        "json"
    );
    let conversions = at(show, &["structured", "conversions"])
        .into_list()
        .unwrap();
    assert_eq!(
        at(&conversions[0], &["ty"]).coerce_string().unwrap(),
        "datetime"
    );
}
