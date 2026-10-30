//! The jev commands against a stand-in for the service: what each sends, what it returns,
//! and that an answer given once is not asked for again.

use std::io::{BufRead, BufReader, Read, Write};
use std::net::TcpListener;

use nu_plugin_jev::JevPlugin;
use nusage_plugin::nu_protocol::Value;
use nusage_plugin::test::{harness, value};

/// A server answering `replies` in order, one connection each; what it saw, a request body
/// each, with the authorization header.
fn serve(
    replies: Vec<(u16, &'static str)>,
) -> (String, std::thread::JoinHandle<Vec<(String, String)>>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    let handle = std::thread::spawn(move || {
        let mut seen = Vec::new();
        for (status, body) in replies {
            let (stream, _) = listener.accept().unwrap();
            let mut reader = BufReader::new(stream);
            let mut line = String::new();
            reader.read_line(&mut line).unwrap();
            assert!(line.starts_with("POST /v1/systemone "), "{line}");
            let mut length = 0;
            let mut authorization = String::new();
            loop {
                let mut header = String::new();
                reader.read_line(&mut header).unwrap();
                let header = header.trim_end();
                if header.is_empty() {
                    break;
                }
                let (key, value) = header.split_once(':').unwrap();
                match key.to_lowercase().as_str() {
                    "content-length" => length = value.trim().parse().unwrap(),
                    "authorization" => authorization = value.trim().to_string(),
                    _ => {}
                }
            }
            let mut received = vec![0; length];
            reader.read_exact(&mut received).unwrap();
            seen.push((String::from_utf8(received).unwrap(), authorization));
            let response = format!(
                "HTTP/1.1 {status} X\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                body.len()
            );
            reader.get_mut().write_all(response.as_bytes()).unwrap();
        }
        seen
    });
    (url, handle)
}

fn test_at(url: &str, token: Option<&str>) -> nusage_plugin::test::PluginTest {
    let mut test = harness("jev", JevPlugin::new().unwrap()).unwrap();
    let state = test.engine_state_mut();
    state.add_env_var("TYPESAFE_URL".into(), Value::test_string(url));
    if let Some(token) = token {
        state.add_env_var("TYPESAFE_TOKEN".into(), Value::test_string(token));
    }
    test
}

const ANSWER: &str = r#"{"model": "jev-latest", "answers": {"answer": {"type": "noul", "noul": 0.93}}, "usage": {"input_tokens": 12, "output_tokens": 3}}"#;

#[test]
fn a_statement_is_judged_once_and_the_answer_kept() {
    let (url, server) = serve(vec![(200, ANSWER)]);
    let mut test = test_at(&url, Some("s3cret"));
    let first = value(
        &mut test,
        r#""I was charged twice" | jev noul "Is this about billing?""#,
    )
    .unwrap();
    assert_eq!(first, Value::test_float(0.93));
    // The same question of the same content: answered from what was kept, so the server,
    // which takes one connection, is not asked again.
    let again = value(
        &mut test,
        r#""I was charged twice" | jev noul "Is this about billing?""#,
    )
    .unwrap();
    assert_eq!(again, Value::test_float(0.93));
    let seen = server.join().unwrap();
    assert_eq!(seen.len(), 1);
    let (body, authorization) = &seen[0];
    assert_eq!(authorization, "Bearer s3cret");
    let request: serde_json::Value = serde_json::from_str(body).unwrap();
    assert_eq!(request["model"], "jev-latest");
    assert_eq!(request["state"], "I was charged twice");
    assert_eq!(request["questions"]["answer"]["type"], "noul");
    assert_eq!(
        request["questions"]["answer"]["instructions"],
        "Is this about billing?"
    );
}

#[test]
fn questions_are_asked_as_given_and_answered_as_a_record() {
    let (url, server) = serve(vec![(
        200,
        r#"{"model": "jev-latest", "answers": {"category": {"type": "choice", "choice": "billing", "probabilities": {"billing": 0.9, "other": 0.1}}}, "usage": {"input_tokens": 1, "output_tokens": 1}}"#,
    )]);
    let mut test = test_at(&url, Some("k"));
    let answer = value(
        &mut test,
        r#"{text: "charged twice", id: 7} | jev ask {category: {type: choice, criteria: {billing: null, other: null}}} --model jev-preview"#,
    )
    .unwrap();
    assert_eq!(
        answer
            .get_data_by_key("answers")
            .unwrap()
            .get_data_by_key("category")
            .unwrap()
            .get_data_by_key("choice")
            .unwrap(),
        Value::test_string("billing")
    );
    let seen = server.join().unwrap();
    let request: serde_json::Value = serde_json::from_str(&seen[0].0).unwrap();
    assert_eq!(request["model"], "jev-preview");
    // A record as the content goes as the JSON it is.
    assert_eq!(request["state"]["id"], 7);
    assert_eq!(
        request["questions"]["category"]["criteria"]["other"],
        serde_json::Value::Null
    );
}

#[test]
fn what_the_service_refuses_is_an_error_naming_the_status() {
    let (url, server) = serve(vec![(401, r#"{"error": "no such key"}"#)]);
    let mut test = test_at(&url, Some("wrong"));
    let err = value(&mut test, r#""x" | jev noul "y""#)
        .unwrap_err()
        .to_string();
    server.join().unwrap();
    assert!(
        err.contains("answered 401") && err.contains("no such key"),
        "{err}"
    );
}

#[test]
fn without_a_key_nothing_is_sent() {
    let mut test = test_at("http://127.0.0.1:9", None);
    let err = value(&mut test, r#""x" | jev noul "y""#)
        .unwrap_err()
        .to_string();
    assert!(err.contains("TYPESAFE_TOKEN"), "{err}");
    let help = value(&mut test, "jev").unwrap().coerce_string().unwrap();
    assert!(help.contains("ask") && help.contains("noul"), "{help}");
}
