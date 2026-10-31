//! usage's argv corpus through `nus parse`: each vector's spec becomes a script's
//! `#USAGE` header, the script is parsed with the vector's argv and environment, and the
//! `$usage` record has to hold everything `expect.ok` binds, or the arguments have to be
//! rejected when the vector expects an error. The corpus is usage's own, at
//! `$NUS_CORPUS` (the `corpus/` directory of its source, which `mise.toml` installs);
//! without it the test is skipped. The format is usage's:
//! https://github.com/jdx/usage/blob/main/corpus/README.md
//!
//! A spec with `cmd` nodes is laid out as the tree the interpreter reads: the root's nodes
//! in `mod.nu`, each command's in `<name>.nu` or `<name>/mod.nu`, and the root script is
//! posed the argv, which usage routes.
//!
//! Not posed: vectors that choose `argv0`, since a script is called by its own name; vectors
//! with `mounts`, since the interpreter runs no command while parsing; and vectors whose
//! `cmd` nodes carry properties other than `help`, which a header has no line for.

use std::path::{Path, PathBuf};
use std::process::Command;

use nu_protocol::Value;
use serde_json::Value as Json;
use usage::kdl::{KdlDocument, KdlNode};

#[test]
fn usage_corpus_binds_the_same() {
    let Ok(corpus) = std::env::var("NUS_CORPUS") else {
        // The mise task sets it; a bare `cargo test` without the corpus says so, and in CI
        // that is a failure, since a check that did not run proves nothing.
        assert!(
            std::env::var_os("CI").is_none(),
            "NUS_CORPUS is not set; `mise run //nusage:test` sets it to usage's corpus"
        );
        eprintln!("NUS_CORPUS is not set; usage's corpus is not posed");
        return;
    };
    let corpus = Path::new(&corpus);
    let mut files: Vec<_> = std::fs::read_dir(corpus)
        .unwrap_or_else(|err| panic!("{}: {err}", corpus.display()))
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| path.extension().is_some_and(|ext| ext == "json"))
        .collect();
    files.sort();
    assert!(!files.is_empty(), "no vectors under {}", corpus.display());

    let dir = tempdir();
    let mut posed = 0;
    let mut skipped = Vec::new();
    let mut disagreements = Vec::new();
    for file in &files {
        let text = std::fs::read_to_string(file).unwrap();
        let section: Json = serde_json::from_str(&text).unwrap();
        for vector in section["vectors"].as_array().unwrap() {
            let id = vector["id"].as_str().unwrap().to_string();
            if vector.get("argv0").is_some()
                || vector.get("mounts").is_some()
                || has_command_properties(vector["spec"].as_str().unwrap())
            {
                skipped.push(id);
                continue;
            }
            posed += 1;
            if let Some(why) = pose(&dir, vector) {
                disagreements.push(format!("{id}: {why}"));
            }
        }
    }
    eprintln!(
        "corpus: {posed} vectors posed, {} not posed: {}",
        skipped.len(),
        skipped.join(", ")
    );
    assert!(
        disagreements.is_empty(),
        "{} of {posed} vectors disagree:\n  {}",
        disagreements.len(),
        disagreements.join("\n  ")
    );
}

/// Pose one vector; `Some(why)` when the interpreter disagrees with it.
fn pose(dir: &Path, vector: &Json) -> Option<String> {
    let tree = dir.join("tree");
    let _ = std::fs::remove_dir_all(&tree);
    std::fs::create_dir_all(&tree).unwrap();
    let doc: KdlDocument = vector["spec"].as_str().unwrap().parse().unwrap();
    let script = write_command(&tree, doc.nodes(), true);
    let argv: Vec<&str> = vector["argv"]
        .as_array()
        .unwrap()
        .iter()
        .map(|word| word.as_str().unwrap())
        .collect();
    let mut command = Command::new(env!("CARGO_BIN_EXE_nus"));
    command.arg("parse").arg(&script).arg("--").args(&argv);
    if let Some(env) = vector.get("env").and_then(Json::as_object) {
        for (name, value) in env {
            command.env(name, value.as_str().unwrap());
        }
    }
    let output = command.output().unwrap();
    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    let expect = &vector["expect"];
    if let Some(error) = expect.get("error") {
        // usage's refusal is exit code 2; anything else is the interpreter's own failure.
        return match output.status.code() {
            Some(2) => None,
            Some(0) => Some(format!(
                "expected the error {error}, bound {}",
                stdout.trim()
            )),
            code => Some(format!(
                "expected the error {error}, but the interpreter failed (exit {code:?}): {}",
                stderr.trim()
            )),
        };
    }
    if !output.status.success() {
        return Some(format!("rejected: {}", stderr.trim()));
    }
    let bound = nuon::from_nuon(&stdout, None)
        .unwrap_or_else(|err| panic!("{} did not print NUON: {err}\n{stdout}", vector["id"]));
    let expected = flattened(&expect["ok"], &bound);
    holds(&expected, &bound, "")
}

/// Whether a `cmd` node of the spec carries a property a header cannot spell.
fn has_command_properties(spec: &str) -> bool {
    fn check(nodes: &[KdlNode]) -> bool {
        nodes.iter().any(|node| {
            node.name().value() == "cmd"
                && (node
                    .entries()
                    .iter()
                    .any(|entry| entry.name().is_some_and(|name| name.value() != "help"))
                    || node
                        .children()
                        .is_some_and(|children| check(children.nodes())))
        })
    }
    let doc: KdlDocument = spec.parse().unwrap();
    check(doc.nodes())
}

