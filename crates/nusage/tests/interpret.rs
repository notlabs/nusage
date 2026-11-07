//! `nus <script>` runs the script in the `nu` on PATH, as Nushell runs any script, with the definitions of the scripts it calls before it: a call returns the called script's value, typed, in the caller's own Nushell, and what the script prints, reads and exits with are Nushell's.
//! Without `nu` on PATH the runs are skipped, except in CI, where they fail.

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

/// `nus <script> <args>` in `dir`, with `input` on standard input when given, and the cache in `dir`; `None` when there is no `nu` to run it.
fn nus(dir: &Path, script: &str, args: &[&str], input: Option<&str>) -> Option<Output> {
    nus_with(dir, script, args, input, &[])
}

/// [`nus`] with these variables set, and the modules' variables unset otherwise.
fn nus_with(
    dir: &Path,
    script: &str,
    args: &[&str],
    input: Option<&str>,
    vars: &[(&str, String)],
) -> Option<Output> {
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
        .env_remove("NUS_MODULES")
        .env_remove("NUS_TOOLS")
        .envs(vars.iter().map(|(name, value)| (*name, value)))
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

/// A script's spec may mount commands, which it then runs: usage reads the arguments by the mounted spec, `$usage.cmd` names the command, and a call of it is typed by it too.
#[cfg(unix)]
#[test]
fn a_script_runs_the_commands_its_spec_mounts() {
    let dir = scripts(&[
        ("tasks.kdl", "cmd \"build\" {\n    flag \"--release\"\n}\n"),
        (
            "tool.nu",
            "#!/usr/bin/env nus\n#USAGE cmd \"run\" { mount run=\"cat tasks.kdl\" }\n#USAGE output (\"record<cmd: list<string>, release: bool>\")\"nuon\" default=#true\n{cmd: $usage.cmd, release: ($usage.flags.release? | default false)}\n",
        ),
        (
            "caller.nu",
            "#!/usr/bin/env nus\n(./tool.nu run build --release) | to nuon\n",
        ),
        (
            "misspelt.nu",
            "#!/usr/bin/env nus\n./tool.nu run build --fast\n",
        ),
    ]);
    let Some(direct) = nus(&dir, "tool.nu", &["run", "build", "--release"], None) else {
        return;
    };
    assert!(direct.status.success(), "{direct:?}");
    assert!(stdout(&direct).contains("release"), "{direct:?}");
    let refused = nus(&dir, "tool.nu", &["run", "build", "--fast"], None).unwrap();
    assert_eq!(refused.status.code(), Some(2), "{refused:?}");
    let called = nus(&dir, "caller.nu", &[], None).unwrap();
    assert!(called.status.success(), "{called:?}");
    assert_eq!(stdout(&called), "{cmd: [run, build], release: true}");
    let misspelt = nus(&dir, "misspelt.nu", &[], None).unwrap();
    assert!(!misspelt.status.success(), "{misspelt:?}");
    assert!(
        String::from_utf8_lossy(&misspelt.stderr).contains("fast"),
        "{misspelt:?}"
    );
    std::fs::remove_dir_all(dir).unwrap();
}

/// A script gets a module by calling it: a call nothing defines whose word `NUS_MODULES` names is the module's, imported by its absolute path.
/// The project's version of the tool the package wraps must be the one it was generated from.
#[test]
fn a_call_gets_the_module_its_word_names() {
    let package = scripts(&[
        (
            "greet/mod.nu",
            "export def \"greet hello\" [who: string]: nothing -> string { $\"hello ($who)\" }\n",
        ),
        (
            "package.nuon",
            "{name: greet, version: \"0.1.0\", module: greet, tool: {name: greeter, bin: greet, version: \"1.2.0\"}}\n",
        ),
    ]);
    let dir = scripts(&[(
        "calls.nu",
        "#!/usr/bin/env nus\ngreet hello ana | str upcase\n",
    )]);
    let modules = (
        "NUS_MODULES",
        format!("{{greet: '{}'}}", package.join("greet").display()),
    );
    let tools = |version: &str| ("NUS_TOOLS", format!("{{greeter: '{version}'}}"));
    let Some(called) = nus_with(
        &dir,
        "calls.nu",
        &[],
        None,
        &[modules.clone(), tools("1.2.0")],
    ) else {
        return;
    };
    assert!(called.status.success(), "{called:?}");
    assert_eq!(stdout(&called), "HELLO ANA");
    let without = nus(&dir, "calls.nu", &[], None).unwrap();
    assert!(!without.status.success(), "{without:?}");
    let other = nus_with(&dir, "calls.nu", &[], None, &[modules, tools("1.3.0")]).unwrap();
    assert!(!other.status.success(), "{other:?}");
    let said = String::from_utf8_lossy(&other.stderr);
    assert!(
        said.contains("greeter 1.2.0") && said.contains("greeter 1.3.0"),
        "{said}"
    );
    std::fs::remove_dir_all(dir).unwrap();
    std::fs::remove_dir_all(package).unwrap();
}

fn number_package(version: &str) -> (PathBuf, [(&'static str, String); 2]) {
    let package = scripts(&[
        (
            "greet/mod.nu",
            "export def \"greet twice\" [n: int]: nothing -> int { $n * 2 }\n",
        ),
        (
            "package.nuon",
            "{name: greet, version: '0.1.0', module: greet, tool: {name: greeter, bin: greet, version: '1.2.0'}}\n",
        ),
    ]);
    let vars = [
        (
            "NUS_MODULES",
            format!("{{greet: '{}'}}", package.join("greet").display()),
        ),
        ("NUS_TOOLS", format!("{{greeter: '{version}'}}")),
    ];
    (package, vars)
}

#[test]
fn nested_calls_get_modules_in_their_own_scope() {
    let (package, vars) = number_package("1.2.0");
    let dir = scripts(&[
        ("leaf.nu", "#!/usr/bin/env nus\ngreet twice 3\n"),
        ("middle.nu", "#!/usr/bin/env nus\n./leaf.nu\n"),
        (
            "caller.nu",
            "#!/usr/bin/env nus\ndef 'greet twice' [n: int] { $n + 100 }\n[(greet twice 1) (./middle.nu) (greet twice 2)] | to nuon\n",
        ),
    ]);
    let Some(direct) = nus_with(&dir, "leaf.nu", &[], None, &vars) else {
        return;
    };
    assert!(direct.status.success(), "{direct:?}");
    assert_eq!(stdout(&direct), "6");
    let nested = nus_with(&dir, "caller.nu", &[], None, &vars).unwrap();
    assert!(nested.status.success(), "{nested:?}");
    assert_eq!(stdout(&nested), "[101, 6, 102]");
    std::fs::remove_dir_all(dir).unwrap();
    std::fs::remove_dir_all(package).unwrap();
}

#[test]
fn nested_module_mismatches_stop_before_execution() {
    let (package, vars) = number_package("1.3.0");
    let dir = scripts(&[
        ("leaf.nu", "#!/usr/bin/env nus\ngreet twice 3\n"),
        ("middle.nu", "#!/usr/bin/env nus\n./leaf.nu\n"),
        (
            "caller.nu",
            "#!/usr/bin/env nus\n'ran' | save ran.txt\n./middle.nu\n",
        ),
    ]);
    let Some(output) = nus_with(&dir, "caller.nu", &[], None, &vars) else {
        return;
    };
    assert!(!output.status.success(), "{output:?}");
    let said = String::from_utf8_lossy(&output.stderr);
    for expected in ["leaf.nu", "greeter 1.2.0", "greeter 1.3.0"] {
        assert!(said.contains(expected), "{said}");
    }
    assert!(!dir.join("ran.txt").exists(), "the caller must not start");
    std::fs::remove_dir_all(dir).unwrap();
    std::fs::remove_dir_all(package).unwrap();
}

#[test]
fn mutual_calls_keep_their_modules() {
    let (package, vars) = number_package("1.2.0");
    let header =
        "#!/usr/bin/env nus\n#USAGE arg (int)\"<n>\"\n#USAGE output (int)\"nuon\" default=#true\n";
    let dir = scripts(&[
        (
            "a.nu",
            &format!(
                "{header}if $usage.args.n > 0 {{ ./b.nu ($usage.args.n - 1) }} else {{ greet twice 3 }}\n"
            ),
        ),
        (
            "b.nu",
            &format!(
                "{header}if $usage.args.n > 0 {{ ./a.nu ($usage.args.n - 1) }} else {{ greet twice 4 }}\n"
            ),
        ),
        ("caller.nu", "#!/usr/bin/env nus\n./a.nu 3\n"),
    ]);
    let Some(output) = nus_with(&dir, "caller.nu", &[], None, &vars) else {
        return;
    };
    assert!(output.status.success(), "{output:?}");
    assert_eq!(stdout(&output), "8");
    std::fs::remove_dir_all(dir).unwrap();
    std::fs::remove_dir_all(package).unwrap();
}

#[test]
fn nested_local_commands_and_explicit_externals_do_not_import_packages() {
    // A package of the wrong version must not stop a script that does not use it.
    let (package, vars) = number_package("1.3.0");
    let dir = scripts(&[
        (
            "leaf.nu",
            "#!/usr/bin/env nus\ndef 'greet twice' [n: int] { $n + 1 }\nif false { ^greet twice 2 }\ngreet twice 2\n",
        ),
        ("caller.nu", "#!/usr/bin/env nus\n./leaf.nu\n"),
    ]);
    let Some(output) = nus_with(&dir, "caller.nu", &[], None, &vars) else {
        return;
    };
    assert!(output.status.success(), "{output:?}");
    assert_eq!(stdout(&output), "3");
    std::fs::remove_dir_all(dir).unwrap();
    std::fs::remove_dir_all(package).unwrap();
}
