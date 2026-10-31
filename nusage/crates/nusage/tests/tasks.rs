//! A script that runs a task of mise's whose file is a script nusage runs calls it as it
//! calls that script: typed, the value back, mise running the task with what it runs around
//! it. A project of file tasks is made for each test, outside any other; without mise on
//! PATH the tests are skipped, except in CI, where they fail.

use std::path::{Path, PathBuf};
use std::process::Command;

use nu_protocol::engine::StateWorkingSet;
use nu_protocol::{Span, Value};

fn callee() -> String {
    std::fs::read_to_string(
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../../fixtures/script-calls/callee.nu"),
    )
    .unwrap()
}

/// A project of mise's with its tasks, and a script that calls them, as the test names it;
/// `None` when there is no mise to ask.
fn project(test: &str, caller: &str) -> Option<PathBuf> {
    if Command::new("mise").arg("--version").output().is_err() {
        assert!(
            std::env::var("CI").as_deref() != Ok("true"),
            "CI runs mise's tasks, and mise is not on PATH"
        );
        eprintln!("skipped: mise is not on PATH");
        return None;
    }
    let dir = std::env::temp_dir().join(format!("nusage-tasks-{test}-{}", std::process::id()));
    let tasks = dir.join("mise-tasks");
    std::fs::create_dir_all(&tasks).unwrap();
    // A task around it, before and after, is a script nusage runs too, with a value of its
    // own that is not the one asked for.
    let greet = callee().replacen(
        "\n",
        "\n#MISE depends=[\"before\"]\n#MISE depends_post=[\"after\"]\n",
        1,
    );
    let around = |word: &str| {
        format!(
            "#!/usr/bin/env nus\n#USAGE output (\"string\")\"nuon\" default=#true\n\"{word}\"\n"
        )
    };
    for (name, text) in [
        ("greet", greet),
        ("before", around("before")),
        ("after", around("after")),
        ("plain", "#!/bin/sh\necho plain\n".to_string()),
    ] {
        let file = tasks.join(name);
        std::fs::write(&file, text).unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(&file, std::fs::Permissions::from_mode(0o755)).unwrap();
        }
    }
    std::fs::write(dir.join("caller.nu"), caller).unwrap();
    Some(dir)
}

/// The script with the prelude in place of its first line, as Nushell's parser reads it.
fn parse_errors(script: &Path) -> Vec<String> {
    let (line, _) = nusage::prelude(script).expect("a prelude");
    let source = std::fs::read_to_string(script).unwrap();
    let analysis = format!("{line}\n{}", source.split_once('\n').unwrap().1);
    let mut engine_state =
        nu_command::add_shell_command_context(nu_cmd_lang::create_default_context());
    engine_state.add_env_var(
        "PWD".into(),
        Value::string(script.parent().unwrap().to_string_lossy(), Span::unknown()),
    );
    let mut working_set = StateWorkingSet::new(&engine_state);
    nu_parser::parse(
        &mut working_set,
        Some(&script.to_string_lossy()),
        analysis.as_bytes(),
        false,
    );
    working_set
        .parse_errors
        .iter()
        .map(|err| err.to_string())
        .collect()
}

