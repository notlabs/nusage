//! `nus <script>` runs the script in the `nu` on PATH, as Nushell runs any script, with the
//! definitions of the scripts it calls before it: a call returns the called script's value,
//! typed, in the caller's own Nushell, and what the script prints, reads and exits with are
//! Nushell's. Without `nu` on PATH the runs are skipped, except in CI, where they fail.

use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};

/// A directory of its own for a test's scripts, each made executable.
fn scripts(files: &[(&str, &str)]) -> PathBuf {
    use std::sync::atomic::{AtomicUsize, Ordering};
    static NEXT: AtomicUsize = AtomicUsize::new(0);
    let dir = std::env::temp_dir().join(format!(
        "nusage-interpret-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ));
    std::fs::create_dir_all(&dir).unwrap();
    for (name, text) in files {
        let file = dir.join(name);
        std::fs::create_dir_all(file.parent().unwrap()).unwrap();
        std::fs::write(&file, text).unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(&file, std::fs::Permissions::from_mode(0o755)).unwrap();
        }
    }
    dir
}

/// `nus <script> <args>` in `dir`, with `input` on standard input when given, and the cache
/// in `dir`; `None` when there is no `nu` to run it.
fn nus(dir: &Path, script: &str, args: &[&str], input: Option<&str>) -> Option<Output> {
    if Command::new("nu").arg("--version").output().is_err() {
        assert!(
            std::env::var("CI").as_deref() != Ok("true"),
            "CI runs scripts in nu, and nu is not on PATH"
        );
        eprintln!("skipped: nu is not on PATH");
        return None;
    }
    let cache = dir.join(".cache");
    let mut command = Command::new(env!("CARGO_BIN_EXE_nus"));
    command
        .arg(dir.join(script))
        .args(args)
        .current_dir(dir)
        .env("XDG_CACHE_HOME", &cache)
        .env("LOCALAPPDATA", &cache)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    let output = match input {
        Some(text) => {
            command.stdin(Stdio::piped());
            let mut child = command.spawn().unwrap();
            child
                .stdin
                .take()
                .unwrap()
                .write_all(text.as_bytes())
                .unwrap();
            child.wait_with_output().unwrap()
        }
        None => command.stdin(Stdio::null()).output().unwrap(),
    };
    Some(output)
}

fn stdout(output: &Output) -> String {
    String::from_utf8_lossy(&output.stdout).trim().to_string()
}

const CALLEE: &str = r#"#!/usr/bin/env nus
#USAGE arg "<name>"
#USAGE flag "--times" default="2" { arg (int)"<n>" }
#USAGE output ("record<greeting: string, times: int>")"nuon" default=#true
print $"callee: ($usage.args.name)"
{greeting: $"hello ($usage.args.name)", times: $usage.flags.times}
"#;

#[test]
fn a_call_returns_the_called_scripts_value_typed() {
    let dir = scripts(&[
        ("callee.nu", CALLEE),
        (
            "caller.nu",
            "#!/usr/bin/env nus\nlet got = ./callee.nu ana\n[($got | describe) $got.times] | to nuon\n",
        ),
    ]);
    let Some(output) = nus(&dir, "caller.nu", &[], None) else {
        return;
    };
    assert!(output.status.success(), "{output:?}");
    // What the callee prints passes through, before the caller's value.
    assert_eq!(
        stdout(&output),
        "callee: ana\n[\"record<greeting: string, times: int>\", 2]"
    );
    std::fs::remove_dir_all(dir).unwrap();
}

#[test]
fn a_script_runs_as_nushell_runs_one() {
    let dir = scripts(&[(
        "here.nu",
        "#!/usr/bin/env nus\n#USAGE arg \"<code>\"\nconst self = path self\nif $usage.args.code != \"0\" { exit ($usage.args.code | into int) }\n[($env.CURRENT_FILE | path basename) ($env.FILE_PWD == ($self | path dirname)) ($in | default '' | str length)] | to nuon\n",
    )]);
    let Some(output) = nus(&dir, "here.nu", &["0"], Some("piped")) else {
        return;
    };
    assert!(output.status.success(), "{output:?}");
    assert_eq!(stdout(&output), "[\"here.nu\", true, 5]");
    let exited = nus(&dir, "here.nu", &["3"], None).unwrap();
    assert_eq!(exited.status.code(), Some(3), "{exited:?}");
    let help = nus(&dir, "here.nu", &["--help"], None).unwrap();
    assert_eq!(help.status.code(), Some(0), "{help:?}");
    let rejected = nus(&dir, "here.nu", &[], None).unwrap();
    assert_eq!(rejected.status.code(), Some(2), "{rejected:?}");
    std::fs::remove_dir_all(dir).unwrap();
}

#[test]
fn calls_may_go_round() {
    let dir = scripts(&[(
        "count.nu",
        "#!/usr/bin/env nus\n#USAGE arg (int)\"<n>\"\n#USAGE output (\"list<int>\")\"nuon\" default=#true\nif $usage.args.n > 0 { [$usage.args.n] ++ (./count.nu ($usage.args.n - 1)) } else { [0] }\n",
    )]);
    let caller = "#!/usr/bin/env nus\n./count.nu 3 | to nuon\n";
    std::fs::write(dir.join("caller.nu"), caller).unwrap();
    let Some(output) = nus(&dir, "caller.nu", &[], None) else {
        return;
    };
    assert!(output.status.success(), "{output:?}");
    assert_eq!(stdout(&output), "[3, 2, 1, 0]");
    std::fs::remove_dir_all(dir).unwrap();
}

#[test]
fn definitions_are_kept_once_for_their_contents() {
    let dir = scripts(&[
        ("callee.nu", CALLEE),
        ("caller.nu", "#!/usr/bin/env nus\n(./callee.nu ana).times\n"),
    ]);
    let Some(first) = nus(&dir, "caller.nu", &[], None) else {
        return;
    };
    assert!(first.status.success(), "{first:?}");
    let second = nus(&dir, "caller.nu", &[], None).unwrap();
    assert_eq!(stdout(&first), stdout(&second));
    let kept: Vec<_> = std::fs::read_dir(dir.join(".cache/nusage/definitions"))
        .unwrap()
        .flatten()
        .map(|entry| entry.file_name().to_string_lossy().into_owned())
        .collect();
    assert_eq!(kept.len(), 1, "{kept:?}");
    assert!(kept[0].ends_with(".nu"), "{kept:?}");
    std::fs::remove_dir_all(dir).unwrap();
}

/// A program that echoes the arguments it was given, and prints a spec of its tasks when
/// asked for them, as a task runner's `--usage` does.
const TOOL: &str = "#!/bin/sh\nif [ \"$1\" = --tasks ]; then printf 'cmd \"build\" {\\n    flag \"--release\"\\n}\\n'; exit; fi\necho \"$@\"\n";

/// The program's spec beside it, its tasks mounted from what it prints.
const TOOL_SPEC: &str = "name \"tool\"\nbin \"tool\"\ncmd \"greet\" {\n    flag \"--name <name>\"\n    flag \"--loud\"\n}\ncmd \"run\" {\n    mount run=\"./tool --tasks\"\n}\n";

#[cfg(unix)]
#[test]
fn a_program_with_a_spec_beside_it_is_called_by_its_commands() {
    let dir = scripts(&[
        ("tool", TOOL),
        (".tool.usage.kdl", TOOL_SPEC),
        (
            "caller.nu",
            "#!/usr/bin/env nus\n./tool greet --name ana --loud\n./tool run build --release\n",
        ),
        (
            "misspelt.nu",
            "#!/usr/bin/env nus\n./tool greet --nme ana\n",
        ),
        (
            "untasked.nu",
            "#!/usr/bin/env nus\n./tool run build --fast\n",
        ),
    ]);
    let Some(output) = nus(&dir, "caller.nu", &[], None) else {
        return;
    };
    assert!(output.status.success(), "{output:?}");
    assert_eq!(
        stdout(&output),
        "greet --name ana --loud\nrun build --release"
    );
    // The spec's flags, and a mounted task's, are the only ones Nushell takes.
    for (script, word) in [("misspelt.nu", "nme"), ("untasked.nu", "fast")] {
        let refused = nus(&dir, script, &[], None).unwrap();
        assert!(!refused.status.success(), "{refused:?}");
        let stderr = String::from_utf8_lossy(&refused.stderr);
        assert!(stderr.contains(word), "{stderr}");
    }
    std::fs::remove_dir_all(dir).unwrap();
}

/// A program found on PATH by its name, and a script nusage runs found there, are typed as
/// a path to them is.
#[cfg(unix)]
#[test]
fn a_command_on_path_is_typed_by_its_spec() {
    let dir = scripts(&[
        ("bin/tool", TOOL),
        ("bin/.tool.usage.kdl", TOOL_SPEC),
        ("bin/callee", CALLEE),
        (
            "caller.nu",
            "#!/usr/bin/env nus\nlet got = callee ana\nprint $got.times\ntool greet --name ana\n",
        ),
    ]);
    let path = std::env::join_paths(
        std::iter::once(dir.join("bin")).chain(std::env::split_paths(
            &std::env::var_os("PATH").unwrap_or_default(),
        )),
    )
    .unwrap();
    let Some(output) = nus_with(&dir, "caller.nu", &[("PATH", path.as_os_str())]) else {
        return;
    };
    assert!(output.status.success(), "{output:?}");
    assert_eq!(stdout(&output), "callee: ana\n2\ngreet --name ana");
    std::fs::remove_dir_all(dir).unwrap();
}

/// [`nus`] with no input and these variables set.
fn nus_with(dir: &Path, script: &str, env: &[(&str, &std::ffi::OsStr)]) -> Option<Output> {
    Command::new("nu").arg("--version").output().ok()?;
    let cache = dir.join(".cache");
    let mut command = Command::new(env!("CARGO_BIN_EXE_nus"));
    command
        .arg(dir.join(script))
        .current_dir(dir)
        .env("XDG_CACHE_HOME", &cache)
        .env("LOCALAPPDATA", &cache)
        .stdin(Stdio::null());
    for (name, value) in env {
        command.env(name, value);
    }
    Some(command.output().unwrap())
}
