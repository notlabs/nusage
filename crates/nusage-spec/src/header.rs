use std::fs;
use std::path::{Path, PathBuf};

use usage::kdl::{KdlDocument, KdlNode};

use crate::Diagnostic;

/// The usage header of one script: usage's parse of it, and what usage drops.
#[derive(Debug, Clone)]
pub struct Header {
    pub path: PathBuf,
    /// The header's KDL, the `#USAGE` lines joined.
    pub kdl: String,
    /// The top-level nodes, in header order, with their verbatim text and annotations.
    pub nodes: Vec<HeaderNode>,
    /// usage's reading of the same text. Its `cmd` is the command this file declares.
    pub spec: usage::Spec,
}

/// One top-level node of a header.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HeaderNode {
    /// The node's name: `arg`, `flag`, `output`, `about`, ...
    pub name: String,
    /// The node as written, surrounding whitespace trimmed.
    pub text: String,
    /// The node's first argument, when it is a string: `<target>`, `--dry-run`, `json`.
    pub first: Option<String>,
    /// The KDL type annotation on the first argument, which usage ignores: `(int)"<n>"`.
    pub ty: Option<String>,
    /// The annotation on a nested `arg` child's first argument, for `flag "--x" { arg (int)"<n>" }`.
    pub nested_arg_ty: Option<String>,
    /// 1-based line of the script where the node starts.
    pub line: usize,
}

impl HeaderNode {
    /// The annotation that types this node's value: a flag's nested `arg` wins over the flag
    /// itself, so both `flag (int)"--n <n>"` and `flag "--n" { arg (int)"<n>" }` work.
    pub fn value_type(&self) -> Option<&str> {
        self.nested_arg_ty.as_deref().or(self.ty.as_deref())
    }
}

/// Lines that open or continue a header. Only the `#` comment prefix: these are Nushell files.
fn header_line(line: &str) -> Option<&str> {
    line.strip_prefix("#USAGE")
        .or_else(|| line.strip_prefix("#[USAGE]"))
        .or_else(|| line.strip_prefix("# [USAGE]"))
}

fn blank_comment(line: &str) -> bool {
    line.strip_prefix('#')
        .map(|rest| rest.trim().is_empty())
        .unwrap_or(false)
}

/// The header lines of a script, each with its 1-based line number, as usage reads them: a
/// shebang first, then `#USAGE` lines, blank comment lines allowed between them, stopping at
/// the first other line.
fn extract(path: &Path, source: &str) -> Result<Vec<(usize, String)>, Diagnostic> {
    if !source.starts_with("#!") {
        return Err(Diagnostic::new(
            path,
            "a script's usage header is only read after a shebang line; add `#!/usr/bin/env nusage`",
        )
        .at_line(1));
    }
    let mut lines = Vec::new();
    let mut started = false;
    for (index, line) in source.lines().enumerate() {
        if let Some(rest) = header_line(line) {
            started = true;
            lines.push((index + 1, rest.trim().to_string()));
        } else if started {
            if blank_comment(line) {
                continue;
            }
            break;
        }
    }
    if lines.is_empty() {
        return Err(Diagnostic::new(path, "no `#USAGE` lines found").at_line(1));
    }
    Ok(lines)
}

fn string_arg(node: &KdlNode, index: usize) -> Option<String> {
    node.entries()
        .iter()
        .filter(|entry| entry.name().is_none())
        .nth(index)
        .and_then(|entry| entry.value().as_string().map(str::to_string))
}

fn first_arg_ty(node: &KdlNode) -> Option<String> {
    node.entries()
        .iter()
        .find(|entry| entry.name().is_none())
        .and_then(|entry| entry.ty().map(|ty| ty.value().to_string()))
}

fn nested_arg_ty(node: &KdlNode) -> Option<String> {
    node.children()?
        .nodes()
        .iter()
        .find(|child| child.name().value() == "arg")
        .and_then(first_arg_ty)
}

/// Read one script's header.
pub fn read_header(path: &Path) -> Result<Header, Diagnostic> {
    let source = fs::read_to_string(path)
        .map_err(|err| Diagnostic::new(path, format!("cannot read: {err}")))?;
    let lines = extract(path, &source)?;
    // Byte offset of each joined line's start, to map node spans back to script lines.
    let mut offsets = Vec::with_capacity(lines.len());
    let mut kdl = String::new();
    for (line, text) in &lines {
        offsets.push((kdl.len(), *line));
        kdl.push_str(text);
        kdl.push('\n');
    }
    let doc: KdlDocument = kdl.parse().map_err(|err| {
        Diagnostic::new(path, format!("header is not valid KDL: {err}")).at_line(lines[0].0)
    })?;
    let spec = kdl.parse::<usage::Spec>().map_err(|err| {
        Diagnostic::new(path, format!("usage rejects the header: {err}")).at_line(lines[0].0)
    })?;
    let nodes = doc
        .nodes()
        .iter()
        .map(|node| {
            let span = node.span();
            let start = span.offset();
            let end = start + span.len();
            let line = offsets
                .iter()
                .take_while(|(offset, _)| *offset <= start)
                .last()
                .map(|(_, line)| *line)
                .unwrap_or(lines[0].0);
            HeaderNode {
                name: node.name().value().to_string(),
                text: kdl[start..end].trim().to_string(),
                first: string_arg(node, 0),
                ty: first_arg_ty(node),
                nested_arg_ty: nested_arg_ty(node),
                line,
            }
        })
        .collect();
    Ok(Header {
        path: path.to_path_buf(),
        kdl,
        nodes,
        spec,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn header_of(source: &str) -> Header {
        let dir = std::env::temp_dir().join(format!("nusage-spec-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join(format!("{}.nu", source.len()));
        fs::write(&path, source).unwrap();
        read_header(&path).unwrap()
    }

    #[test]
    fn keeps_node_text_and_annotations() {
        let header = header_of(
            "#!/usr/bin/env nusage\n\
             #USAGE name \"t\"\n\
             #USAGE bin \"t\"\n\
             #USAGE arg (datetime)\"<since>\" help=\"After\"\n\
             #USAGE flag \"--limit\" default=\"10\" { arg (int)\"<n>\" }\n\
             #USAGE output (\"list<string>\")\"nuon\" default=#true\n\
             \n\
             $usage\n",
        );
        let names: Vec<_> = header.nodes.iter().map(|n| n.name.as_str()).collect();
        assert_eq!(names, ["name", "bin", "arg", "flag", "output"]);
        let arg = &header.nodes[2];
        assert_eq!(arg.text, "arg (datetime)\"<since>\" help=\"After\"");
        assert_eq!(arg.value_type(), Some("datetime"));
        assert_eq!(arg.first.as_deref(), Some("<since>"));
        assert_eq!(arg.line, 4);
        let flag = &header.nodes[3];
        assert_eq!(flag.value_type(), Some("int"));
        assert_eq!(flag.first.as_deref(), Some("--limit"));
        let output = &header.nodes[4];
        assert_eq!(output.value_type(), Some("list<string>"));
        assert_eq!(header.spec.bin, "t");
        assert_eq!(header.spec.cmd.args[0].name, "since");
    }

    #[test]
    fn needs_a_shebang() {
        let dir = std::env::temp_dir();
        let path = dir.join("nusage-spec-noshebang.nu");
        fs::write(&path, "#USAGE bin \"t\"\n").unwrap();
        let err = read_header(&path).unwrap_err();
        assert!(err.message.contains("shebang"), "{err}");
    }
}
