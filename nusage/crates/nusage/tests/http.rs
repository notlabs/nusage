//! The petstore module, generated from the fixture's spec and HTTP mapping, against a server
//! of the test's own: what each wrapper sends, and the typed value it returns. Nushell runs
//! the module, so without `nu` on PATH the test is skipped, except in CI, where it fails.

use std::io::{BufRead, BufReader, Read, Write};
use std::net::TcpListener;
use std::path::Path;
use std::process::Command;

/// One request as the server saw it: the request line, the headers in lower case, the body.
#[derive(Debug)]
struct Seen {
    line: String,
    headers: Vec<(String, String)>,
    body: String,
}

impl Seen {
    fn header(&self, name: &str) -> Option<&str> {
        self.headers
            .iter()
            .find(|(key, _)| key == name)
            .map(|(_, value)| value.as_str())
    }
}

/// A server answering `replies` in order, one connection each, and what it saw.
fn serve(replies: Vec<(u16, &'static str)>) -> (String, std::thread::JoinHandle<Vec<Seen>>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    let handle = std::thread::spawn(move || {
        let mut seen = Vec::new();
        for (status, body) in replies {
            let (stream, _) = listener.accept().unwrap();
            let mut reader = BufReader::new(stream);
            let mut line = String::new();
            reader.read_line(&mut line).unwrap();
            let mut headers = Vec::new();
            loop {
                let mut header = String::new();
                reader.read_line(&mut header).unwrap();
                let header = header.trim_end();
                if header.is_empty() {
                    break;
                }
                let (key, value) = header.split_once(':').unwrap();
                headers.push((key.to_lowercase(), value.trim().to_string()));
            }
            let length: usize = headers
                .iter()
                .find(|(key, _)| key == "content-length")
                .map(|(_, value)| value.parse().unwrap())
                .unwrap_or(0);
            let mut received = vec![0; length];
            reader.read_exact(&mut received).unwrap();
            seen.push(Seen {
                line: line.trim_end().to_string(),
                headers,
                body: String::from_utf8(received).unwrap(),
            });
            let reason = if status == 200 { "OK" } else { "Not Found" };
            let response = format!(
                "HTTP/1.1 {status} {reason}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                body.len()
            );
            reader.get_mut().write_all(response.as_bytes()).unwrap();
        }
        seen
    });
    (url, handle)
}

/// `code` run by `nu` with the petstore module in scope, pointed at `url`; the output, or
/// `None` without a `nu` to run it.
fn run(url: &str, code: &str) -> Option<std::process::Output> {
    if Command::new("nu").arg("--version").output().is_err() {
        assert!(
            std::env::var("CI").as_deref() != Ok("true"),
            "nu is not on PATH"
        );
        eprintln!("skipped: nu is not on PATH");
        return None;
    }
    let module = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../fixtures/http-petstore/expected/petstore.nu")
        .canonicalize()
        .unwrap();
    let script = format!("use {} *\n{code}", nuon_string(&module.to_string_lossy()));
    Some(
        Command::new("nu")
            .args(["-n", "-c", &script])
            .env("PETSTORE_URL", url)
            .env("PETSTORE_TOKEN", "s3cret")
            .output()
            .unwrap(),
    )
}

fn nuon_string(text: &str) -> String {
    format!("{:?}", text)
}

#[test]
fn the_wrappers_send_what_the_mapping_says_and_return_typed_values() {
    let (url, server) = serve(vec![
        (
            200,
            r#"[{"id": 1, "name": "Rex", "born": "2024-01-02T03:04:05Z"}, {"id": 2, "name": "Tom", "tag": "cat", "owner": {"name": "Ana"}}]"#,
        ),
        (200, ""),
        (200, r#"{"id": 7, "name": "Kit", "owner": null}"#),
        (200, ""),
    ]);
    let code = r#"
let pets = petstore list-pets --limit 2 --tags [a b] --x-request-id 7
let created = {name: Rex, tag: dog} | petstore create-pets
let kit = petstore show-pet-by-id 7
let gone = petstore delete-pets-pet-id 7 --force
{
    pets: $pets,
    born: ($pets | first | get born | describe),
    created: $created,
    kit: $kit,
    gone: $gone,
    where: (petstore),
} | to nuon
"#;
    let Some(output) = run(&url, code) else {
        return;
    };
    let seen = server.join().unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let stdout = String::from_utf8_lossy(&output.stdout);
    let value = nuon::from_nuon(&stdout, None).unwrap();
    let field = |name: &str| value.get_data_by_key(name).unwrap();
    // The query from the flags, a list repeated, the header from its flag, the token as
    // the bearer.
    assert_eq!(seen[0].line, "GET /pets?limit=2&tags=a&tags=b HTTP/1.1");
    assert_eq!(seen[0].header("x-request-id"), Some("7"));
    assert_eq!(seen[0].header("authorization"), Some("Bearer s3cret"));
    // The body as JSON, from the input.
    assert_eq!(seen[1].line, "POST /pets HTTP/1.1");
    assert!(
        seen[1]
            .header("content-type")
            .is_some_and(|media| media.starts_with("application/json")),
        "{:?}",
        seen[1].headers
    );
    assert_eq!(
        serde_json::from_str::<serde_json::Value>(&seen[1].body).unwrap(),
        serde_json::json!({"name": "Rex", "tag": "dog"})
    );
    // The path parameter in the path, and the switch in the query.
    assert_eq!(seen[2].line, "GET /pets/7 HTTP/1.1");
    assert_eq!(seen[3].line, "DELETE /pets/7?force=true HTTP/1.1");
    // Typed: the absent properties filled, the date a datetime.
    assert_eq!(field("born").coerce_string().unwrap(), "datetime");
    let pets = field("pets").into_list().unwrap();
    assert_eq!(pets.len(), 2);
    assert_eq!(
        pets[1]
            .get_data_by_key("owner")
            .unwrap()
            .get_data_by_key("pets")
            .unwrap(),
        nu_protocol::Value::test_nothing()
    );
    assert_eq!(field("created").coerce_string().unwrap(), "");
    assert_eq!(
        field("kit")
            .get_data_by_key("name")
            .unwrap()
            .coerce_string()
            .unwrap(),
        "Kit"
    );
    assert_eq!(field("gone").coerce_string().unwrap(), "");
    assert_eq!(field("where").coerce_string().unwrap(), url);
}

#[test]
fn a_response_that_is_not_a_success_is_an_error_naming_the_status() {
    let (url, server) = serve(vec![(404, r#"{"code": 404, "message": "no such pet"}"#)]);
    let Some(output) = run(&url, "petstore show-pet-by-id 9") else {
        return;
    };
    server.join().unwrap();
    assert!(!output.status.success());
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains("GET")
            && stderr.contains("/pets/9 answered 404")
            && stderr.contains("no such pet"),
        "{stderr}"
    );
}