#[test]
fn a_task_is_called_as_its_script_with_the_value_its_own() {
    let caller = r#"#!/usr/bin/env nus
#USAGE arg "<who>"
#USAGE output ("record<times: int, at: string, loud: string>")"nuon" default=#true
{
    times: (mise run greet $usage.args.who --times 2).times
    at: (mise r greet $usage.args.who | get at | describe)
    loud: (mise run greet $usage.args.who --loud).greeting
}
"#;
    let Some(dir) = project("value", caller) else {
        return;
    };
    if Command::new("nu").arg("--version").output().is_err() {
        assert!(
            std::env::var("CI").as_deref() != Ok("true"),
            "nu is not on PATH"
        );
        return;
    }
    // The tasks' shebangs find the nus built here, and the interpreter the `nu` on PATH,
    // from a directory of the project's own: mise takes its installs off PATH for a project
    // that pins no `nu`. mise reads no configuration of the user's.
    let nusage = PathBuf::from(env!("CARGO_BIN_EXE_nus"));
    let path = std::env::var_os("PATH").unwrap_or_default();
    let nu = std::env::split_paths(&path)
        .map(|dir| dir.join(format!("nu{}", std::env::consts::EXE_SUFFIX)))
        .filter_map(|candidate| std::fs::canonicalize(candidate).ok())
        .find(|target| target.is_file() && target.file_stem().is_some_and(|stem| stem == "nu"))
        .expect("nu on PATH");
    let bin = dir.join("bin");
    std::fs::create_dir_all(&bin).unwrap();
    for program in [&nusage, &nu] {
        let link = bin.join(program.file_name().unwrap());
        #[cfg(unix)]
        std::os::unix::fs::symlink(program, link).unwrap();
        #[cfg(not(unix))]
        std::fs::copy(program, link).unwrap();
    }
    let dirs = std::iter::once(bin).chain(std::env::split_paths(&path));
    let value = dir.join("value.nuon");
    let output = Command::new(&nusage)
        .arg(dir.join("caller.nu"))
        .arg("ana")
        .current_dir(std::env::temp_dir())
        .env("PATH", std::env::join_paths(dirs).unwrap())
        .env("MISE_CONFIG_DIR", dir.join("no-config"))
        .env("NUS_OUTPUT_FILE", &value)
        .output()
        .unwrap();
    let written = std::fs::read_to_string(&value);
    std::fs::remove_dir_all(&dir).unwrap();
    assert!(output.status.success(), "{output:?}");
    assert_eq!(
        written.unwrap(),
        r#"{times: 2, at: datetime, loud: "HELLO ANA"}"#
    );
}

#[test]
fn a_call_of_a_task_is_held_to_its_scripts_header() {
    let caller = "#!/usr/bin/env nus\nmise run greet --times two --bogus\nmise run plain 1 2\n";
    let Some(dir) = project("checked", caller) else {
        return;
    };
    let errors = parse_errors(&dir.join("caller.nu"));
    let (line, findings) = nusage::prelude(&dir.join("caller.nu")).unwrap();
    let inspection = nusage::inspect(&dir.join("caller.nu")).unwrap();
    let call = inspection["calls"]
        .as_array()
        .unwrap()
        .iter()
        .find(|call| call["name"] == "mise run greet")
        .unwrap();
    assert_eq!(call["through"]["kind"], "mise");
    assert_eq!(call["through"]["task"], "greet");
    assert_eq!(call["through"]["dir"], dir.to_str().unwrap());
    assert_eq!(
        Path::new(call["target"].as_str().unwrap())
            .canonicalize()
            .unwrap(),
        dir.join("mise-tasks/greet").canonicalize().unwrap()
    );
    std::fs::remove_dir_all(&dir).unwrap();
    for expected in [
        "expected int",
        "doesn't have flag `bogus`",
        "missing required positional",
    ] {
        assert!(
            errors
                .iter()
                .any(|err| err.to_lowercase().contains(&expected.to_lowercase())),
            "no error saying {expected:?} in {errors:#?}"
        );
    }
    // A task whose file nusage does not run is mise's external, as it was.
    assert!(line.contains(r#"def "mise run greet""#), "{line}");
    assert!(!line.contains("mise run plain"), "{line}");
    assert_eq!(findings, Vec::<String>::new());
}

#[test]
fn a_task_mise_does_not_know_is_said() {
    let caller = "#!/usr/bin/env nus\nmise run nope\n^mise run nope\nmise run --quiet nope\n";
    let Some(dir) = project("unknown", caller) else {
        return;
    };
    let found = nusage::prelude(&dir.join("caller.nu"));
    std::fs::remove_dir_all(&dir).unwrap();
    let (_, findings) = found.unwrap();
    assert_eq!(findings.len(), 1, "{findings:#?}");
    assert!(
        findings[0].contains(":2:10: mise: Task not found: nope"),
        "{findings:#?}"
    );
}
