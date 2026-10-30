use std::collections::BTreeMap;
use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};

use usage::SpecCommand;
use usage::kdl::{KdlDocument, KdlNode};

use crate::args::OutputArgs;
use crate::header::{header_node, read_header_in, read_subcommand_header_in, strip_decodes};
use crate::{Diagnostic, Header, Texts};

/// A command's place in the tree: subcommand names outermost first, empty at the root.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Default, serde::Serialize)]
pub struct CommandPath(pub Vec<String>);

impl CommandPath {
    pub fn root() -> Self {
        Self(Vec::new())
    }

    pub fn child(&self, name: &str) -> Self {
        let mut words = self.0.clone();
        words.push(name.to_string());
        Self(words)
    }

    pub fn is_root(&self) -> bool {
        self.0.is_empty()
    }

    pub fn words(&self) -> &[String] {
        &self.0
    }
}

impl fmt::Display for CommandPath {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0.join(" "))
    }
}

/// A `choices run="./x.nu"` that names a script in the tree: that script's command supplies
/// the completions for the parameter.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Provider {
    /// The command whose parameter is completed.
    pub consumer: CommandPath,
    /// The usage name of the arg or flag.
    pub param: String,
    /// The command that provides the values.
    pub provider: CommandPath,
}

/// What runs when a command is called.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Source {
    /// Scripts: each command's body is a file.
    Scripts {
        bodies: BTreeMap<CommandPath, PathBuf>,
    },
    /// A binary described by a spec file; Nushell runs it from `PATH`.
    Binary,
}

/// A script, a tree of scripts, or a spec file, as one usage spec plus what the spec cannot
/// hold.
#[derive(Debug, Clone)]
pub struct Assembled {
    /// The whole command tree. A valid usage spec, so every usage tool can read it.
    pub spec: usage::Spec,
    pub source: Source,
    /// Each command's declaration, for its node text and annotations.
    pub headers: BTreeMap<CommandPath, Header>,
    /// Completion providers resolved to commands in the tree.
    pub providers: Vec<Provider>,
    /// The words that ask for an output where usage's `select` cannot say them: each
    /// `nusage-args`, by the command whose `output` declared it.
    pub output_args: OutputArgs,
    /// The HTTP mapping, when the spec describes a service: what each command's call sends.
    pub http: Option<crate::http::Http>,
}

impl Assembled {
    /// The script that is the command's body, when the source is scripts.
    pub fn body(&self, path: &CommandPath) -> Option<&Path> {
        match &self.source {
            Source::Scripts { bodies } => bodies.get(path).map(PathBuf::as_path),
            Source::Binary => None,
        }
    }

    /// The words that ask the command at `path` for its output `name`: the `nusage-args` of
    /// the nearest command declaring them, the command's own or an ancestor's, as an output
    /// a command declares is every command's under it.
    pub fn output_args(&self, path: &CommandPath, name: &str) -> Option<&[String]> {
        let mut words = path.words().to_vec();
        loop {
            if let Some(found) = self
                .output_args
                .get(&CommandPath(words.clone()))
                .and_then(|outputs| outputs.get(name))
            {
                return Some(found);
            }
            words.pop()?;
        }
    }
}

/// Assemble a single script, a directory whose `mod.nu` is the root and whose files and
/// subdirectories (each with its own `mod.nu`) are its subcommands, or a `.kdl` spec file
/// describing a binary.
pub fn assemble(source: &Path) -> Result<Assembled, Diagnostic> {
    assemble_with(source, &[])
}

/// [`assemble`], with overlays merged onto a spec file before usage reads it: each is a usage
/// KDL document whose nodes are added to the spec's, a `cmd` merging into the command of the
/// same name and any other node replacing the one with the same name and first argument.
/// Scripts take no overlay; their headers are their own.
pub fn assemble_with(source: &Path, overlays: &[PathBuf]) -> Result<Assembled, Diagnostic> {
    assemble_from(source, overlays, &Texts::new())
}

