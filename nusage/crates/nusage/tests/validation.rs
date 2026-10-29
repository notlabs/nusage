//! Runtime behavior, including the real generated Nu pipeline and a live JSONL stream.
use std::io::{BufRead, BufReader, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Duration;

use serde_json::{Value, json};

const DIALECT: &str = "https://gerrit.tail3b571d.ts.net/plugins/gitiles/notlabs/+/refs/heads/nusage/nuon-schema/nusage/nuon-schema/meta.json";
const BIN: &str = env!("CARGO_BIN_EXE_nusage");

struct Dir(PathBuf);
impl Dir {
    fn new() -> Self {
        static NEXT: AtomicUsize = AtomicUsize::new(0);
        let path = std::env::temp_dir().join(format!(
            "nusage-runtime-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        std::fs::create_dir_all(&path).unwrap();
        Self(path)
    }
    fn write(&self, name: &str, text: &str) -> PathBuf {
        let path = self.0.join(name);
        std::fs::write(&path, text).unwrap();
        path
    }
}
impl Drop for Dir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn command() -> Command {
    let mut c = Command::new(BIN);
    c.arg("validate")
        .env_remove("NUSAGE_VALIDATE")
        .env_remove("NUSAGE_SCHEMA_ALLOW")
        .env("NUSAGE_DIAGNOSTICS", "json");
    c
}

fn input(mut c: Command, text: &str) -> Output {
    let mut child = c
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    child
        .stdin
        .take()
        .unwrap()
        .write_all(text.as_bytes())
        .unwrap();
    child.wait_with_output().unwrap()
}

fn diagnostic(output: &Output) -> Value {
    assert!(!output.status.success(), "unexpected success");
    serde_json::from_slice(&output.stderr).unwrap()
}

#[test]
fn explicit_validation_checks_formats_and_never_emits_invalid_data() {
    let mut c = command();
    c.args([
        "--schema-json",
        r#"{"type":"object","properties":{"at":{"format":"date-time"}}}"#,
        "--passthrough",
        "--source",
        "tool events stdout",
    ]);
    let out = input(c, r#"{"at":"yesterday"}"#);
    assert!(out.stdout.is_empty());
    let d = diagnostic(&out);
    assert_eq!(d["code"], "nusage::validation::invalid");
    assert_eq!(d["path"], "tool events stdout");
    assert_eq!(d["instance_path"], "/at");
    assert_eq!(d["schema_path"], "/properties/at/format");
    assert!(
        d["schema_uri"]
            .as_str()
            .unwrap()
            .ends_with("#/properties/at/format")
    );
}

#[test]
fn header_and_blank_lines_preserve_physical_locations_and_fail_at_the_bad_record() {
    let header = json!({"$schema":DIALECT,"type":"object","required":["n"],"properties":{"n":{"type":"integer"}}});
    let mut c = command();
    c.args(["--auto", "--jsonl", "--passthrough"]);
    let out = input(
        c,
        &format!("\n{header}\n{{\"n\":1}}\n\n{{\"n\":\"bad\"}}\n{{\"n\":3}}\n"),
    );
    assert_eq!(out.stdout, b"{\"n\":1}\n");
    let d = diagnostic(&out);
    assert_eq!(d["line"], 5);
    assert_eq!(d["record"], 2);
    assert_eq!(d["instance_path"], "/n");
}

#[test]
fn unknown_declarations_and_ordinary_schema_documents_are_not_headers() {
    let mut c = command();
    c.args(["--auto", "--jsonl", "--passthrough"]);
    let text = "{\"$schema\":\"https://example.invalid/unknown\",\"n\":1}\n{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":\"integer\"}\n";
    let out = input(c, text);
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    assert_eq!(out.stdout, text.as_bytes());
    assert!(out.stderr.is_empty());
}

#[test]
fn explicit_schema_takes_precedence_and_opt_out_copies_bytes() {
    let header = json!({"$schema":DIALECT,"type":"integer"}).to_string();
    let mut c = command();
    c.args([
        "--schema-json",
        "{\"type\":\"integer\"}",
        "--jsonl",
        "--passthrough",
    ]);
    assert_eq!(
        diagnostic(&input(c, &header))["code"],
        "nusage::validation::invalid"
    );
    let mut c = command();
    c.args(["--auto", "--passthrough"])
        .env("NUSAGE_VALIDATE", "off")
        .env("NUSAGE_SCHEMA_ALLOW", "not even JSON");
    let out = input(c, "not JSON\n");
    assert!(out.status.success());
    assert_eq!(out.stdout, b"not JSON\n");
    // An explicit check still checks when automatic validation has been disabled.
    let dir = Dir::new();
    let schema = dir.write("schema.json", "{\"type\":\"integer\"}");
    let bad = dir.write("bad.json", "false");
    let out = command()
        .arg(schema)
        .arg(bad)
        .env("NUSAGE_VALIDATE", "off")
        .output()
        .unwrap();
    assert_eq!(diagnostic(&out)["code"], "nusage::validation::invalid");
}

#[test]
fn local_names_are_relative_to_the_data_and_do_not_become_stream_headers() {
    let dir = Dir::new();
    dir.write(
        "schema.json",
        &json!({"$schema":DIALECT,"properties":{"n":{"type":"integer"}}}).to_string(),
    );
    let data = dir.write(
        "data.jsonl",
        "{\"$schema\":\"schema.json\",\"n\":1}\n{\"n\":\"untyped\"}\n",
    );
    let opts = nusage::ValidationOptions {
        auto: true,
        jsonl: true,
        passthrough: true,
        ..Default::default()
    };
    let mut out = Vec::new();
    assert!(
        nusage::validate_with(&opts, std::slice::from_ref(&data), &mut out)
            .unwrap()
            .is_empty()
    );
    assert_eq!(out, std::fs::read(&data).unwrap());
    let from_cli = command()
        .args(["--auto", "--jsonl", "--passthrough"])
        .arg(data)
        .current_dir(std::env::temp_dir())
        .output()
        .unwrap();
    assert!(from_cli.status.success());
    assert_eq!(out, from_cli.stdout);
}

#[test]
fn file_allowlist_supports_fragments_and_rejects_unapproved_references() {
    let dir = Dir::new();
    let target = dir.write("target.json", r#"{"$schema":"https://json-schema.org/draft/2020-12/schema","$defs":{"row":{"required":["n"]}}}"#);
    let target_url = url::Url::from_file_path(&target).unwrap();
    let mut c = command();
    c.args(["--auto", "--passthrough"]).env(
        "NUSAGE_SCHEMA_ALLOW",
        json!([target_url.as_str()]).to_string(),
    );
    let data = json!({"$schema":format!("{target_url}#/$defs/row")});
    assert_eq!(
        diagnostic(&input(c, &data.to_string()))["code"],
        "nusage::validation::invalid"
    );
    let schema = json!({"$ref":target_url.as_str()}).to_string();
    let mut c = command();
    c.args(["--schema-json", &schema, "--passthrough"]);
    let d = diagnostic(&input(c, "{}"));
    assert_eq!(d["code"], "nusage::schema::resolve");
    assert!(
        d["message"]
            .as_str()
            .unwrap()
            .contains("NUSAGE_SCHEMA_ALLOW")
    );
}

#[test]
fn allowed_http_schema_is_reused_and_disallowed_urls_are_never_contacted() {
    use std::net::TcpListener;
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    listener.set_nonblocking(true).unwrap();
    let url = format!(
        "http://{}/schemas/event.json",
        listener.local_addr().unwrap()
    );
    let mut c = command();
    c.args(["--auto", "--passthrough"]);
    let data = json!({"$schema":url,"n":"bad"}).to_string();
    assert!(input(c, &data).status.success());
    assert!(matches!(listener.accept(), Err(e) if e.kind() == std::io::ErrorKind::WouldBlock));
    let server = std::thread::spawn(move || {
        let until = std::time::Instant::now() + Duration::from_secs(10);
        loop {
            match listener.accept() {
                Ok((mut stream, _)) => {
                    stream
                        .set_read_timeout(Some(Duration::from_secs(2)))
                        .unwrap();
                    let mut request = [0; 4096];
                    assert!(stream.read(&mut request).unwrap() > 0);
                    let schema = r#"{"properties":{"n":{"type":"integer"}}}"#;
                    write!(stream, "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{schema}", schema.len()).unwrap();
                    break;
                }
                Err(e)
                    if e.kind() == std::io::ErrorKind::WouldBlock
                        && std::time::Instant::now() < until =>
                {
                    std::thread::sleep(Duration::from_millis(10))
                }
                other => panic!("schema was not retrieved: {other:?}"),
            }
        }
    });
    let mut c = command();
    let pattern = format!("{}/schemas/**", url.split("/schemas/").next().unwrap());
    c.args(["--auto", "--jsonl", "--passthrough"])
        .env("NUSAGE_SCHEMA_ALLOW", json!([pattern]).to_string());
    let good = json!({"$schema":url,"n":1}).to_string();
    let out = input(c, &format!("{good}\n{good}\n{data}\n"));
    server.join().unwrap();
    assert_eq!(out.stdout, format!("{good}\n{good}\n").as_bytes());
    assert_eq!(diagnostic(&out)["record"], 3);
}

#[test]
fn jsonl_emits_before_stdin_closes() {
    let mut child = command()
        .args([
            "--schema-json",
            "{\"type\":\"integer\"}",
            "--jsonl",
            "--passthrough",
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    let mut stdin = child.stdin.take().unwrap();
    let stdout = child.stdout.take().unwrap();
    let (send, recv) = std::sync::mpsc::channel();
    let reader = std::thread::spawn(move || {
        let mut text = String::new();
        BufReader::new(stdout).read_line(&mut text).unwrap();
        send.send(text).unwrap();
    });
    stdin.write_all(b"1\n").unwrap();
    stdin.flush().unwrap();
    let first = recv.recv_timeout(Duration::from_secs(5));
    if first.is_err() {
        child.kill().unwrap();
    }
    assert_eq!(first.unwrap(), "1\n");
    stdin.write_all(b"false\n").unwrap();
    drop(stdin);
    assert!(!child.wait().unwrap().success());
    reader.join().unwrap();
}

#[test]
fn generated_nu_wrapper_reports_validation_failure_before_conversion() {
    let fixture = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../fixtures/binary-schema");
    let dir = Dir::new();
    let module = dir.0.join("probe.nu");
    std::fs::write(
        &module,
        nusage::generate(&fixture.join("probe.usage.kdl"), Some(&module)).unwrap(),
    )
    .unwrap();
    let paths = std::iter::once(fixture.join("fake"))
        .chain(std::iter::once(Path::new(BIN).parent().unwrap().to_owned()))
        .chain(std::env::split_paths(&std::env::var_os("PATH").unwrap()))
        .collect::<Vec<_>>();
    let out = Command::new("nu")
        .args(["--no-config-file", "-c"])
        .arg(format!(
            "use '{}' *; probe events | to nuon",
            module.display()
        ))
        .env("PATH", std::env::join_paths(paths).unwrap())
        .env("NUSAGE_FAKE_ARGV", dir.0.join("argv"))
        .env(
            "NUSAGE_FAKE_STDOUT",
            "{\"at\":0,\"kind\":\"start\"}\n{\"at\":1,\"kind\":\"invalid\"}",
        )
        .env_remove("NUSAGE_VALIDATE")
        .env_remove("NUSAGE_DIAGNOSTICS")
        .env_remove("NUSAGE_SCHEMA_ALLOW")
        .output()
        .expect("the pinned nu must be on PATH");
    assert!(
        !out.status.success(),
        "validation failure disappeared: {}",
        String::from_utf8_lossy(&out.stdout)
    );
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(stderr.contains("nusage::validation::invalid"), "{stderr}");
    assert!(stderr.contains("/kind"), "{stderr}");
}

#[test]
fn syntax_schema_and_policy_failures_use_the_same_diagnostic_record() {
    for (args, input_text, expected) in [
        (vec!["--auto", "--passthrough"], "{", "nusage::json::parse"),
        (
            vec!["--schema-json", "{\"type\":\"invalid\"}", "--passthrough"],
            "{}",
            "nusage::schema::invalid",
        ),
    ] {
        let mut c = command();
        c.args(args);
        let out = input(c, input_text);
        let d = diagnostic(&out);
        assert_eq!(d["code"], expected);
        assert!(d["message"].is_string());
        assert!(d["path"].is_string());
        assert!(out.stdout.is_empty());
    }
    let mut c = command();
    c.args(["--auto"])
        .env("NUSAGE_SCHEMA_ALLOW", "[\"https://*.example.com/**\"]");
    assert_eq!(
        diagnostic(&input(c, "{}"))["code"],
        "nusage::schema::policy"
    );
    // Existing spec errors use the same JSON renderer, too.
    let out = Command::new(BIN)
        .args(["generate", "/does-not-exist/nusage.usage.kdl"])
        .env("NUSAGE_DIAGNOSTICS", "json")
        .output()
        .unwrap();
    assert_eq!(diagnostic(&out)["code"], "nusage::spec");
}

#[cfg(unix)]
#[test]
fn generated_nu_wrapper_streams_before_the_producer_finishes() {
    use std::os::unix::fs::PermissionsExt;
    let fixture = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../fixtures/binary-schema");
    let dir = Dir::new();
    let module = dir.0.join("probe.nu");
    std::fs::write(
        &module,
        nusage::generate(&fixture.join("probe.usage.kdl"), Some(&module)).unwrap(),
    )
    .unwrap();
    let producer = dir.write("probe", "#!/bin/sh\nprintf '%s\\n' '{\"at\":0,\"kind\":\"start\"}'\nwhile [ ! -f \"$NUSAGE_RELEASE\" ]; do sleep 0.05; done\n");
    std::fs::set_permissions(producer, std::fs::Permissions::from_mode(0o755)).unwrap();
    let paths = std::iter::once(dir.0.clone())
        .chain(std::iter::once(Path::new(BIN).parent().unwrap().to_owned()))
        .chain(std::env::split_paths(&std::env::var_os("PATH").unwrap()))
        .collect::<Vec<_>>();
    let release = dir.0.join("release");
    let mut child = Command::new("nu")
        .args(["--no-config-file", "-c"])
        .arg(format!(
            "use '{}' *; probe events | each {{ to nuon | print }}",
            module.display()
        ))
        .env("PATH", std::env::join_paths(paths).unwrap())
        .env("NUSAGE_RELEASE", &release)
        .env_remove("NUSAGE_VALIDATE")
        .env_remove("NUSAGE_SCHEMA_ALLOW")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    let stdout = child.stdout.take().unwrap();
    let (send, recv) = std::sync::mpsc::channel();
    let reader = std::thread::spawn(move || {
        let mut line = String::new();
        let mut reader = BufReader::new(stdout);
        reader.read_line(&mut line).unwrap();
        let _ = send.send(line);
        reader.read_to_end(&mut Vec::new()).unwrap();
    });
    let first = recv.recv_timeout(Duration::from_secs(5));
    std::fs::write(release, "done").unwrap();
    let output = child.wait_with_output().unwrap();
    reader.join().unwrap();
    assert!(
        first
            .expect("wrapper buffered the stream")
            .contains("start")
    );
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
}

#[test]
fn generated_jsonl_keeps_null_and_nested_arrays() {
    let dir = Dir::new();
    let spec = dir.write(
        "probe.usage.kdl",
        "name \"probe\"\nbin \"probe\"\noutput \"jsonl\" framing=\"jsonl\" default=#true\n",
    );
    let module = dir.0.join("probe.nu");
    std::fs::write(&module, nusage::generate(&spec, Some(&module)).unwrap()).unwrap();
    let fake = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../fixtures/binary-schema/fake");
    let paths = std::iter::once(fake)
        .chain(std::iter::once(Path::new(BIN).parent().unwrap().to_owned()))
        .chain(std::env::split_paths(&std::env::var_os("PATH").unwrap()))
        .collect::<Vec<_>>();
    let out = Command::new("nu")
        .args(["--no-config-file", "-c"])
        .arg(format!("use '{}'; probe | to json --raw", module.display()))
        .env("PATH", std::env::join_paths(paths).unwrap())
        .env("NUSAGE_FAKE_ARGV", dir.0.join("argv"))
        .env("NUSAGE_FAKE_STDOUT", "null\nfalse\n[]\n[1,2]")
        .env_remove("NUSAGE_VALIDATE")
        .env_remove("NUSAGE_SCHEMA_ALLOW")
        .output()
        .unwrap();
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    assert_eq!(
        serde_json::from_slice::<Value>(&out.stdout).unwrap(),
        json!([null, false, [], [1, 2]])
    );
}
