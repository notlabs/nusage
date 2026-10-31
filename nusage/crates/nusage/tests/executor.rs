//! Scripts run in the executor's engine as the interpreter runs them: the `script-calls`
//! fixture, whose script calls another three ways, each through `nus call` as a command of
//! the engine's own, so nothing leaves the process but what the scripts print.

use std::path::{Path, PathBuf};
use std::sync::Arc;

use nusage::commands::Commands;
use nusage::executor::{Executor, ProcessContext};
use nusage_plugin::nu_protocol::{PipelineData, Span, Value};
use nusage_plugin::{Args, Run};

fn fixture() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../fixtures/script-calls")
}

fn call(commands: &Commands, words: &[&str]) -> Result<Value, String> {
    let args = Args::new(
        Span::test_data(),
        words.iter().map(|word| Value::test_string(*word)).collect(),
        Vec::new(),
    );
    commands
        .call
        .run(&ProcessContext::default(), &args, PipelineData::empty())
        .map_err(|err| format!("{err:?}"))
        .and_then(|data| {
            data.into_value(Span::test_data())
                .map_err(|err| format!("{err:?}"))
        })
}

#[test]
fn a_script_calling_scripts_runs_inside_the_engine() {
    let dir = fixture();
    let script = dir.join("script.nu");
    let script = script.to_string_lossy();
    let commands = Commands::new(Arc::new(Executor::new())).unwrap();
    let value = call(&commands, &[&script, "nus", &script, "ana"]).unwrap();
    // The case's value: the callee's record through `./callee.nu`, the greeting through
    // `nus callee.nu --loud`, the times through `nu callee.nu`, and a datetime's type.
    let field = |name: &str| value.get_data_by_key(name).unwrap();
    let path = field("path");
    assert_eq!(
        path.get_data_by_key("greeting").unwrap(),
        Value::test_string("hello ana")
    );
    assert_eq!(path.get_data_by_key("times").unwrap(), Value::test_int(2));
    assert!(matches!(
        path.get_data_by_key("at").unwrap(),
        Value::Date { .. }
    ));
    assert_eq!(field("nus"), Value::test_string("HELLO ANA"));
    assert_eq!(field("nu"), Value::test_int(1));
    assert_eq!(field("at"), Value::test_string("datetime"));
    // Again: the parsed script is kept, and the value is the same.
    let again = call(&commands, &[&script, "nus", &script, "ana"]).unwrap();
    assert_eq!(again, value);
    // `--help` is the page; arguments usage rejects are an error saying why.
    let help = call(&commands, &[&script, "nus", &script, "--help"]).unwrap();
    assert!(help.coerce_string().unwrap().contains("<who>"));
    let refused = call(&commands, &[&script, "nus", &script]).unwrap_err();
    assert!(refused.contains("who"), "{refused}");
}

#[test]
fn the_path_is_a_list_as_nushell_has_it() {
    // A script adds a directory to `$env.PATH` and runs what is there, as it would in `nu`.
    let dir = std::env::temp_dir().join(format!("nusage-path-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let script = dir.join("pathed.nu");
    std::fs::write(
        &script,
        "#!/usr/bin/env nus\n#USAGE about \"Held to a path\"\n$env.PATH | describe\n",
    )
    .unwrap();
    let script = script.to_string_lossy();
    let commands = Commands::new(Arc::new(Executor::new())).unwrap();
    let value = call(&commands, &[&script, "nus", &script]).unwrap();
    std::fs::remove_dir_all(&dir).unwrap();
    assert_eq!(value, Value::test_string("list<string>"));
}

#[test]
fn the_engine_has_the_standard_library() {
    // A script's `use std/...` finds the library `nu` loads, in this engine as in `nu`.
    let dir = std::env::temp_dir().join(format!("nusage-std-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let script = dir.join("checked.nu");
    std::fs::write(
        &script,
        "#!/usr/bin/env nus\n#USAGE about \"Held to std\"\nuse std/assert\nassert equal 1 1\n\
         \"held\"\n",
    )
    .unwrap();
    let script = script.to_string_lossy();
    let commands = Commands::new(Arc::new(Executor::new())).unwrap();
    let value = call(&commands, &[&script, "nus", &script]).unwrap();
    std::fs::remove_dir_all(&dir).unwrap();
    assert_eq!(value, Value::test_string("held"));
}