/// [`assemble_with`], for a spec file that describes a service rather than a binary: the
/// HTTP mapping at `http`, `<name>.http.kdl` as `openapi-usage` writes it beside the spec,
/// says what each command's call sends. See [`crate::http`].
pub fn assemble_http(
    source: &Path,
    overlays: &[PathBuf],
    http: &Path,
) -> Result<Assembled, Diagnostic> {
    let mut assembled = assemble_from(source, overlays, &Texts::new())?;
    if !matches!(assembled.source, Source::Binary) {
        return Err(Diagnostic::new(
            http,
            "an HTTP mapping goes with a spec file; scripts have nothing to map",
        ));
    }
    assembled.http = Some(crate::http::read_http(http)?);
    Ok(assembled)
}

/// [`assemble`] for a script or a tree, reading each script from the text `texts` holds for
/// it when it holds one: as an editor has the scripts, saved or not.
pub fn assemble_in(source: &Path, texts: &Texts) -> Result<Assembled, Diagnostic> {
    assemble_from(source, &[], texts)
}

fn assemble_from(
    source: &Path,
    overlays: &[PathBuf],
    texts: &Texts,
) -> Result<Assembled, Diagnostic> {
    if source.is_file() {
        return if source.extension().and_then(|ext| ext.to_str()) == Some("kdl") {
            assemble_spec_file(source, overlays)
        } else if let Some(overlay) = overlays.first() {
            Err(Diagnostic::new(
                overlay,
                "an overlay applies to a spec file; a script declares its own header",
            ))
        } else {
            assemble_single(source, texts)
        };
    }
    if let Some(overlay) = overlays.first() {
        return Err(Diagnostic::new(
            overlay,
            "an overlay applies to a spec file; scripts declare their own headers",
        ));
    }
    if !source.is_dir() {
        return Err(Diagnostic::new(source, "not a file or a directory"));
    }
    let mut bodies = BTreeMap::new();
    let mut headers = BTreeMap::new();
    let root = CommandPath::root();
    let root_header = group_header(source, texts)?;
    reject_mounts(&root_header.header)?;
    let mut spec = root_header.spec.clone();
    if spec.name.is_empty() {
        let name = dir_name(source)?;
        spec.name = name.clone();
        spec.bin = name;
    }
    spec.cmd.name = spec.bin.clone();
    spec.cmd.subcommands = children(source, &root, &mut bodies, &mut headers, texts)?;
    bodies.insert(root.clone(), source.join("mod.nu"));
    headers.insert(root, root_header.header);
    spec.restamp();
    fill_headers(
        &spec.cmd,
        &CommandPath::root(),
        &source.join("mod.nu"),
        &mut headers,
    );
    let mut out = Assembled {
        spec,
        source: Source::Scripts { bodies },
        headers,
        providers: Vec::new(),
        output_args: OutputArgs::new(),
        http: None,
    };
    resolve_providers(&mut out)?;
    Ok(out)
}

fn assemble_single(path: &Path, texts: &Texts) -> Result<Assembled, Diagnostic> {
    let script = read_header_in(path, texts)?;
    reject_mounts(&script.header)?;
    let mut spec = script.spec.clone();
    if spec.name.is_empty() {
        let stem = file_stem(path)?;
        spec.name = stem.clone();
        spec.bin = stem;
    }
    spec.cmd.name = spec.bin.clone();
    spec.restamp();
    let root = CommandPath::root();
    let mut out = Assembled {
        spec,
        source: Source::Scripts {
            bodies: BTreeMap::from([(root.clone(), path.to_path_buf())]),
        },
        headers: BTreeMap::from([(root, script.header)]),
        providers: Vec::new(),
        output_args: OutputArgs::new(),
        http: None,
    };
    resolve_providers(&mut out)?;
    Ok(out)
}

/// [`assemble`] for a spec given as KDL text rather than a file: `name` stands for the file,
/// `<name>.usage.kdl`, in diagnostics and as the spec's name when the text declares none. For
/// a spec a program carries in itself, as a plugin carries the spec of the CLI it stands for.
pub fn assemble_text(name: &str, kdl: &str) -> Result<Assembled, Diagnostic> {
    assemble_spec_text(
        Path::new(&format!("{name}.usage.kdl")),
        kdl.to_string(),
        &[],
    )
}

