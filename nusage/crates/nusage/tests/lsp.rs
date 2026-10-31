//! `nus lsp` in front of the pinned `nu --lsp`: requests are sent together, then answers
//! are read through the shutdown acknowledgment before exit, draining all complete frames.
//! Without `nu` on PATH the session is skipped, except in CI, where it fails.

use std::io::{self, BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::mpsc;
use std::time::{Duration, Instant};

use serde_json::{Value as Json, json};

fn caller() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../fixtures/script-calls/script.nu")
        .canonicalize()
        .unwrap()
}

fn uri(path: &Path) -> String {
    format!("file://{}", path.display())
}

/// Where a word first stands in the text, as a position, a few characters into it.
fn at(text: &str, word: &str, into: usize) -> Json {
    let (line, found) = text
        .lines()
        .enumerate()
        .find(|(_, line)| line.contains(word))
        .expect("the word is in the text");
    json!({"line": line, "character": found.find(word).unwrap() + into})
}

/// The answers to a session: each request's result by id, and the diagnostics last published
/// for the document. `None` when there is no `nu` to run it with.
fn session(
    open: &str,
    change: Option<&str>,
    requests: &[(&str, Json)],
) -> Option<(Vec<Json>, Vec<Json>)> {
    session_with(&["lsp"], &[], open, change, requests)
}

/// [`session`], with the server started as `nus` and these arguments, in this
/// environment.
fn session_with(
    server: &[&str],
    vars: &[(&str, String)],
    open: &str,
    change: Option<&str>,
    requests: &[(&str, Json)],
) -> Option<(Vec<Json>, Vec<Json>)> {
    if Command::new("nu").arg("--version").output().is_err() {
        assert!(
            std::env::var("CI").as_deref() != Ok("true"),
            "CI runs the language server against nu, and nu is not on PATH"
        );
        eprintln!("skipped: nu is not on PATH");
        return None;
    }
    Some(
        exchange_session(
            server,
            vars,
            open,
            change,
            requests,
            Duration::from_secs(30),
        )
        .expect("a complete LSP session"),
    )
}

