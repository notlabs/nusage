//! `nus activate nu` in a real Nushell, with a `mise` that answers as mise does for a project
//! directory, `proj`, and for anywhere else. Each step is its own evaluation in one session,
//! as each line at a prompt is: `nu --mcp` evaluates them in turn without a terminal, and the
//! hook's condition and code are run as the hook would run them. `nus modules` is the real
//! one. Without Nushell on PATH the session is skipped, except in CI, where it fails.

use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};

use serde_json::{Value, json};

/// A directory of its own for a test.
fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("nusage-activate-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

fn executable(file: &Path, text: &str) {
    std::fs::create_dir_all(file.parent().unwrap()).unwrap();
    std::fs::write(file, text).unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(file, std::fs::Permissions::from_mode(0o755)).unwrap();
    }
}

/// The Nushell on PATH: the first `nu` that is a file named `nu` once its links are followed,
/// as `nus nu` finds it, passing over a version manager's wrapper, a link to another program.
fn nushell() -> Option<PathBuf> {
    let found = std::env::split_paths(&std::env::var_os("PATH").unwrap_or_default())
        .map(|dir| dir.join("nu"))
        .find(|file| {
            std::fs::canonicalize(file)
                .is_ok_and(|real| real.is_file() && real.file_name() == Some("nu".as_ref()))
        });
    if found.is_none() {
        assert!(
            std::env::var("CI").as_deref() != Ok("true"),
            "CI runs Nushell, and nu is not on PATH"
        );
        eprintln!("skipped: nu is not on PATH");
    }
    found
}

/// A Nushell session that evaluates one step at a time.
struct Session {
    child: Child,
    stdin: ChildStdin,
    stdout: BufReader<ChildStdout>,
    id: u64,
}

impl Session {
    fn start(nu: &Path, dir: &Path, path: &str) -> Self {
        // No startup files: a machine's own, such as an autoload that puts its tools first on
        // PATH, would be in the session.
        let mut child = Command::new(nu)
            .args(["--no-config-file", "--mcp"])
            .current_dir(dir)
            .env("PATH", path)
            .env_remove("NUS_MODULES")
            .env_remove("NUS_TOOLS")
            .env_remove("MISE_ENV")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .unwrap();
        let stdin = child.stdin.take().unwrap();
        let stdout = BufReader::new(child.stdout.take().unwrap());
        let mut session = Session {
            child,
            stdin,
            stdout,
            id: 0,
        };
        session.request(
            "initialize",
            json!({"protocolVersion": "2025-06-18", "capabilities": {},
                   "clientInfo": {"name": "nusage-tests", "version": "0"}}),
        );
        session.send(json!({"jsonrpc": "2.0", "method": "notifications/initialized"}));
        session
    }

    fn send(&mut self, message: Value) {
        writeln!(self.stdin, "{message}").unwrap();
        self.stdin.flush().unwrap();
    }

    fn request(&mut self, method: &str, params: Value) -> Value {
        self.id += 1;
        let id = self.id;
        self.send(json!({"jsonrpc": "2.0", "id": id, "method": method, "params": params}));
        loop {
            let mut line = String::new();
            assert!(self.stdout.read_line(&mut line).unwrap() > 0, "nu ended");
            let message: Value = serde_json::from_str(&line).unwrap();
            if message["id"] == json!(id) {
                return message;
            }
        }
    }

    /// The value of `code`, as the session evaluates it.
    fn eval(&mut self, code: &str) -> Value {
        let reply = self.request(
            "tools/call",
            json!({"name": "evaluate", "arguments": {"input": code}}),
        );
        let result = &reply["result"];
        assert!(result["isError"] != json!(true), "{code}: {result}");
        result["structuredContent"]["output"].clone()
    }
}

impl Drop for Session {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

#[test]
#[cfg(unix)]
fn the_overlays_follow_the_directory_and_leave_what_was_set_at_the_prompt() {
    let Some(nushell) = nushell() else {
        return;
    };
    let dir = scratch("overlays");
    let module = dir.join("greet");
    std::fs::create_dir_all(&module).unwrap();
    std::fs::write(
        module.join("mod.nu"),
        "export def main [] { 'typed main' }\nexport def \"greet hello\" [] { 'typed hello' }\n",
    )
    .unwrap();
    std::fs::create_dir_all(dir.join("proj")).unwrap();
    let tools = dir.join("tools");
    // mise, as far as the activation asks it: `env --json` for the working directory, or the
    // one `-C` names, and the variables `hook-env` would hide in a shell mise started.
    executable(
        &dir.join("bin/mise"),
        &format!(
            r#"#!/bin/sh
dir=$PWD
if [ "$1" = "-C" ]; then dir=$2; shift 2; fi
case "$1 $2" in
"env --json")
  case "$dir" in
  */proj) printf '{{"FOO": "proj", "NUS_MODULES": "{{greet: %s}}", "PATH": "%s:%s"}}\n' "'{module}'" "{tools}" "$PATH" ;;
  *) printf '{{"PATH": "%s"}}\n' "$PATH" ;;
  esac ;;
"hook-env -s")
  [ -n "$__MISE_DIFF" ] && printf 'hide,INHERITED,\nset,PATH,/elsewhere\n' ;;