/// A spec file: the root's declaration is its top-level nodes, each `cmd` node is a command
/// whose declaration is its children.
fn assemble_spec_file(path: &Path, overlays: &[PathBuf]) -> Result<Assembled, Diagnostic> {
    let text = fs::read_to_string(path)
        .map_err(|err| Diagnostic::new(path, format!("cannot read: {err}")))?;
    assemble_spec_text(path, text, overlays)
}

fn assemble_spec_text(
    path: &Path,
    text: String,
    overlays: &[PathBuf],
) -> Result<Assembled, Diagnostic> {
    let mut doc: KdlDocument = text
        .parse()
        .map_err(|err| Diagnostic::new(path, format!("not valid KDL: {err}")))?;
    for overlay in overlays {
        let overlay_text = fs::read_to_string(overlay)
            .map_err(|err| Diagnostic::new(overlay, format!("cannot read: {err}")))?;
        let overlay_doc: KdlDocument = overlay_text
            .parse()
            .map_err(|err| Diagnostic::new(overlay, format!("not valid KDL: {err}")))?;
        crate::overlay::merge(&mut doc, &overlay_doc);
    }
    let output_args = crate::args::lift(&mut doc, path)?;
    // With overlays, or words taken out, the text usage reads is the document as it now is,
    // re-parsed so that node spans are its; a diagnostic's line then counts in that document
    // rather than the file.
    let (text, doc) = if overlays.is_empty() && output_args.is_empty() {
        (text, doc)
    } else {
        let merged = doc.to_string();
        let doc: KdlDocument = merged.parse().map_err(|err| {
            Diagnostic::new(path, format!("the overlays merged into invalid KDL: {err}"))
        })?;
        (merged, doc)
    };
    // An output's `nusage-decode` node is nusage's: usage reads the document without it, and the
    // declarations keep it. Only a document that had one is re-rendered, so a diagnostic's
    // line counts in the file as written otherwise.
    let mut for_usage = doc.clone();
    let usage_text = if strip_decodes(&mut for_usage) {
        for_usage.to_string()
    } else {
        text.clone()
    };
    let mut spec = usage::Spec::parse_str_with_path(&usage_text, path)
        .map_err(|err| Diagnostic::new(path, format!("usage rejects the spec: {err}")))?;
    if spec.name.is_empty() {
        let stem = file_stem(path)?.trim_end_matches(".usage").to_string();
        spec.name = stem.clone();
        spec.bin = stem;
    }
    spec.cmd.name = spec.bin.clone();
    spec.restamp();
    let line_of = |offset: usize| text[..offset.min(text.len())].matches('\n').count() + 1;
    let mut headers = BTreeMap::new();
    let root_nodes: Vec<_> = doc
        .nodes()
        .iter()
        .filter(|node| node.name().value() != "cmd")
        .map(|node| header_node(node, &text, line_of))
        .collect();
    headers.insert(
        CommandPath::root(),
        Header {
            path: path.to_path_buf(),
            nodes: root_nodes,
            about: spec.about.clone(),
            about_long: spec.about_long.clone(),
        },
    );
    collect_cmd_headers(
        doc.nodes(),
        &CommandPath::root(),
        &spec.cmd,
        path,
        &text,
        &line_of,
        &mut headers,
    )?;
    // A spec's `mount` runs the binary for the mounted commands; here they are unknown, and
    // the node rides along as an attribute like any other.
    fill_headers(&spec.cmd, &CommandPath::root(), path, &mut headers);
    Ok(Assembled {
        spec,
        source: Source::Binary,
        headers,
        providers: Vec::new(),
        output_args,
        http: None,
    })
}

/// Commands usage added that the source does not declare, from an `include`, get an empty
/// declaration: usage's own help, no annotations and no attributes.
fn fill_headers(
    cmd: &SpecCommand,
    path: &CommandPath,
    file: &Path,
    headers: &mut BTreeMap<CommandPath, Header>,
) {
    for (name, sub) in &cmd.subcommands {
        let child = path.child(name);
        headers.entry(child.clone()).or_insert_with(|| Header {
            path: file.to_path_buf(),
            nodes: Vec::new(),
            about: sub.help.clone(),
            about_long: sub.help_long.clone(),
        });
        fill_headers(sub, &child, file, headers);
    }
}

