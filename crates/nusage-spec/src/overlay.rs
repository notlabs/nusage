//! An overlay: a usage KDL document merged onto a spec's document before usage reads it,
//! so a spec one does not own, such as what a binary prints for `tool usage`, can be given
//! what it lacks: `output` declarations, a `select`, type annotations on arguments.
//!
//! usage itself has no merge: a redeclared `cmd` replaces the earlier one, and a `select`
//! naming a flag the overlay does not repeat is rejected. Merging at the node level, before
//! usage parses, keeps the overlay in usage's grammar and lets usage validate the whole.

use usage::kdl::{KdlDocument, KdlNode};

/// Merge `overlay` into `base`. A `cmd` merges into the `cmd` of the same name, its
/// properties over the base's and its children recursively, or is added when there is none.
/// Any other node replaces the base node with the same name and the same first argument, or
/// is added; an `include` is always added.
pub(crate) fn merge(base: &mut KdlDocument, overlay: &KdlDocument) {
    merge_nodes(base.nodes_mut(), overlay.nodes());
}

fn merge_nodes(base: &mut Vec<KdlNode>, overlay: &[KdlNode]) {
    for node in overlay {
        let name = node.name().value();
        let first = first_arg(node);
        let same =
            |candidate: &KdlNode| candidate.name().value() == name && first_arg(candidate) == first;
        if name == "cmd" {
            if let Some(target) = base.iter_mut().find(|candidate| same(candidate)) {
                for entry in node.entries().iter().filter(|entry| entry.name().is_some()) {
                    let key = entry
                        .name()
                        .map(|k| k.value().to_string())
                        .unwrap_or_default();
                    match target.entry_mut(key.as_str()) {
                        Some(existing) => *existing = entry.clone(),
                        None => target.push(entry.clone()),
                    }
                }
                if let Some(children) = node.children() {
                    merge_nodes(target.ensure_children().nodes_mut(), children.nodes());
                }
                continue;
            }
        } else if name != "include"
            && let Some(position) = base.iter().position(same)
        {
            base[position] = node.clone();
            continue;
        }
        base.push(node.clone());
    }
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
}
