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
    // mise, as far as the activation asks it: `env --json` for the working directory, with
    // `LEVEL` from `MISE_ENV` in the project, and what it adds before the PATH it is given.
    executable(
        &dir.join("bin/mise"),
        &format!(
            r#"#!/bin/sh
dir=$PWD
if [ "$1" = "-C" ]; then dir=$2; shift 2; fi
case "$1 $2" in
"env --json")
  case "$dir" in
  */proj) printf '{{"FOO": "proj", "LEVEL": "%s", "NUS_MODULES": "{{greet: %s}}", "PATH": "%s:%s"}}\n' "${{MISE_ENV:-read}}" "'{module}'" "{tools}" "$PATH" ;;
  *) printf '{{"PATH": "%s"}}\n' "$PATH" ;;
  esac ;;
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
    // A session with no startup files is not activated as a shell at a prompt is, and the
    // `--mcp` it serves is not activated at all; its PATH is still a string, as before
    // Nushell's configuration converts it.
    nu.eval(&format!("source {}", word(&dir.join("activate.nu"))));
    assert_eq!(
        nu.eval("[($env.__NUS_PATH? | default unset) ($env.config.hooks.pre_prompt | length)]"),
        json!(["unset", 0])
    );
    nu.eval("$env.PATH = ($env.PATH | split row (char esep))");

    // A shell that starts in the project with mise's environment already set, as a wrapper or
    // an editor starts it, has it taken out: what is left is the shell's own environment.
    let module_word = format!("{{greet: '{}'}}", module.display());
    assert_eq!(
        nu.eval(&format!(
            r#"cd proj; $env.FOO = "proj"; $env.LEVEL = "read"; $env.NUS_MODULES = "{module_word}"
            $env.PATH = ($env.PATH | prepend {tools}); $env.__MISE_DIFF = "x"; $env.OWN = "mine"
            nus-revert
            [($env.FOO? | default gone) ($env.NUS_MODULES? | default gone) ($env.__MISE_DIFF? | default gone)
             ($env.PATH.0 == {tools}) ($env.PATH == $env.__NUS_PATH) $env.OWN]"#,
            tools = word(&tools),
        )),
        json!(["gone", "gone", "gone", false, true, "mine"])
    );

    // As the hook does before a prompt: what changes the overlays for the directory, and the
    // change when the environment changed.
    let prompt = |nu: &mut Session| -> bool {
        let changed = nu.eval(&format!("nus-overlays {cache}"));
        if changed == json!(true) {
            let code = nu.eval(&format!("nus-overlays-code {cache}"));
            nu.eval(code.as_str().unwrap());
        }
        changed == json!(true)
    };
    // The overlays in use, each named by what it holds, the digest left out.
    let state = r#"[($env.FOO? | default gone) ($env.LEVEL? | default none) ($env.PATH.0 == $env.__NUS_PATH.0)
        ($env.MINE? | default lost) (scope commands | where name == "greet hello" | length)
        (overlay list | where active | get name | each { str replace --regex '-[0-9a-f]{8}$' '' })]"#;

    assert!(prompt(&mut nu));
    assert_eq!(nu.eval("greet hello"), json!("typed hello"));
    assert_eq!(nu.eval("$env.PATH.0"), json!(tools.to_string_lossy()));
    assert_eq!(
        nu.eval(state),
        json!([
            "proj",
            "read",
            false,
            "lost",
            1,
            ["zero", "mise", "nus", "prompt"]
        ])
    );
    // What is set at the prompt stays; another `MISE_ENV` is another environment.
    nu.eval(r#"$env.MINE = "kept"; $env.MISE_ENV = "write""#);
    assert!(prompt(&mut nu));
    assert_eq!(
        nu.eval(state),
        json!([
            "proj",
            "write",
            false,
            "kept",
            1,
            ["zero", "mise", "nus", "prompt"]
        ])
    );
    // An environment that has not changed changes nothing.
    assert!(!prompt(&mut nu));

    // Leaving takes away all the overlays set, variables and commands, and keeps the rest.
    nu.eval("cd ..");
    assert!(prompt(&mut nu));
    assert_eq!(
        nu.eval(state),
        json!(["gone", "none", true, "kept", 0, ["zero", "mise", "prompt"]])
    );
    assert_eq!(
        nu.eval("pwd"),
        json!(dir.canonicalize().unwrap().to_string_lossy())
    );

    // An environment met again has its overlays back.
    nu.eval("cd proj");
    assert!(prompt(&mut nu));
    assert_eq!(
        nu.eval(state),
        json!([
            "proj",
            "write",
            false,
            "kept",
            1,
            ["zero", "mise", "nus", "prompt"]
        ])
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