/// Write a command's nodes as a script's header and return the script: `mod.nu` in `dir`
/// for a command with subcommands, each laid out below it, else `<name>.nu`.
fn write_command(dir: &Path, nodes: &[KdlNode], root: bool) -> PathBuf {
    let (commands, own): (Vec<&KdlNode>, Vec<&KdlNode>) =
        nodes.iter().partition(|node| node.name().value() == "cmd");
    let mut source = String::from("#!/usr/bin/env nus\n");
    for node in own {
        for line in node.to_string().lines() {
            source.push_str("#USAGE ");
            source.push_str(line);
            source.push('\n');
        }
    }
    source.push_str("$usage\n");
    let script = if commands.is_empty() && !root {
        dir.with_extension("nu")
    } else {
        std::fs::create_dir_all(dir).unwrap();
        dir.join("mod.nu")
    };
    std::fs::write(&script, source).unwrap();
    for command in commands {
        let name = command.entries()[0].value().as_string().unwrap();
        let mut nodes: Vec<KdlNode> = command
            .children()
            .map(|children| children.nodes().to_vec())
            .unwrap_or_default();
        // The node's own properties that a header spells as nodes.
        if let Some(help) = command.get("help").and_then(|value| value.as_string()) {
            let mut about = KdlNode::new("about");
            about.push(help);
            nodes.insert(0, about);
        }
        write_command(&dir.join(name), &nodes, false);
    }
    script
}

/// `expect.ok` as the record flattens it. `cmd` is omitted for the root, where the record
/// has `[]`. A clause's instances are flattened: a positional the record holds as a list
/// collects every instance's values, any other takes the first instance's.
fn flattened(expected: &Json, bound: &Value) -> Json {
    let mut expected = expected.clone();
    let Some(object) = expected.as_object_mut() else {
        return expected;
    };
    if let Some(clauses) = object.remove("clauses") {
        let mut args = object
            .remove("args")
            .unwrap_or_else(|| Json::Object(Default::default()));
        let bound_args = bound
            .get_data_by_key("args")
            .unwrap_or_else(|| Value::nothing(nu_protocol::Span::unknown()));
        for (_, instances) in clauses.as_object().unwrap() {
            for instance in instances.as_array().unwrap() {
                for (key, value) in instance.as_object().unwrap() {
                    let collects = bound_args
                        .get_data_by_key(&nusage_model::identifier(key).var)
                        .is_some_and(|found| matches!(found, Value::List { .. }));
                    let args = args.as_object_mut().unwrap();
                    if collects {
                        let items = args
                            .entry(key.clone())
                            .or_insert_with(|| Json::Array(vec![]));
                        match value {
                            Json::Array(more) => items.as_array_mut().unwrap().extend(more.clone()),
                            other => items.as_array_mut().unwrap().push(other.clone()),
                        }
                    } else {
                        args.entry(key.clone()).or_insert_with(|| value.clone());
                    }
                }
            }
        }
        object.insert("args".into(), args);
    }
    expected
}

/// Whether `bound` holds everything `expected` has: every key, under the name the record
/// gives it, with the same value, where a count's list of booleans is the record's count
/// and the record may hold more. `Some(why)` when not.
fn holds(expected: &Json, bound: &Value, at: &str) -> Option<String> {
    match expected {
        Json::Object(fields) => {
            for (key, value) in fields {
                let name = if at.is_empty() {
                    key.clone()
                } else {
                    nusage_model::identifier(key).var
                };
                let Some(found) = bound.get_data_by_key(&name) else {
                    return Some(format!("no `{at}{name}`"));
                };
                if let Some(why) = holds(value, &found, &format!("{at}{name}.")) {
                    return Some(why);
                }
            }
            None
        }
        Json::Array(items) if items.iter().all(Json::is_boolean) && !items.is_empty() => {
            match bound {
                Value::Int { val, .. } if *val == items.len() as i64 => None,
                Value::Bool { val: true, .. } if items.len() == 1 => None,
                other => Some(format!(
                    "`{at}` is {}, expected {} occurrences",
                    nusage_nu::nuon(other),
                    items.len()
                )),
            }
        }
        Json::Array(items) => {
            let Value::List { vals, .. } = bound else {
                return Some(format!(
                    "`{at}` is {}, expected a list",
                    nusage_nu::nuon(bound)
                ));
            };
            if vals.len() != items.len() {
                return Some(format!(
                    "`{at}` is {}, expected {expected}",
                    nusage_nu::nuon(bound)
                ));
            }
            for (item, val) in items.iter().zip(vals) {
                if let Some(why) = holds(item, val, at) {
                    return Some(why);
                }
            }
            None
        }
        Json::String(text) => match bound {
            Value::String { val, .. } if val == text => None,
            other => Some(format!(
                "`{at}` is {}, expected {expected}",
                nusage_nu::nuon(other)
            )),
        },
        Json::Bool(flag) => match bound {
            Value::Bool { val, .. } if val == flag => None,
            other => Some(format!(
                "`{at}` is {}, expected {expected}",
                nusage_nu::nuon(other)
            )),
        },
        other => Some(format!("`{at}`: unexpected vector value {other}")),
    }
}

fn tempdir() -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!("nusage-corpus-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    dir
}
