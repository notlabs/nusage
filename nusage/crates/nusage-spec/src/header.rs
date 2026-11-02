use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

use usage::kdl::{KdlDocument, KdlNode};

use crate::Diagnostic;

/// What one command declares, beyond what usage's parse of it keeps: its nodes as written,
/// their type annotations, and its description.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Header {
    /// The file the declaration came from: the script, or the spec file.
    pub path: PathBuf,
    /// The command's own nodes, in order, with their verbatim text and annotations. For a
    /// script this is the whole header; for a `cmd` node of a spec file, its children other
    /// than nested `cmd`s.
    pub nodes: Vec<HeaderNode>,
    /// usage `about` or a `cmd`'s `help`: the description.
    pub about: Option<String>,
    /// usage `long_about`: the extra description.
    pub about_long: Option<String>,
}

/// One node of a declaration.
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
    /// An `output`'s `nusage-decode` child: the Nushell pipeline that turns the output's text
    /// into a value, as written, for an output no `from` reader decodes. nusage's own node,
    /// named as `nusage-args` is so that usage's grammar can grow without a collision, taken
    /// out before usage reads the spec.
    pub decode: Option<String>,
    /// 1-based line of the file where the node starts.
    pub line: usize,
}

impl HeaderNode {
    /// The annotation that types this node's value: a flag's nested `arg` wins over the flag
    /// itself, so both `flag (int)"--n <n>"` and `flag "--n" { arg (int)"<n>" }` work.
    pub fn value_type(&self) -> Option<&str> {
        self.nested_arg_ty.as_deref().or(self.ty.as_deref())
    }
}