fn collect_cmd_headers(
    nodes: &[KdlNode],
    parent: &CommandPath,
    parent_cmd: &SpecCommand,
    path: &Path,
    text: &str,
    line_of: &impl Fn(usize) -> usize,
    headers: &mut BTreeMap<CommandPath, Header>,
) -> Result<(), Diagnostic> {
    for node in nodes.iter().filter(|node| node.name().value() == "cmd") {
        let name = node
            .entries()
            .iter()
            .find(|entry| entry.name().is_none())
            .and_then(|entry| entry.value().as_string())
            .ok_or_else(|| {
                Diagnostic::new(path, "a `cmd` node needs a name")
                    .at_line(line_of(node.span().offset()))
            })?;
        let cmd_path = parent.child(name);
        let cmd = parent_cmd.subcommands.get(name).ok_or_else(|| {
            Diagnostic::new(path, format!("usage did not keep the command `{cmd_path}`"))
        })?;
        let children = node.children().map(|doc| doc.nodes()).unwrap_or(&[]);
        let own_nodes = children
            .iter()
            .filter(|child| child.name().value() != "cmd")
            .map(|child| header_node(child, text, line_of))
            .collect();
        headers.insert(
            cmd_path.clone(),
            Header {
                path: path.to_path_buf(),
                nodes: own_nodes,
                about: cmd.help.clone(),
                about_long: cmd.help_long.clone(),
            },
        );
        collect_cmd_headers(children, &cmd_path, cmd, path, text, line_of, headers)?;
    }
    Ok(())
}

fn group_header(dir: &Path, texts: &Texts) -> Result<crate::ScriptHeader, Diagnostic> {
    let mod_nu = dir.join("mod.nu");
    if !mod_nu.is_file() {
        return Err(Diagnostic::new(
            dir,
            "a command directory needs a `mod.nu` with the group's header",
        ));
    }
    read_header_in(&mod_nu, texts)
}

/// The subcommands under `dir`, in name order: `x.nu` is the command `x`, a subdirectory with
/// a `mod.nu` is a group. Other entries are ignored.
fn children(
    dir: &Path,
    parent: &CommandPath,
    bodies: &mut BTreeMap<CommandPath, PathBuf>,
    headers: &mut BTreeMap<CommandPath, Header>,
    texts: &Texts,
) -> Result<indexmap::IndexMap<String, SpecCommand>, Diagnostic> {
    let mut entries: Vec<PathBuf> = fs::read_dir(dir)
        .map_err(|err| Diagnostic::new(dir, format!("cannot list: {err}")))?
        .filter_map(|entry| entry.ok().map(|entry| entry.path()))
        .collect();
    entries.sort();
    let mut subcommands = indexmap::IndexMap::new();
    for entry in entries {
        let name = file_stem(&entry)?;
        let (script, body, nested) = if entry.is_file() {
            if entry.extension().and_then(|ext| ext.to_str()) != Some("nu") || name == "mod" {
                continue;
            }
            (
                read_subcommand_header_in(&entry, &name, texts)?,
                entry.clone(),
                indexmap::IndexMap::new(),
            )
        } else if entry.is_dir() && entry.join("mod.nu").is_file() {
            let script = read_subcommand_header_in(&entry.join("mod.nu"), &name, texts)?;
            let path = parent.child(&name);
            let nested = children(&entry, &path, bodies, headers, texts)?;
            (script, entry.join("mod.nu"), nested)
        } else {
            continue;
        };
        reject_mounts(&script.header)?;
        let path = parent.child(&name);
        let mut cmd = script.cmd.clone();
        cmd.name = name.clone();
        cmd.subcommands = nested;
        bodies.insert(path.clone(), body);
        headers.insert(path, script.header);
        subcommands.insert(name, cmd);
    }
    Ok(subcommands)
}

fn reject_mounts(header: &Header) -> Result<(), Diagnostic> {
    if let Some(node) = header.nodes.iter().find(|node| node.name == "mount") {
        return Err(Diagnostic::new(
            &header.path,
            "`mount` is not supported in a script: a script tree's directory is the discovery",
        )
        .at_line(node.line));
    }
    Ok(())
}