esac
"#,
            module = module.display(),
            tools = tools.display(),
        ),
    );
    // The nus under test is the one on PATH, as the environment's own would be.
    std::os::unix::fs::symlink(env!("CARGO_BIN_EXE_nus"), dir.join("bin/nus")).unwrap();
    let script = Command::new(env!("CARGO_BIN_EXE_nus"))
        .args(["activate", "nu"])
        .env("XDG_CACHE_HOME", dir.join("cache"))
        .output()
        .unwrap();
    assert!(script.status.success(), "{script:?}");
    std::fs::write(dir.join("activate.nu"), &script.stdout).unwrap();

    let path = format!(
        "{}:{}",
        dir.join("bin").display(),
        std::env::var("PATH").unwrap_or_default()
    );
    let mut nu = Session::start(&nushell, &dir, &path);
    let word = |path: &Path| serde_json::to_string(&path.to_string_lossy()).unwrap();
    let cache = word(&dir.join("cache/test"));
    nu.eval(&format!("source {}", word(&dir.join("activate.nu"))));

    // A shell mise started has the project's variables: they go, and what is left is the
    // shell's own environment, from which mise is asked.
    assert_eq!(
        nu.eval(
            r#"$env.__MISE_DIFF = "x"; $env.INHERITED = "from a project"; nus-revert
            [($env.INHERITED? | default gone) ($env.__MISE_DIFF? | default gone) ($env.PATH == $env.__NUS_PATH)]"#
        ),
        json!(["gone", "gone", true])
    );

    // As the hook does before a prompt: the modules for the directory, and their reload when
    // they changed.
    let prompt = |nu: &mut Session| -> bool {
        let changed = nu.eval(&format!("nus-overlays {cache}"));
        if changed == json!(true) {
            let code = nu.eval(&format!("nus-overlays-code {cache}"));
            nu.eval(code.as_str().unwrap());
        }
        changed == json!(true)
    };

    nu.eval("cd proj");
    assert!(prompt(&mut nu));
    assert_eq!(
        nu.eval("[$env.FOO $env.PATH.0 (greet hello)]"),
        json!(["proj", tools.to_string_lossy(), "typed hello"])
    );
    nu.eval(r#"$env.MINE = "kept""#);
    // An environment that has not changed is not reloaded.
    assert!(!prompt(&mut nu));

    nu.eval("cd ..");
    assert!(prompt(&mut nu));
    assert_eq!(
        nu.eval(
            r#"[($env.FOO? | default gone) ($env.PATH.0 == $env.__NUS_PATH.0) $env.MINE
            (scope commands | where name == "greet hello" | is-empty)
            (overlay list | where active | get name)]"#
        ),
        json!(["gone", true, "kept", true, ["zero", "mise", "nus"]])
    );
    std::fs::remove_dir_all(&dir).unwrap();
}

#[test]
fn only_nushell_is_activated() {
    let output = Command::new(env!("CARGO_BIN_EXE_nus"))
        .args(["activate", "bash"])
        .output()
        .unwrap();
    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("the shells are `nu`"));
}

#[test]
fn the_packages_module_exports_each_package_its_tool_allows() {
    let dir = scratch("modules");
    let package = |name: &str, version: &str| {
        let module = dir.join(name).join(name);
        std::fs::create_dir_all(&module).unwrap();
        std::fs::write(
            module.join("mod.nu"),
            format!("export def main [] {{ '{name}' }}\n"),
        )
        .unwrap();
        std::fs::write(
            dir.join(name).join("package.nuon"),
            format!(
                "{{name: {name}, version: \"0.1.0\", module: {name}, \
                 tool: {{name: {name}-tool, bin: {name}, version: \"{version}\"}}}}"
            ),
        )
        .unwrap();
        module
    };
    let same = package("same", "1.0.0");
    let other = package("other", "1.0.0");
    let output = Command::new(env!("CARGO_BIN_EXE_nus"))
        .arg("modules")
        .env(
            "NUS_MODULES",
            format!(
                "{{same: '{}', other: '{}'}}",
                same.display(),
                other.display()
            ),
        )
        .env("NUS_TOOLS", "{same-tool: '1.0.0', other-tool: '2.0.0'}")
        .output()
        .unwrap();
    assert!(output.status.success(), "{output:?}");
    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert_eq!(stdout.lines().count(), 1, "{stdout}");
    assert!(
        stdout.starts_with("export use ") && stdout.contains("same"),
        "{stdout}"
    );
    assert!(
        stderr.contains("other-tool 1.0.0") && stderr.contains("other-tool 2.0.0"),
        "{stderr}"
    );
    std::fs::remove_dir_all(&dir).unwrap();
}