/// A script's header: the declaration plus usage's reading of the same text.
#[derive(Debug, Clone)]
pub struct ScriptHeader {
    pub header: Header,
    /// The header's KDL, the `#USAGE` lines joined.
    pub kdl: String,
    /// usage's parse: the whole spec for a root script; for a subcommand's, the spec that
    /// wraps its header in a `cmd`, which [`ScriptHeader::cmd`] is taken from.
    pub spec: usage::Spec,
    /// The command this file declares: its args, flags, outputs, and for a subcommand its
    /// `alias` and `hide` too.
    pub cmd: usage::SpecCommand,
    /// The declarations of the commands the spec's own `cmd` nodes declare below this one,
    /// by their path under it.
    pub nested: BTreeMap<crate::CommandPath, Header>,
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
/// the first other line. Another tool's directives belong before the first `#USAGE` line,
/// where usage passes over them too.
fn extract(path: &Path, source: &str) -> Result<Vec<(usize, String)>, Diagnostic> {
    if !source.starts_with("#!") {
        return Err(Diagnostic::new(
            path,
            "a script's usage header is only read after a shebang line; add `#!/usr/bin/env nus`",
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
    // No lines is a command with no parameters.
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

/// The name of the child node that states how an output is decoded.
pub(crate) const DECODE: &str = "nusage-decode";

fn decode_of(node: &KdlNode) -> Option<String> {
    if node.name().value() != "output" {
        return None;
    }
    node.children()?
        .nodes()
        .iter()
        .find(|child| child.name().value() == DECODE)
        .and_then(|child| string_arg(child, 0))
}

/// Take every output's `nusage-decode` child out of the document, so that usage, which knows no
/// such node, reads the rest. Whether any was there.
pub(crate) fn strip_decodes(doc: &mut KdlDocument) -> bool {
    let mut stripped = false;
    for node in doc.nodes_mut() {
        if node.name().value() == "output"
            && let Some(children) = node.children_mut()
        {
            let before = children.nodes().len();
            children
                .nodes_mut()
                .retain(|child| child.name().value() != DECODE);
            stripped |= children.nodes().len() != before;
        }
        if let Some(children) = node.children_mut() {
            stripped |= strip_decodes(children);
        }
    }
    stripped
}

/// The [`HeaderNode`] of a parsed node, with `text` sliced from the source it was parsed
/// from and `line` looked up through `line_of`.
pub(crate) fn header_node(
    node: &KdlNode,
    source: &str,
    line_of: impl Fn(usize) -> usize,
) -> HeaderNode {
    let span = node.span();
    let start = span.offset();
    let end = start + span.len();
    HeaderNode {
        name: node.name().value().to_string(),
        text: source[start..end].trim().to_string(),
        first: string_arg(node, 0),
        ty: first_arg_ty(node),
        nested_arg_ty: nested_arg_ty(node),
        decode: decode_of(node),
        line: line_of(start),
    }
}

/// Text to read in place of what a file holds on disk, by the file's path: what an editor
/// has open and not yet saved.
pub type Texts = BTreeMap<PathBuf, String>;

/// Read a root script's header: a usage spec, as its `#USAGE` lines spell it.
pub fn read_header(path: &Path) -> Result<ScriptHeader, Diagnostic> {
    read(path, None, &Texts::new())
}

/// [`read_header`], from the text `texts` holds for the path when it holds one.
pub fn read_header_in(path: &Path, texts: &Texts) -> Result<ScriptHeader, Diagnostic> {
    read(path, None, texts)
}

/// Read a subcommand script's header: what a `cmd "<name>" { }` holds, as its `#USAGE`
/// lines spell it, `about` and `long_about` standing for the command's `help` and
/// `long_help`, so a subcommand declares what usage lets a command declare, an `alias` or
/// `hide` included.
pub fn read_subcommand_header(path: &Path, name: &str) -> Result<ScriptHeader, Diagnostic> {
    read(path, Some(name), &Texts::new())
}

pub(crate) fn read_subcommand_header_in(
    path: &Path,
    name: &str,
    texts: &Texts,
) -> Result<ScriptHeader, Diagnostic> {
    read(path, Some(name), texts)
}

/// usage's spec beside a script, `.<file name>.usage.kdl`, which usage reads in place of the
/// script's header; with its text, as `texts` holds it or as it is on disk.
pub fn sidecar(script: &Path, texts: &Texts) -> Option<(PathBuf, String)> {
    let name = script.file_name()?.to_str()?;
    let file = script.with_file_name(format!(".{name}.usage.kdl"));
    if let Some(text) = texts.get(&file) {
        return Some((file, text.clone()));
    }
    let text = fs::read_to_string(&file).ok()?;
    Some((file, text))
}

fn read(path: &Path, subcommand: Option<&str>, texts: &Texts) -> Result<ScriptHeader, Diagnostic> {
    let source = match texts.get(path) {
        Some(text) => text.clone(),
        None => fs::read_to_string(path)
            .map_err(|err| Diagnostic::new(path, format!("cannot read: {err}")))?,
    };
    let header = extract(path, &source)?;
    // As usage reads a script: the hidden spec beside it when there is one, in place of its
    // header, else its header. Either is read with its own path, which a relative `include`
    // is relative to.
    let (spec_path, lines) = match sidecar(path, texts) {
        Some((file, text)) => {
            let lines = text
                .lines()
                .enumerate()
                .map(|(index, line)| (index + 1, line.to_string()))
                .collect();
            (file, lines)
        }
        None => (path.to_path_buf(), header),
    };
    let path = spec_path.as_path();
    // Byte offset of each joined line's start, to map node spans back to script lines.
    let mut offsets = Vec::with_capacity(lines.len());
    let mut kdl = String::new();
    for (line, text) in &lines {
        offsets.push((kdl.len(), *line));
        kdl.push_str(text);
        kdl.push('\n');
    }
    let first_line = lines.first().map(|(line, _)| *line).unwrap_or(1);
    let mut doc: KdlDocument = kdl.parse().map_err(|err| {
        Diagnostic::new(path, format!("header is not valid KDL: {err}")).at_line(first_line)
    })?;
    let line_of = |offset: usize| {
        offsets
            .iter()
            .take_while(|(start, _)| *start <= offset)
            .last()
            .map(|(_, line)| *line)
            .unwrap_or(first_line)
    };
    let nodes = doc
        .nodes()
        .iter()
        .map(|node| header_node(node, &kdl, line_of))
        .collect();
    let rejected = |err: usage::error::UsageErr| {
        Diagnostic::new(path, format!("usage rejects the header: {err}")).at_line(first_line)
    };
    let (spec, cmd, about, about_long) = match subcommand {
        None => {
            let mut spec = usage::Spec::parse_str_with_path(&kdl, path).map_err(rejected)?;
            // A name usage takes from the file is the sidecar's; the script's is the default.
            let file_name = path.file_name().and_then(|name| name.to_str()).unwrap_or("");
            for field in [&mut spec.name, &mut spec.bin] {
                if field == file_name {
                    field.clear();
                }
            }
            let cmd = spec.cmd.clone();
            let (about, about_long) = (spec.about.clone(), spec.about_long.clone());
            (spec, cmd, about, about_long)
        }
        Some(name) => {
            for node in doc.nodes_mut() {
                match node.name().value() {
                    "about" => node.set_name("help"),
                    "long_about" => node.set_name("long_help"),
                    _ => {}
                }
            }
            let wrapped = format!("name \"_\"\nbin \"_\"\ncmd {name:?} {{\n{doc}}}\n");
            let spec = usage::Spec::parse_str_with_path(&wrapped, path).map_err(rejected)?;
            let cmd = spec.cmd.subcommands.get(name).cloned().ok_or_else(|| {
                Diagnostic::new(path, "usage did not read the header as a command")
            })?;
            let (about, about_long) = (cmd.help.clone(), cmd.help_long.clone());
            (spec, cmd, about, about_long)
        }
    };
    let mut nested = BTreeMap::new();
    crate::tree::collect_cmd_headers(
        doc.nodes(),
        &crate::CommandPath::root(),
        &cmd,
        path,
        &kdl,
        &line_of,
        &mut nested,
    )?;
    Ok(ScriptHeader {
        header: Header {
            path: path.to_path_buf(),
            nodes,
            about,
            about_long,
        },
        kdl,
        spec,
        cmd,
        nested,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dir_of(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("nusage-spec-{name}-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    /// As usage reads a script: the hidden spec beside it, in place of its header, which
    /// declarations then name; and a relative `include` in either, from the file it is in.
    #[test]
    fn a_sidecar_stands_in_for_the_header_and_includes_are_relative() {
        let dir = dir_of("sidecar");
        let script = dir.join("greet.nu");
        fs::write(&script, "#!/usr/bin/env nus\n#USAGE arg \"<ignored>\"\n$usage\n").unwrap();
        fs::write(dir.join("common.kdl"), "flag \"--loud\"\n").unwrap();
        let sidecar = dir.join(".greet.nu.usage.kdl");
        fs::write(&sidecar, "arg (int)\"<times>\"\ninclude file=\"common.kdl\"\n").unwrap();
        let read = read_header(&script).unwrap();
        assert_eq!(read.header.path, sidecar);
        assert_eq!(read.cmd.args.iter().map(|a| a.name.as_str()).collect::<Vec<_>>(), ["times"]);
        assert_eq!(read.header.nodes[0].value_type(), Some("int"));
        assert!(read.cmd.flags.iter().any(|f| f.name == "loud"));
        assert!(read.spec.name.is_empty(), "{}", read.spec.name);
        fs::remove_file(&sidecar).unwrap();
        fs::write(&script, "#!/usr/bin/env nus\n#USAGE include file=\"common.kdl\"\n$usage\n").unwrap();
        let read = read_header(&script).unwrap();
        assert_eq!(read.header.path, script);
        assert!(read.cmd.flags.iter().any(|f| f.name == "loud"));
        fs::remove_dir_all(dir).unwrap();
    }

    fn header_of(source: &str) -> ScriptHeader {
        let dir = std::env::temp_dir().join(format!("nusage-spec-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join(format!("{}.nu", source.len()));
        fs::write(&path, source).unwrap();
        read_header(&path).unwrap()
    }

    #[test]
    fn keeps_node_text_and_annotations() {
        let script = header_of(
            "#!/usr/bin/env nus\n\
             #USAGE name \"t\"\n\
             #USAGE bin \"t\"\n\
             #USAGE about \"Test\"\n\
             #USAGE arg (datetime)\"<since>\" help=\"After\"\n\
             #USAGE flag \"--limit\" default=\"10\" { arg (int)\"<n>\" }\n\
             #USAGE output (\"list<string>\")\"nuon\" default=#true\n\
             \n\
             $usage\n",
        );
        let header = &script.header;
        let names: Vec<_> = header.nodes.iter().map(|n| n.name.as_str()).collect();
        assert_eq!(names, ["name", "bin", "about", "arg", "flag", "output"]);
        let arg = &header.nodes[3];
        assert_eq!(arg.text, "arg (datetime)\"<since>\" help=\"After\"");
        assert_eq!(arg.value_type(), Some("datetime"));
        assert_eq!(arg.first.as_deref(), Some("<since>"));
        assert_eq!(arg.line, 5);
        let flag = &header.nodes[4];
        assert_eq!(flag.value_type(), Some("int"));
        assert_eq!(flag.first.as_deref(), Some("--limit"));
        let output = &header.nodes[5];
        assert_eq!(output.value_type(), Some("list<string>"));
        assert_eq!(header.about.as_deref(), Some("Test"));
        assert_eq!(script.spec.bin, "t");
        assert_eq!(script.spec.cmd.args[0].name, "since");
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
