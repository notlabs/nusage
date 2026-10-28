use std::collections::BTreeMap;
use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};

use usage::SpecCommand;
use usage::kdl::{KdlDocument, KdlNode};

use crate::header::header_node;
use crate::{Diagnostic, Header, read_header};

/// A command's place in the tree: subcommand names outermost first, empty at the root.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Default)]
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
}

impl Assembled {
    /// The script that is the command's body, when the source is scripts.
    pub fn body(&self, path: &CommandPath) -> Option<&Path> {
        match &self.source {
            Source::Scripts { bodies } => bodies.get(path).map(PathBuf::as_path),
            Source::Binary => None,
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
    if source.is_file() {
        return if source.extension().and_then(|ext| ext.to_str()) == Some("kdl") {
            assemble_spec_file(source, overlays)
        } else if let Some(overlay) = overlays.first() {
            Err(Diagnostic::new(
                overlay,
                "an overlay applies to a spec file; a script declares its own header",
            ))
        } else {
            assemble_single(source)
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
    let root_header = group_header(source)?;
    reject_mounts(&root_header.header)?;
    let mut spec = root_header.spec.clone();
    if spec.name.is_empty() {
        let name = dir_name(source)?;
        spec.name = name.clone();
        spec.bin = name;
    }
    spec.cmd.name = spec.bin.clone();
    spec.cmd.subcommands = children(source, &root, &mut bodies, &mut headers)?;
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
    };
    resolve_providers(&mut out)?;
    Ok(out)
}

fn assemble_single(path: &Path) -> Result<Assembled, Diagnostic> {
    let script = read_header(path)?;
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
    };
    resolve_providers(&mut out)?;
    Ok(out)
}

/// A spec file: the root's declaration is its top-level nodes, each `cmd` node is a command
/// whose declaration is its children.
fn assemble_spec_file(path: &Path, overlays: &[PathBuf]) -> Result<Assembled, Diagnostic> {
    let text = fs::read_to_string(path)
        .map_err(|err| Diagnostic::new(path, format!("cannot read: {err}")))?;
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
    // With overlays, the text usage reads is the merged document, re-parsed so that node
    // spans are its; a diagnostic's line then counts in that document rather than the file.
    let (text, doc) = if overlays.is_empty() {
        (text, doc)
    } else {
        let merged = doc.to_string();
        let doc: KdlDocument = merged.parse().map_err(|err| {
            Diagnostic::new(path, format!("the overlays merged into invalid KDL: {err}"))
        })?;
        (merged, doc)
    };
    let mut spec = usage::Spec::parse_str_with_path(&text, path)
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

fn group_header(dir: &Path) -> Result<crate::ScriptHeader, Diagnostic> {
    let mod_nu = dir.join("mod.nu");
    if !mod_nu.is_file() {
        return Err(Diagnostic::new(
            dir,
            "a command directory needs a `mod.nu` with the group's header",
        ));
    }
    read_header(&mod_nu)
}

/// The subcommands under `dir`, in name order: `x.nu` is the command `x`, a subdirectory with
/// a `mod.nu` is a group. Other entries are ignored.
fn children(
    dir: &Path,
    parent: &CommandPath,
    bodies: &mut BTreeMap<CommandPath, PathBuf>,
    headers: &mut BTreeMap<CommandPath, Header>,
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
                read_header(&entry)?,
                entry.clone(),
                indexmap::IndexMap::new(),
            )
        } else if entry.is_dir() && entry.join("mod.nu").is_file() {
            let script = group_header(&entry)?;
            let path = parent.child(&name);
            let nested = children(&entry, &path, bodies, headers)?;
            (script, entry.join("mod.nu"), nested)
        } else {
            continue;
        };
        reject_mounts(&script.header)?;
        let path = parent.child(&name);
        let mut cmd = script.spec.cmd.clone();
        cmd.name = name.clone();
        cmd.help = script.spec.about.clone();
        cmd.help_long = script.spec.about_long.clone();
        // A fragment's top-level `output` nodes are CLI-wide to usage; here they are the command's.
        cmd.outputs.extend(script.spec.outputs.iter().cloned());
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