fn exchange_session(
    server: &[&str],
    vars: &[(&str, String)],
    open: &str,
    change: Option<&str>,
    requests: &[(&str, Json)],
    timeout: Duration,
) -> io::Result<(Vec<Json>, Vec<Json>)> {
    let script = caller();
    let document = uri(&script);
    let mut messages = vec![
        json!({"jsonrpc": "2.0", "id": 0, "method": "initialize", "params": {"processId": null, "rootUri": null, "capabilities": {}}}),
        json!({"jsonrpc": "2.0", "method": "initialized", "params": {}}),
        json!({"jsonrpc": "2.0", "method": "textDocument/didOpen", "params": {"textDocument": {"uri": document, "languageId": "nushell", "version": 1, "text": open}}}),
    ];
    for (id, (method, params)) in requests.iter().enumerate() {
        let mut params = params.clone();
        params["textDocument"] = json!({"uri": document});
        messages.push(json!({"jsonrpc": "2.0", "id": id + 1, "method": method, "params": params}));
    }
    if let Some(text) = change {
        messages.push(json!({"jsonrpc": "2.0", "method": "textDocument/didChange", "params": {"textDocument": {"uri": document, "version": 2}, "contentChanges": [{"text": text}]}}));
    }
    messages.push(json!({"jsonrpc": "2.0", "id": 999, "method": "shutdown"}));
    let mut input = Vec::new();
    for message in &messages {
        let body = serde_json::to_vec(message).unwrap();
        write!(input, "Content-Length: {}\r\n\r\n", body.len()).unwrap();
        input.extend(body);
    }

    // Nushell's own files go to a home of the session's; sessions run side by side.
    static SESSIONS: AtomicUsize = AtomicUsize::new(0);
    let home = std::env::temp_dir().join(format!(
        "nus-lsp-{}-{}",
        std::process::id(),
        SESSIONS.fetch_add(1, Ordering::Relaxed)
    ));
    std::fs::create_dir_all(&home).unwrap();
    let mut server = Command::new(env!("CARGO_BIN_EXE_nus"))
        .args(server)
        .envs(vars.iter().map(|(name, value)| (*name, value)))
        .env("HOME", &home)
        .env("XDG_CONFIG_HOME", home.join(".config"))
        .env("XDG_DATA_HOME", home.join(".local/share"))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let mut stdin = Some(server.stdin.take().unwrap());
    let stdout = server.stdout.take().unwrap();
    let (sent, received) = mpsc::channel();
    let reader = std::thread::spawn(move || {
        let mut stdout = BufReader::new(stdout);
        loop {
            let message = response(&mut stdout);
            let ended = !matches!(message, Ok(Some(_)));
            if sent.send(message).is_err() || ended {
                break;
            }
        }
    });
    let deadline = Instant::now() + timeout;
    let session = (|| -> io::Result<_> {
        stdin.as_mut().unwrap().write_all(&input)?;
        let mut results = vec![Json::Null; requests.len()];
        let mut diagnostics = Vec::new();
        let mut shutdown = false;
        loop {
            let body = received
                .recv_timeout(deadline.saturating_duration_since(Instant::now()))
                .map_err(|err| match err {
                    mpsc::RecvTimeoutError::Timeout => {
                        io::Error::new(io::ErrorKind::TimedOut, "LSP response deadline exceeded")
                    }
                    mpsc::RecvTimeoutError::Disconnected => {
                        io::Error::new(io::ErrorKind::UnexpectedEof, "LSP response reader stopped")
                    }
                })??;
            let Some(body) = body else {
                if shutdown {
                    break;
                }
                return Err(io::Error::new(
                    io::ErrorKind::UnexpectedEof,
                    "no shutdown response",
                ));
            };
            if body["id"] == 999 {
                if body.get("result") != Some(&Json::Null) {
                    return Err(io::Error::other(format!("shutdown failed: {body}")));
                }
                // Only the complete acknowledgment permits exit; Nu may otherwise stop
                // before its output thread has finished writing earlier responses.
                let exit = br#"{"jsonrpc":"2.0","method":"exit"}"#;
                let mut input = stdin.take().unwrap();
                write!(input, "Content-Length: {}\r\n\r\n", exit.len())?;
                input.write_all(exit)?;
                shutdown = true;
            } else if body["method"] == "textDocument/publishDiagnostics"
                && body["params"]["uri"] == document
            {
                diagnostics = body["params"]["diagnostics"]
                    .as_array()
                    .ok_or_else(|| io::Error::other("diagnostics are not an array"))?
                    .clone();
            } else if let Some(id) = body["id"].as_u64()
                && (1..=requests.len() as u64).contains(&id)
            {
                results[id as usize - 1] = body["result"].clone();
            }
        }
        Ok((results, diagnostics))
    })();
    // EOF lets nusage clean up its own Nu child. Bound that grace period too, then reap.
    drop(stdin);
    let deadline = Instant::now() + Duration::from_secs(2);
    let status = loop {
        if let Some(status) = server.try_wait()? {
            break status;
        }
        if Instant::now() >= deadline {
            server.kill()?;
            break server.wait()?;
        }
        std::thread::sleep(Duration::from_millis(10));
    };
    reader.join().expect("the response reader");
    std::fs::remove_dir_all(&home)?;
    let result = session?;
    if !status.success() {
        return Err(io::Error::other(format!("LSP server exited: {status}")));
    }
    Ok(result)
}

/// A complete LSP frame; EOF is valid only between frames.
fn response(stdout: &mut impl BufRead) -> io::Result<Option<Json>> {
    let mut header = String::new();
    if stdout.read_line(&mut header)? == 0 {
        return Ok(None);
    }
    let mut length = None;
    while header != "\r\n" {
        if let Some(value) = header.strip_prefix("Content-Length:") {
            length = Some(value.trim().parse::<usize>().map_err(io::Error::other)?);
        }
        header.clear();
        if stdout.read_line(&mut header)? == 0 {
            return Err(io::Error::new(
                io::ErrorKind::UnexpectedEof,
                "incomplete LSP header",
            ));
        }
    }
    let length = length.ok_or_else(|| io::Error::other("no Content-Length"))?;
    let mut bytes = vec![0; length];
    stdout.read_exact(&mut bytes)?;
    serde_json::from_slice(&bytes)
        .map(Some)
        .map_err(io::Error::other)
}

