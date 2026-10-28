//! An overlay for a CLI whose commands share a switch that selects a framed output, such as
//! `--json`, and whose spec declares no `output`: for every command with the switch, one
//! framed output the switch selects.

use usage::kdl::{KdlDocument, KdlEntry, KdlNode};
use usage::{Spec, SpecCommand};

/// The overlay as usage KDL. A command already declaring an output the switch selects is
/// left alone; the root's output goes at the top level, a subcommand's inside its `cmd`.
pub fn switch_overlay(spec: &Spec, switch: &str, framing: &str) -> String {
    let mut doc = KdlDocument::new();
    if wants_output(&spec.cmd, &spec.outputs, switch) {
        doc.nodes_mut().push(output_node(switch, framing));
    }
    for (name, sub) in &spec.cmd.subcommands {
        if let Some(node) = command_node(name, sub, switch, framing) {
            doc.nodes_mut().push(node);
        }
    }
    doc.autoformat();
    doc.to_string()
}

/// `cmd "name" { ... }` with the output and any subcommands that want one; `None` when
/// nothing below wants one.
fn command_node(name: &str, cmd: &SpecCommand, switch: &str, framing: &str) -> Option<KdlNode> {
    let mut children = Vec::new();
    if wants_output(cmd, &cmd.outputs, switch) {
        children.push(output_node(switch, framing));
    }
    for (name, sub) in &cmd.subcommands {
        children.extend(command_node(name, sub, switch, framing));
    }
    if children.is_empty() {
        return None;
    }
    let mut node = KdlNode::new("cmd");
    node.push(KdlEntry::new(name));
    node.ensure_children().nodes_mut().extend(children);
    Some(node)
}

fn wants_output(cmd: &SpecCommand, outputs: &[usage::SpecOutput], switch: &str) -> bool {
    let long = switch.trim_start_matches('-');
    let has_switch = cmd
        .flags
        .iter()
        .any(|flag| flag.arg.is_none() && flag.long.iter().any(|l| l == long));
    let declared = outputs
        .iter()
        .any(|output| output.select.as_deref() == Some(switch));
    has_switch && !declared
}

fn output_node(switch: &str, framing: &str) -> KdlNode {
    let mut node = KdlNode::new("output");
    node.push(KdlEntry::new(framing));
    node.push(KdlEntry::new_prop("framing", framing));
    node.push(KdlEntry::new_prop("select", switch));
    node
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_command_with_the_switch_gets_an_output() {
        let spec: Spec = r#"
name "tool"
bin "tool"
flag "-J --json"
cmd "ls" { flag "-J --json" }
cmd "rm" { flag "--force" }
cmd "tasks" { cmd "ls" { flag "--json" } }
cmd "done" { flag "--json"; output "json" framing="json" select="--json" }
"#
        .parse()
        .unwrap();
        let overlay = switch_overlay(&spec, "--json", "json");
        let expected = r#"output json framing=json select=--json
cmd ls {
    output json framing=json select=--json
}
cmd tasks {
    cmd ls {
        output json framing=json select=--json
    }
}
"#;
        assert_eq!(overlay, expected);
    }
}
