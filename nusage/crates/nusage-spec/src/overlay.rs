//! An overlay: a usage KDL document merged onto a spec's document before usage reads it,
//! so a spec one does not own, such as what a binary prints for `tool usage`, can be given
//! what it lacks: `output` declarations, a `select`, type annotations on arguments, a
//! `decode` pipeline on an output.
//!
//! usage itself has no merge: a redeclared `cmd` replaces the earlier one, and a `select`
//! naming a flag the overlay does not repeat is rejected. Merging at the node level, before
//! usage parses, keeps the overlay in usage's grammar and lets usage validate the whole.

use usage::kdl::{KdlDocument, KdlDocumentFormat, KdlNode, KdlNodeFormat};

/// Merge `overlay` into `base`. A node merges into the base node with the same name and
/// the same first argument: the overlay's arguments, annotations included, replace the
/// base's, its properties go over the base's, and its children merge recursively; a node
/// with no counterpart is added, and an `include` always is. So an overlay that states only
/// a type on an output keeps the output's framing and selector.
pub(crate) fn merge(base: &mut KdlDocument, overlay: &KdlDocument) {
    merge_nodes(base.nodes_mut(), overlay.nodes());
}

fn merge_nodes(base: &mut Vec<KdlNode>, overlay: &[KdlNode]) {
    for node in overlay {
        let name = node.name().value();
        let first = first_arg(node);
        let same =
            |candidate: &KdlNode| candidate.name().value() == name && first_arg(candidate) == first;
        let target = if name == "include" {
            None
        } else {
            base.iter_mut().find(|candidate| same(candidate))
        };
        let Some(target) = target else {
            base.push(node.clone());
            continue;
        };
        // Arguments as a whole from the overlay, when it gives any: that is where a type
        // annotation sits. Properties one by one over the base's.
        let (args, props): (Vec<_>, Vec<_>) = node
            .entries()
            .iter()
            .cloned()
            .partition(|entry| entry.name().is_none());
        if !args.is_empty() {
            let mut entries = args;
            entries.extend(
                target
                    .entries()
                    .iter()
                    .filter(|entry| entry.name().is_some())
                    .cloned(),
            );
            *target.entries_mut() = entries;
        }
        for entry in props {
            let key = entry
                .name()
                .map(|k| k.value().to_string())
                .unwrap_or_default();
            match target.entry_mut(key.as_str()) {
                Some(existing) => *existing = entry,
                None => target.push(entry),
            }
        }
        if let Some(children) = node.children() {
            let opened = target.children().is_none();
            merge_nodes(target.ensure_children().nodes_mut(), children.nodes());
            if opened {
                open_block(target);
            }
        }
    }
}

/// Lay out a block the overlay opened on a node that had none, as it would be written: a
/// space before `{`, each child on its own line indented by four, `}` on its own. The node's
/// text is what a module carries as an attribute, and the children brought the whitespace
/// of the overlay file with them.
fn open_block(node: &mut KdlNode) {
    if let Some(format) = node.format_mut() {
        format.before_children = " ".into();
    }
    let children = node.ensure_children();
    for child in children.nodes_mut() {
        child.set_format(KdlNodeFormat {
            leading: "    ".into(),
            terminator: "\n".into(),
            ..Default::default()
        });
    }
    children.set_format(KdlDocumentFormat {
        leading: "\n".into(),
        trailing: String::new(),
    });
}

fn first_arg(node: &KdlNode) -> Option<String> {
    node.entries()
        .iter()
        .find(|entry| entry.name().is_none())
        .and_then(|entry| entry.value().as_string().map(str::to_string))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_block_the_overlay_opens_reads_as_written() {
        let mut base: KdlDocument = "cmd \"ls\" {\n    output \"text\" default=#true\n}\n"
            .parse()
            .unwrap();
        let overlay: KdlDocument = r#"
cmd "ls" {
    output ("table<name: string>")"text" default=#true {
        decode "lines | parse \"{name}\""
    }
}
"#
        .parse()
        .unwrap();
        merge(&mut base, &overlay);
        let output = base.nodes()[0].children().unwrap().nodes()[0].to_string();
        assert_eq!(
            output.trim(),
            "output (\"table<name: string>\")\"text\" default=#true {\n    decode \"lines | parse \\\"{name}\\\"\"\n}"
        );
    }

    #[test]
    fn commands_merge_and_other_nodes_replace_by_name_and_first_argument() {
        let mut base: KdlDocument = r#"
name "tool"
about "Old"
cmd "ls" help="List" {
    flag "-J --json"
    arg "[name]" help="Only this"
}
"#
        .parse()
        .unwrap();
        let overlay: KdlDocument = r#"
about "New"
cmd "ls" help="List things" {
    arg ("string")"[name]" help="Only this, by name"
    output "json" framing="json" select="--json"
}
cmd "rm" {
    arg "<name>"
}
"#
        .parse()
        .unwrap();
        merge(&mut base, &overlay);
        let spec: usage::Spec = base.to_string().parse().unwrap();
        assert_eq!(spec.about.as_deref(), Some("New"));
        let ls = &spec.cmd.subcommands["ls"];
        assert_eq!(ls.help.as_deref(), Some("List things"));
        assert_eq!(ls.flags.len(), 1, "the base flag survives");
        assert_eq!(ls.args.len(), 1, "the argument is replaced, not duplicated");
        assert_eq!(ls.args[0].help.as_deref(), Some("Only this, by name"));
        assert_eq!(ls.outputs.len(), 1);
        assert!(spec.cmd.subcommands.contains_key("rm"));
    }

    #[test]
    fn an_overlay_that_states_only_a_type_keeps_the_rest_of_the_node() {
        let mut base: KdlDocument = r#"
cmd "ls" {
    flag "-J --json"
    output "json" framing="json" select="--json" help="Rows"
}
"#
        .parse()
        .unwrap();
        let overlay: KdlDocument = r#"
cmd "ls" {
    output ("table<name: string>")"json"
}
"#
        .parse()
        .unwrap();
        merge(&mut base, &overlay);
        let text = base.to_string();
        assert!(
            text.contains(
                r#"output ("table<name: string>")"json" framing="json" select="--json" help="Rows""#
            ),
            "{text}"
        );
    }
}