fn said(diagnostics: &[Json]) -> Vec<(u64, String)> {
    diagnostics
        .iter()
        .map(|diagnostic| {
            (
                diagnostic["range"]["start"]["line"].as_u64().unwrap(),
                diagnostic["message"].as_str().unwrap().to_string(),
            )
        })
        .collect()
}

#[cfg(unix)]
#[test]
fn a_server_that_exits_early_or_never_answers_cannot_stall_the_session() {
    use std::os::unix::fs::PermissionsExt;

    let dir = std::env::temp_dir().join(format!("nus-lsp-unresponsive-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let nu = dir.join("nu");
    let vars = [("PATH", dir.to_string_lossy().into_owned())];
    for script in [
        "#!/bin/sh\nexit 9\n",
        "#!/bin/sh\nexec /bin/cat > /dev/null\n",
    ] {
        std::fs::write(&nu, script).unwrap();
        std::fs::set_permissions(&nu, std::fs::Permissions::from_mode(0o755)).unwrap();
        let started = Instant::now();
        let error = exchange_session(
            &["lsp"],
            &vars,
            "let a = 1\n",
            None,
            &[],
            Duration::from_millis(250),
        )
        .unwrap_err();
        assert!(
            matches!(
                error.kind(),
                io::ErrorKind::TimedOut | io::ErrorKind::UnexpectedEof | io::ErrorKind::BrokenPipe
            ),
            "{error}"
        );
        assert!(started.elapsed() < Duration::from_secs(5), "{error}");
        if script.contains("cat") {
            assert_eq!(error.kind(), io::ErrorKind::TimedOut);
        }
    }
    std::fs::remove_dir_all(dir).unwrap();
}

#[test]
fn a_script_is_checked_as_nusage_runs_it() {
    let text = std::fs::read_to_string(caller()).unwrap();
    let broken = text.replace("--times 2 --chatty", "--times two --bogus") + "run ./callee.nu\n";
    let requests = [
        (
            "textDocument/hover",
            json!({"position": at(&text, "$usage.args.who", 1)}),
        ),
        (
            "textDocument/definition",
            json!({"position": at(&text, "./callee.nu", 2)}),
        ),
        (
            "textDocument/definition",
            json!({"position": at(&text, "$usage.args.who", 1)}),
        ),
        (
            "textDocument/hover",
            json!({"position": {"line": 0, "character": 3}}),
        ),
        ("textDocument/documentSymbol", json!({})),
    ];
    let Some((results, diagnostics)) = session(&text, Some(&broken), &requests) else {
        return;
    };
    // `$usage` has the header's type.
    let hover = results[0]["contents"]["value"].as_str().unwrap();
    assert!(hover.contains("args: record<who: string>"), "{hover}");
    // A shadow leads to its script, and `$usage` to the header.
    let callee = caller().with_file_name("callee.nu");
    assert_eq!(results[1][0]["uri"], json!(uri(&callee)));
    assert_eq!(results[2][0]["uri"], json!(uri(&caller())));
    assert_eq!(results[2][0]["range"]["start"]["line"], json!(1));
    // Line 0 is the editor's, and the prelude's symbols are not.
    assert_eq!(results[3], Json::Null);
    for symbol in results[4].as_array().unwrap() {
        assert_ne!(symbol["range"]["start"]["line"], json!(0), "{symbol}");
    }
    // After the change: Nushell holds the call to the callee's header, and nusage says what a
    // `run` of it does.
    let said = said(&diagnostics);
    let call = at(&broken, "--times two", 0)["line"].as_u64().unwrap();
    let run = at(&broken, "run ./callee.nu", 0)["line"].as_u64().unwrap();
    assert!(
        said.iter()
            .any(|(line, message)| *line == call && message.contains("expected int")),
        "{said:?}"
    );
    assert!(
        said.iter()
            .any(|(line, message)| *line == call && message.contains("flag `bogus`")),
        "{said:?}"
    );
    assert!(
        said.iter()
            .any(|(line, message)| *line == run && message.starts_with("`run ./callee.nu`")),
        "{said:?}"
    );
    assert!(said.iter().all(|(line, _)| *line != 0), "{said:?}");
}

#[test]
fn a_header_that_does_not_read_is_said_and_the_script_still_checks() {
    let text = std::fs::read_to_string(caller())
        .unwrap()
        .replace("#USAGE arg \"<who>\"", "#USAGE arg \"<who>\" {");
    let Some((_, diagnostics)) = session(&text, None, &[]) else {
        return;
    };
    let said = said(&diagnostics);
    assert!(
        said.iter()
            .any(|(_, message)| message.starts_with("header is not valid KDL")),
        "{said:?}"
    );
    // `$usage` is still bound, without its type.
    assert!(
        said.iter()
            .all(|(_, message)| !message.contains("Variable not found")),
        "{said:?}"
    );
}

#[test]
fn a_script_nusage_does_not_run_passes_as_it_is() {
    let text = std::fs::read_to_string(caller())
        .unwrap()
        .replace("#!/usr/bin/env nus", "#!/usr/bin/env nu");
    let Some((_, diagnostics)) = session(&text, None, &[]) else {
        return;
    };
    // Nushell sees no `$usage` in a script it runs itself.
    let said = said(&diagnostics);
    assert!(
        said.iter()
            .any(|(_, message)| message.contains("Variable not found")),
        "{said:?}"
    );
}

#[test]
fn a_shebang_typed_or_taken_away_changes_what_nushell_sees() {
    let text = std::fs::read_to_string(caller()).unwrap();
    let plain = text.replace("#!/usr/bin/env nus", "#!/usr/bin/env nu");
    let unknown = |diagnostics: &[Json]| {
        said(diagnostics)
            .iter()
            .any(|(_, message)| message.contains("Variable not found"))
    };
    // Typed: from the change on, Nushell knows `$usage`.
    let Some((_, typed)) = session(&plain, Some(&text), &[]) else {
        return;
    };
    assert!(!unknown(&typed), "{:?}", said(&typed));
    // Taken away: Nushell sees the script as it is, with no `$usage` in it.
    let Some((_, taken)) = session(&text, Some(&plain), &[]) else {
        return;
    };
    assert!(unknown(&taken), "{:?}", said(&taken));
}

#[test]
fn an_editor_that_goes_without_saying_exit_ends_the_session() {
    if Command::new("nu").arg("--version").output().is_err() {
        assert!(
            std::env::var("CI").as_deref() != Ok("true"),
            "nu is not on PATH"
        );
        return;
    }
    // Nushell's own server would wait for `exit` with its input closed, and so would the
    // server in front of it.
    let document = uri(&caller());
    let mut input = Vec::new();
    for message in [
        json!({"jsonrpc": "2.0", "id": 0, "method": "initialize", "params": {"processId": null, "rootUri": null, "capabilities": {}}}),
        json!({"jsonrpc": "2.0", "method": "initialized", "params": {}}),
        json!({"jsonrpc": "2.0", "method": "textDocument/didOpen", "params": {"textDocument": {"uri": document, "languageId": "nushell", "version": 1, "text": "let a = 1\n"}}}),
    ] {
        let body = serde_json::to_vec(&message).unwrap();
        write!(input, "Content-Length: {}\r\n\r\n", body.len()).unwrap();
        input.extend(body);
    }
    let home = std::env::temp_dir().join(format!("nus-lsp-gone-{}", std::process::id()));
    std::fs::create_dir_all(&home).unwrap();
    let mut server = Command::new(env!("CARGO_BIN_EXE_nus"))
        .args(["lsp", "--", "-n"])
        .env("HOME", &home)
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .spawn()
        .unwrap();
    server.stdin.take().unwrap().write_all(&input).unwrap();
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(60);
    let status = loop {
        if let Some(status) = server.try_wait().unwrap() {
            break status;
        }
        if std::time::Instant::now() > deadline {
            server.kill().unwrap();
            panic!("the server is still waiting for `exit`");
        }
        std::thread::sleep(std::time::Duration::from_millis(50));
    };
    std::fs::remove_dir_all(&home).unwrap();
    // The protocol's code for a server that ends unasked.
    assert_eq!(status.code(), Some(1));
}

/// PATH without kakehashi on it.
fn without_kakehashi() -> String {
    let path = std::env::var_os("PATH").unwrap_or_default();
    let dirs = std::env::split_paths(&path)
        .filter(|dir| !dir.join("kakehashi").is_file() && !dir.join("kakehashi.exe").is_file());
    std::env::join_paths(dirs)
        .unwrap()
        .to_string_lossy()
        .into_owned()
}

#[test]
fn nu_lsp_is_nusages_server_when_kakehashi_is_not_there() {
    let text = std::fs::read_to_string(caller()).unwrap();
    let requests = [(
        "textDocument/hover",
        json!({"position": at(&text, "$usage.args.who", 1)}),
    )];
    let vars = [("PATH", without_kakehashi())];
    let Some((results, _)) = session_with(&["nu", "--lsp"], &vars, &text, None, &requests) else {
        return;
    };
    let hover = results[0]["contents"]["value"].as_str().unwrap();
    assert!(hover.contains("args: record<who: string>"), "{hover}");
}

#[test]
fn the_nu_a_server_of_nusages_starts_is_nushells_own() {
    let text = std::fs::read_to_string(caller()).unwrap();
    let requests = [(
        "textDocument/hover",
        json!({"position": at(&text, "$usage.args.who", 1)}),
    )];
    let vars = [("NUS_LSP", "1".to_string())];
    // `-n`: a Nushell of a home of its own says so on standard output as it writes its
    // configuration files.
    let server = ["nu", "--lsp", "-n"];
    let Some((results, _)) = session_with(&server, &vars, &text, None, &requests) else {
        return;
    };
    // Nushell's own server, which knows no `$usage`.
    let hover = results[0]["contents"]["value"].as_str().unwrap();
    assert!(!hover.contains("record<"), "{hover}");
}

#[test]
fn anything_else_is_nu_itself() {
    if Command::new("nu").arg("--version").output().is_err() {
        assert!(
            std::env::var("CI").as_deref() != Ok("true"),
            "nu is not on PATH"
        );
        return;
    }
    let output = Command::new(env!("CARGO_BIN_EXE_nus"))
        .args(["nu", "-n", "-c", "print ([a b] | str join)"])
        .output()
        .unwrap();
    assert!(output.status.success(), "{output:?}");
    assert_eq!(String::from_utf8_lossy(&output.stdout).trim(), "ab");
}

/// A `nu` first on PATH that runs `nus nu` again, as a wrapper of mise's would that
/// nusage cannot tell for one: the second time round, the same process stops.
#[cfg(unix)]
#[test]
fn a_nu_that_leads_back_here_stops() {
    use std::os::unix::fs::PermissionsExt;
    let dir = std::env::temp_dir().join(format!("nusage-nu-loop-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let nu = dir.join("nu");
    std::fs::write(&nu, "#!/bin/sh\nexec \"$NUS_UNDER_TEST\" nu \"$@\"\n").unwrap();
    std::fs::set_permissions(&nu, std::fs::Permissions::from_mode(0o755)).unwrap();
    let mut child = Command::new(env!("CARGO_BIN_EXE_nus"))
        .args(["nu", "-c", "print hi"])
        .env("PATH", &dir)
        .env("NUS_UNDER_TEST", env!("CARGO_BIN_EXE_nus"))
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(30);
    while child.try_wait().unwrap().is_none() {
        if std::time::Instant::now() > deadline {
            child.kill().unwrap();
            panic!("`nus nu` is still going round");
        }
        std::thread::sleep(std::time::Duration::from_millis(50));
    }
    let output = child.wait_with_output().unwrap();
    std::fs::remove_dir_all(&dir).unwrap();
    assert!(!output.status.success(), "{output:?}");
    assert!(
        String::from_utf8_lossy(&output.stderr).contains("leads back to `nus nu`"),
        "{output:?}"
    );
}

#[test]
fn a_nu_another_one_ran_runs() {
    if Command::new("nu").arg("--version").output().is_err() {
        assert!(
            std::env::var("CI").as_deref() != Ok("true"),
            "nu is not on PATH"
        );
        return;
    }
    // The mark of a `nus nu` that ran this process's parent, as a `nu` Nushell starts has.
    let output = Command::new(env!("CARGO_BIN_EXE_nus"))
        .args(["nu", "-n", "-c", "print inner"])
        .env("NUS_NU_PID", "1")
        .output()
        .unwrap();
    assert!(output.status.success(), "{output:?}");
    assert_eq!(String::from_utf8_lossy(&output.stdout).trim(), "inner");
}
