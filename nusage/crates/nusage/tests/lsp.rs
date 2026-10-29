//! `nusage lsp` in front of the pinned `nu --lsp`: a whole session is written to it at once
//! and its answers read back, which Nushell gives in order, diagnostics after each change.
//! Without `nu` on PATH the session is skipped, except in CI, where it fails.

use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};

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

/// [`session`], with the server started as `nusage` and these arguments, in this
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
    messages.push(json!({"jsonrpc": "2.0", "method": "exit"}));
    let mut input = Vec::new();
    for message in &messages {
        let body = serde_json::to_vec(message).unwrap();
        write!(input, "Content-Length: {}\r\n\r\n", body.len()).unwrap();
        input.extend(body);
    }

    // Nushell's own files go to a home of the session's; sessions run side by side.
    static SESSIONS: AtomicUsize = AtomicUsize::new(0);
    let home = std::env::temp_dir().join(format!(
        "nusage-lsp-{}-{}",
        std::process::id(),
        SESSIONS.fetch_add(1, Ordering::Relaxed)
    ));
    std::fs::create_dir_all(&home).unwrap();
    let mut server = Command::new(env!("CARGO_BIN_EXE_nusage"))
        .args(server)
        .envs(vars.iter().map(|(name, value)| (*name, value)))
        .env("HOME", &home)
        .env("XDG_CONFIG_HOME", home.join(".config"))
        .env("XDG_DATA_HOME", home.join(".local/share"))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    server.stdin.take().unwrap().write_all(&input).unwrap();
    let output = server.wait_with_output().unwrap();
    std::fs::remove_dir_all(&home).unwrap();
    assert!(output.status.success(), "{:?}", output.status);

    let mut results = vec![Json::Null; requests.len()];
    let mut diagnostics = Vec::new();
    let mut rest = output.stdout.as_slice();
    while !rest.is_empty() {
        let split = rest.windows(4).position(|w| w == b"\r\n\r\n").unwrap();
        let head = std::str::from_utf8(&rest[..split]).unwrap();
        let length: usize = head.split(':').nth(1).unwrap().trim().parse().unwrap();
        let body: Json = serde_json::from_slice(&rest[split + 4..split + 4 + length]).unwrap();
        rest = &rest[split + 4 + length..];
        if body["method"] == "textDocument/publishDiagnostics" && body["params"]["uri"] == document
        {
            diagnostics = body["params"]["diagnostics"].as_array().unwrap().clone();
        } else if let Some(id) = body["id"].as_u64()
            && (1..=requests.len() as u64).contains(&id)
        {
            results[id as usize - 1] = body["result"].clone();
        }
    }
    Some((results, diagnostics))
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
        .replace("#!/usr/bin/env nusage", "#!/usr/bin/env nu");
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
    let plain = text.replace("#!/usr/bin/env nusage", "#!/usr/bin/env nu");
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
    let home = std::env::temp_dir().join(format!("nusage-lsp-gone-{}", std::process::id()));
    std::fs::create_dir_all(&home).unwrap();
    let mut server = Command::new(env!("CARGO_BIN_EXE_nusage"))
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
    let vars = [("NUSAGE_LSP", "1".to_string())];
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
    let output = Command::new(env!("CARGO_BIN_EXE_nusage"))
        .args(["nu", "-n", "-c", "print ([a b] | str join)"])
        .output()
        .unwrap();
    assert!(output.status.success(), "{output:?}");
    assert_eq!(String::from_utf8_lossy(&output.stdout).trim(), "ab");
}
