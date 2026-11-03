//! Structured inspection uses the analyzer's facts and never executes the script.
use std::path::Path;
use std::process::Command;

use serde_json::Value;

fn inspected(script: &Path) -> Value {
    inspected_env(script, &[])
}

fn inspected_env(script: &Path, env: &[(&str, &str)]) -> Value {
    inspected_options(script, env, false)
}

fn inspected_options(script: &Path, env: &[(&str, &str)], recursive: bool) -> Value {
    let output = Command::new(env!("CARGO_BIN_EXE_nus"))
        .arg("inspect")
        .arg(script)
        .args(recursive.then_some("--recursive"))
        .env_remove("NUS_MODULES")
        .env_remove("NUS_TOOLS")
        .envs(env.iter().copied())
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(output.stderr.is_empty());
    let value: Value = serde_json::from_slice(&output.stdout).unwrap();
    let schema =
        serde_json::from_str(include_str!("../../../schemas/inspection.schema.json")).unwrap();
    assert!(
        nushell_schema::validate::Schema::new(&schema)
            .unwrap()
            .findings(&value)
            .is_empty()
    );
    value
}

#[test]
fn resolved_calls_and_findings_are_data_without_executing() {
    let dir = std::env::temp_dir().join(format!("nusage-inspect-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let caller = dir.join("caller.nu");
    std::fs::write(
        dir.join("callee.nu"),
        "#!/usr/bin/env nus\n#USAGE arg \"<name>\"\nerror make {msg: 'must not run'}\n",
    )
    .unwrap();
    let source = "#!/usr/bin/env nus\n./callee.nu world\nrun callee.nu\n./missing.nu\n";
    std::fs::write(&caller, source).unwrap();
    let report = inspected(&caller);
    assert_eq!(report["script"], caller.to_str().unwrap());
    assert!(report["header"].is_null());
    assert!(report["module_error"].is_null());
    assert!(report.get("graph").is_none());
    assert_eq!(report["calls"].as_array().unwrap().len(), 1);
    let call = &report["calls"][0];
    assert_eq!(call["name"], "./callee.nu");
    assert_eq!(call["target"], dir.join("callee.nu").to_str().unwrap());
    assert!(
        call.get("through").is_none(),
        "calls are of one kind: {call}"
    );
    assert_eq!(call["command"]["positionals"][0]["usage_name"], "name");
    let findings = report["findings"].as_array().unwrap();
    assert_eq!(findings.len(), 2);
    for finding in findings {
        let start = finding["span"]["start"].as_u64().unwrap() as usize;
        let end = finding["span"]["end"].as_u64().unwrap() as usize;
        assert!(["callee.nu", "./missing.nu"].contains(&&source[start..end]));
    }
    std::fs::write(
        &caller,
        "#!/usr/bin/env nus\n#USAGE not-valid-kdl {\n./callee.nu world\n",
    )
    .unwrap();
    let report = inspected(&caller);
    assert!(report["header"]["message"].is_string());
    assert_eq!(report["calls"].as_array().unwrap().len(), 1);
    std::fs::remove_dir_all(dir).unwrap();
}

#[test]
fn package_errors_are_data_for_direct_and_nested_calls() {
    let dir = std::env::temp_dir().join(format!("nusage-inspect-package-{}", std::process::id()));
    let module = dir.join("greet");
    std::fs::create_dir_all(&module).unwrap();
    std::fs::write(
        module.join("mod.nu"),
        "export def greet [] { error make {msg: 'must not run'} }\n",
    )
    .unwrap();
    std::fs::write(
        dir.join("package.nuon"),
        r#"{name: greet, version: "0.1.0", module: greet, tool: {name: greeter, version: "1.2.0"}}"#,
    )
    .unwrap();
    let direct = dir.join("direct.nu");
    let caller = dir.join("caller.nu");
    std::fs::write(&direct, "#!/usr/bin/env nus\ngreet\n").unwrap();
    std::fs::write(&caller, "#!/usr/bin/env nus\n./direct.nu\n").unwrap();
    let modules = serde_json::json!({"greet": module}).to_string();
    let wrong = [
        ("NUS_MODULES", modules.as_str()),
        ("NUS_TOOLS", "{greeter: '1.3.0'}"),
    ];
    for script in [&direct, &caller] {
        let report = inspected_env(script, &wrong);
        let message = report["module_error"].as_str().unwrap();
        assert!(message.contains("greeter 1.2.0"), "{message}");
        assert!(message.contains("greeter 1.3.0"), "{message}");
        let recursive = inspected_options(script, &wrong, true);
        assert_eq!(recursive["module_error"], report["module_error"]);
        assert!(
            recursive["graph"]["nodes"]
                .as_array()
                .unwrap()
                .iter()
                .any(|node| node["path"] == script.to_str().unwrap())
        );
        let runtime = Command::new(env!("CARGO_BIN_EXE_nus"))
            .args(["prelude", "--run"])
            .arg(script)
            .envs(wrong)
            .output()
            .unwrap();
        assert!(!runtime.status.success());
        assert_eq!(
            String::from_utf8_lossy(&runtime.stderr)
                .trim()
                .strip_prefix("nus: "),
            Some(message),
        );
        let correct = [
            ("NUS_MODULES", modules.as_str()),
            ("NUS_TOOLS", "{greeter: '1.2.0'}"),
        ];
        assert!(inspected_env(script, &correct)["module_error"].is_null());
    }
    let invalid = inspected_env(&direct, &[("NUS_MODULES", "[]")]);
    assert!(
        invalid["module_error"]
            .as_str()
            .unwrap()
            .contains("NUS_MODULES is not a record")
    );
    std::fs::remove_dir_all(dir).unwrap();
}

#[test]
fn recursive_inspection_records_diamonds_cycles_imports_and_nested_findings() {
    let dir = std::env::temp_dir().join(format!("nusage-inspect-graph-{}", std::process::id()));
    let module = dir.join("greet");
    std::fs::create_dir_all(&module).unwrap();
    std::fs::write(
        module.join("mod.nu"),
        "export def greet [] { error make {msg: 'must not run'} }\n",
    )
    .unwrap();
    for (name, body) in [
        ("main.nu", "./a.nu\n./b.nu\n./a.nu\n"),
        ("a.nu", "./shared.nu\n"),
        ("b.nu", "./shared.nu\n"),
        ("shared.nu", "greet\n./a.nu\n./missing.nu\n^./ignored.nu\n"),
        ("ignored.nu", "error make {msg: 'must not run'}\n"),
    ] {
        std::fs::write(dir.join(name), format!("#!/usr/bin/env nus\n{body}")).unwrap();
    }
    let root = dir.join("main.nu");
    let modules = serde_json::json!({"greet": module}).to_string();
    let env = [("NUS_MODULES", modules.as_str())];
    let report = inspected_options(&root, &env, true);
    assert!(report["module_error"].is_null(), "{report}");
    assert_eq!(report, inspected_options(&root, &env, true));
    let graph = &report["graph"];
    assert_eq!(graph["nodes"].as_array().unwrap().len(), 5, "{graph}");
    let id = |kind: &str, path: &str| format!("{kind}:{}", dir.join(path).display());
    let expected = [
        ("main.nu", "a.nu", "calls"),
        ("main.nu", "b.nu", "calls"),
        ("a.nu", "shared.nu", "calls"),
        ("b.nu", "shared.nu", "calls"),
        ("shared.nu", "a.nu", "calls"),
        ("shared.nu", "greet", "imports"),
    ];
    let edges = graph["edges"].as_array().unwrap();
    assert_eq!(edges.len(), expected.len(), "{graph}");
    for (from, to, kind) in expected {
        let target_kind = if kind == "imports" {
            "module"
        } else {
            "script"
        };
        assert!(edges.contains(&serde_json::json!({"from": id("script", from), "to": id(target_kind, to), "kind": kind})), "{graph}");
    }
    let findings = graph["findings"].as_array().unwrap();
    assert_eq!(findings.len(), 1, "{graph}");
    assert_eq!(
        findings[0]["script"],
        dir.join("shared.nu").to_str().unwrap()
    );
    assert!(
        findings[0]["message"]
            .as_str()
            .unwrap()
            .contains("missing.nu")
    );
    std::fs::remove_dir_all(dir).unwrap();
}

#[test]
fn recursive_inspection_resolves_each_callers_relative_paths() {
    let dir = std::env::temp_dir().join(format!("nusage-inspect-relative-{}", std::process::id()));
    for side in ["left", "right"] {
        std::fs::create_dir_all(dir.join(side)).unwrap();
        std::fs::write(
            dir.join(side).join("caller.nu"),
            "#!/usr/bin/env nus\n./helper.nu\n",
        )
        .unwrap();
        std::fs::write(dir.join(side).join("helper.nu"), "#!/usr/bin/env nus\n42\n").unwrap();
    }
    let root = dir.join("main.nu");
    std::fs::write(
        &root,
        "#!/usr/bin/env nus\n./left/caller.nu\n./right/caller.nu\n",
    )
    .unwrap();
    let report = inspected_options(&root, &[], true);
    let edges = report["graph"]["edges"].as_array().unwrap();
    assert_eq!(edges.len(), 4);
    for side in ["left", "right"] {
        assert!(edges.contains(&serde_json::json!({
            "from": format!("script:{}", dir.join(side).join("caller.nu").display()),
            "to": format!("script:{}", dir.join(side).join("helper.nu").display()),
            "kind": "calls",
        })));
    }
    std::fs::remove_dir_all(dir).unwrap();
}
