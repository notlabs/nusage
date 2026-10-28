//! `nusage-args`: the words that ask a binary for an output, where usage's `select` cannot
//! say them. usage reads one switch whose presence picks the output, or a flag whose value is
//! the output's name; jj is asked for its JSON with `--no-graph --template 'json(self) ++
//! "\n"'`, which is neither. The node is a child of the `output` and holds any words:
//!
//! ```kdl
//! cmd "log" {
//!     output "json" framing="jsonl" {
//!         nusage-args "--no-graph" "--template" #"json(self) ++ "\n""#
//!     }
//! }
//! ```
//!
//! usage rejects a node it does not know inside an `output`, so the node is taken out of the
//! document before usage reads it, and kept beside the spec.

use std::collections::BTreeMap;
use std::path::Path;

use usage::kdl::{KdlDocument, KdlNode};

use crate::{CommandPath, Diagnostic};

/// The node's name.
pub const NODE: &str = "nusage-args";

/// Each command's outputs' words, by output name.
pub type OutputArgs = BTreeMap<CommandPath, BTreeMap<String, Vec<String>>>;

/// Take every `nusage-args` out of `doc`'s `output` nodes, the top level's and each `cmd`'s,
/// and return their words by command and output.
pub(crate) fn lift(doc: &mut KdlDocument, file: &Path) -> Result<OutputArgs, Diagnostic> {
    let mut found = OutputArgs::new();
    lift_level(doc.nodes_mut(), &CommandPath::root(), file, &mut found)?;
    Ok(found)
}

fn lift_level(
    nodes: &mut [KdlNode],
    path: &CommandPath,
    file: &Path,
    found: &mut OutputArgs,
) -> Result<(), Diagnostic> {
    for node in nodes {
        match node.name().value() {
            "cmd" => {
                let Some(name) = first_arg(node) else {
                    continue;
                };
                let path = path.child(&name);
                if let Some(children) = node.children_mut() {
                    lift_level(children.nodes_mut(), &path, file, found)?;
                }
            }
            "output" => {
                let Some(output) = first_arg(node) else {
                    continue;
                };
                let Some(words) = lift_output(node, file, path, &output)? else {
                    continue;
                };
                found.entry(path.clone()).or_default().insert(output, words);
            }
            _ => {}
        }
    }
    Ok(())
}

/// The output's words, with the node taken out; an `output` left with no children has its
/// block removed too, since `output "json" {}` is not what was written.
fn lift_output(
    output: &mut KdlNode,
    file: &Path,
    path: &CommandPath,
    name: &str,
) -> Result<Option<Vec<String>>, Diagnostic> {
    let Some(children) = output.children_mut() else {
        return Ok(None);
    };
    let at = |what: &str| {
        let command = if path.is_root() {
            String::new()
        } else {
            format!("`{path}`: ")
        };
        Diagnostic::new(file, format!("{command}output `{name}`: {what}"))
    };
    // A node's leading whitespace is its place in the text, the line break before it
    // included; the node after one taken out takes its place, so the text still reads as
    // written, which matters since a node's text rides along as the wrapper's attribute.
    let nodes = children.nodes_mut();
    let mut lifted = Vec::new();
    let mut kept = Vec::new();
    let mut place: Option<String> = None;
    for mut node in nodes.drain(..) {
        if node.name().value() == NODE {
            if place.is_none() {
                place = node.format().map(|format| format.leading.clone());
            }
            lifted.push(node);
        } else {
            if let (Some(leading), Some(format)) = (place.take(), node.format_mut()) {
                format.leading = leading;
            }
            kept.push(node);
        }
    }
    *nodes = kept;
    if nodes.is_empty() {
        output.clear_children();
    }
    let [node] = lifted.as_slice() else {
        return if lifted.is_empty() {
            Ok(None)
        } else {
            Err(at(&format!("`{NODE}` is declared more than once")))
        };
    };
    if node.children().is_some() {
        return Err(at(&format!("`{NODE}` takes words, not children")));
    }
    let mut words = Vec::new();
    for entry in node.entries() {
        match (entry.name(), entry.value().as_string()) {
            (None, Some(word)) => words.push(word.to_string()),
            (Some(key), _) => {
                return Err(at(&format!(
                    "`{NODE}` takes words, not a property `{}`",
                    key.value()
                )));
            }
            (None, None) => {
                return Err(at(&format!(
                    "`{NODE}` takes strings; `{}` is not one",
                    entry.value()
                )));
            }
        }
    }
    if words.is_empty() {
        return Err(at(&format!("`{NODE}` names no words")));
    }
    Ok(Some(words))
}

fn first_arg(node: &KdlNode) -> Option<String> {
    node.entries()
        .iter()
        .find(|entry| entry.name().is_none())
        .and_then(|entry| entry.value().as_string().map(str::to_string))
}

/// The flag a word names, without its dashes or an `=value`: `--template=x` names
/// `template`, `-T` names `T`; a word that is a value names none.
pub fn flag_word(word: &str) -> Option<&str> {
    let name = word.strip_prefix('-')?;
    let name = name.strip_prefix('-').unwrap_or(name);
    let name = name.split_once('=').map_or(name, |(name, _)| name);
    (!name.is_empty()).then_some(name)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lifted(text: &str) -> (OutputArgs, String) {
        let mut doc: KdlDocument = text.parse().unwrap();
        let found = lift(&mut doc, Path::new("spec.kdl")).unwrap();
        (found, doc.to_string())
    }

    #[test]
    fn the_words_are_taken_out_of_their_output() {
        let (found, rest) = lifted(
            r##"cmd "op" {
    cmd "log" {
        output "json" framing="jsonl" {
            nusage-args "--no-graph" "-T" #"json(self) ++ "\n""#
            schema "{}"
        }
    }
}
output "text" default=#true {
    nusage-args "--plain"
}
"##,
        );
        let op_log = CommandPath::root().child("op").child("log");
        assert_eq!(
            found[&op_log]["json"],
            ["--no-graph", "-T", "json(self) ++ \"\\n\""]
        );
        assert_eq!(found[&CommandPath::root()]["text"], ["--plain"]);
        assert!(!rest.contains(NODE), "{rest}");
        assert!(
            rest.contains("framing=\"jsonl\" {\n            schema \"{}\"\n"),
            "{rest}"
        );
        // An output whose only child was the words has no block left to read as one.
        assert!(rest.ends_with("output \"text\" default=#true\n"), "{rest}");
    }

    #[test]
    fn the_node_takes_words_alone() {
        for (text, why) in [
            (r#"output "j" { nusage-args; }"#, "names no words"),
            (r#"output "j" { nusage-args 1; }"#, "takes strings"),
            (r#"output "j" { nusage-args a=b; }"#, "not a property"),
            (
                r#"output "j" { nusage-args "-a"; nusage-args "-b"; }"#,
                "more than once",
            ),
        ] {
            let mut doc: KdlDocument = text.parse().unwrap();
            let err = lift(&mut doc, Path::new("spec.kdl")).unwrap_err();
            assert!(err.to_string().contains(why), "{text}: {err}");
        }
    }

    #[test]
    fn a_word_names_a_flag_by_its_dashes() {
        assert_eq!(flag_word("--template"), Some("template"));
        assert_eq!(flag_word("--template=json(self)"), Some("template"));
        assert_eq!(flag_word("-T"), Some("T"));
        assert_eq!(flag_word("json(self)"), None);
        assert_eq!(flag_word("-"), None);
    }
}
