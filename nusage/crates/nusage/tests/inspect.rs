//! Structured inspection uses the analyzer's facts and never executes the script.
use std::path::Path;
use std::process::Command;

use serde_json::Value;

fn inspected(script: &Path) -> Value {
    let output = Command::new(env!("CARGO_BIN_EXE_nus"))
        .arg("inspect")
        .arg(script)
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
    assert_eq!(report["calls"].as_array().unwrap().len(), 1);
    let call = &report["calls"][0];
    assert_eq!(call["name"], "./callee.nu");
    assert_eq!(call["target"], dir.join("callee.nu").to_str().unwrap());
    assert_eq!(call["through"]["kind"], "nus");
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