/// Resolve every `choices run="<path>.nu"` to the command whose body that path is.
fn resolve_providers(out: &mut Assembled) -> Result<(), Diagnostic> {
    let Source::Scripts { bodies } = &out.source else {
        return Ok(());
    };
    let mut providers = Vec::new();
    for (path, header) in &out.headers {
        let dir = header.path.parent().unwrap_or(Path::new(""));
        let Some(cmd) = command_at(&out.spec.cmd, path) else {
            continue;
        };
        let args = cmd
            .args
            .iter()
            .map(|arg| (arg.name.clone(), arg.choices.as_ref()));
        let flags = cmd.flags.iter().filter_map(|flag| {
            flag.arg
                .as_ref()
                .map(|arg| (flag.name.clone(), arg.choices.as_ref()))
        });
        for (param, choices) in args.chain(flags) {
            let Some(run) = choices.and_then(|choices| choices.run.as_deref()) else {
                continue;
            };
            if !run.ends_with(".nu") {
                continue;
            }
            let target = normalize(&dir.join(run));
            let provider = bodies
                .iter()
                .find(|(_, body)| normalize(body) == target)
                .map(|(path, _)| path.clone());
            let Some(provider) = provider else {
                let line = header
                    .nodes
                    .iter()
                    .find(|node| node.text.contains(run))
                    .map(|node| node.line)
                    .unwrap_or(1);
                return Err(Diagnostic::new(
                    &header.path,
                    format!("`choices run=\"{run}\"` does not name a script in this tree"),
                )
                .at_line(line));
            };
            providers.push(Provider {
                consumer: path.clone(),
                param,
                provider,
            });
        }
    }
    out.providers = providers;
    Ok(())
}

/// The spec command at a path.
pub fn command_at<'a>(root: &'a SpecCommand, path: &CommandPath) -> Option<&'a SpecCommand> {
    path.words()
        .iter()
        .try_fold(root, |cmd, word| cmd.subcommands.get(word))
}

/// A path with `.` and `..` folded, without touching the filesystem.
fn normalize(path: &Path) -> PathBuf {
    let mut out = PathBuf::new();
    for component in path.components() {
        match component {
            std::path::Component::CurDir => {}
            std::path::Component::ParentDir => {
                out.pop();
            }
            other => out.push(other),
        }
    }
    out
}

fn file_stem(path: &Path) -> Result<String, Diagnostic> {
    path.file_stem()
        .and_then(|stem| stem.to_str())
        .map(str::to_string)
        .ok_or_else(|| Diagnostic::new(path, "file name is not valid UTF-8"))
}

fn dir_name(path: &Path) -> Result<String, Diagnostic> {
    path.file_name()
        .and_then(|name| name.to_str())
        .map(str::to_string)
        .ok_or_else(|| Diagnostic::new(path, "directory name is not valid UTF-8"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_outputs_decode_node_stays_on_the_declaration_and_usage_never_sees_it() {
        let dir = std::env::temp_dir().join(format!("nusage-spec-tree-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("wc.usage.kdl");
        fs::write(
            &path,
            "name \"wc\"\nbin \"wc\"\ncmd \"du\" {\n    output (\"table<size: filesize>\")\"text\" default=#true {\n        nusage-decode \"detect columns --no-headers\"\n    }\n}\n",
        )
        .unwrap();
        let assembled = assemble(&path).unwrap();
        let du = &assembled.headers[&CommandPath(vec!["du".into()])];
        let output = du.nodes.iter().find(|node| node.name == "output").unwrap();
        assert_eq!(
            output.decode.as_deref(),
            Some("detect columns --no-headers")
        );
        assert_eq!(output.value_type(), Some("table<size: filesize>"));
        assert!(output.text.contains("nusage-decode"));
        // usage read the spec without the node: the output is there, as text.
        let cmd = &assembled.spec.cmd.subcommands["du"];
        assert_eq!(cmd.outputs.len(), 1);
        assert_eq!(cmd.outputs[0].framing, usage::Framing::Text);
    }
}
