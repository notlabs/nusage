use std::collections::BTreeMap;
use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};

use usage::SpecCommand;

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

/// A script or a tree of scripts, as one usage spec plus what the spec cannot hold.
#[derive(Debug, Clone)]
pub struct Assembled {
    /// The whole command tree. A valid usage spec, so every usage tool can read it.
    pub spec: usage::Spec,
    /// The script that is each command's body.
    pub bodies: BTreeMap<CommandPath, PathBuf>,
    /// Each command's header, for its node text and annotations.
    pub headers: BTreeMap<CommandPath, Header>,
    /// Completion providers resolved to commands in the tree.
    pub providers: Vec<Provider>,
}

/// Assemble a single script, or a directory whose `mod.nu` is the root and whose files and
/// subdirectories (each with its own `mod.nu`) are its subcommands.
pub fn assemble(source: &Path) -> Result<Assembled, Diagnostic> {
    if source.is_file() {
        return assemble_single(source);
    }
    if !source.is_dir() {
        return Err(Diagnostic::new(source, "not a file or a directory"));
    }
    let mut out = Assembled {
        spec: usage::Spec::default(),
        bodies: BTreeMap::new(),
        headers: BTreeMap::new(),
        providers: Vec::new(),
    };
    let root = CommandPath::root();
    let root_header = group_header(source)?;
    reject_mounts(&root_header)?;
    let mut spec = root_header.spec.clone();
    if spec.name.is_empty() {
        let name = dir_name(source)?;
        spec.name = name.clone();
        spec.bin = name;
    }
    spec.cmd.name = spec.bin.clone();
    spec.cmd.subcommands = children(source, &root, &mut out)?;
    out.bodies.insert(root.clone(), source.join("mod.nu"));
    out.headers.insert(root, root_header);
    spec.restamp();
    out.spec = spec;
    resolve_providers(&mut out)?;
    Ok(out)
}

fn assemble_single(path: &Path) -> Result<Assembled, Diagnostic> {
    let header = read_header(path)?;
    reject_mounts(&header)?;
    let mut spec = header.spec.clone();
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
        bodies: BTreeMap::from([(root.clone(), path.to_path_buf())]),
        headers: BTreeMap::from([(root, header)]),
        providers: Vec::new(),
    };
    resolve_providers(&mut out)?;
    Ok(out)
}

fn group_header(dir: &Path) -> Result<Header, Diagnostic> {
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
    out: &mut Assembled,
) -> Result<indexmap::IndexMap<String, SpecCommand>, Diagnostic> {
    let mut entries: Vec<PathBuf> = fs::read_dir(dir)
        .map_err(|err| Diagnostic::new(dir, format!("cannot list: {err}")))?
        .filter_map(|entry| entry.ok().map(|entry| entry.path()))
        .collect();
    entries.sort();
    let mut subcommands = indexmap::IndexMap::new();
    for entry in entries {
        let name = file_stem(&entry)?;
        let (header, body, nested) = if entry.is_file() {
            if entry.extension().and_then(|ext| ext.to_str()) != Some("nu") || name == "mod" {
                continue;
            }
            let header = read_header(&entry)?;
            (header, entry.clone(), indexmap::IndexMap::new())
        } else if entry.is_dir() && entry.join("mod.nu").is_file() {
            let header = group_header(&entry)?;
            let path = parent.child(&name);
            let nested = children(&entry, &path, out)?;
            (header, entry.join("mod.nu"), nested)
        } else {
            continue;
        };
        reject_mounts(&header)?;
        let path = parent.child(&name);
        let mut cmd = header.spec.cmd.clone();
        cmd.name = name.clone();
        cmd.help = header.spec.about.clone();
        cmd.help_long = header.spec.about_long.clone();
        // A fragment's top-level `output` nodes are CLI-wide to usage; here they are the command's.
        cmd.outputs.extend(header.spec.outputs.iter().cloned());
        cmd.subcommands = nested;
        out.bodies.insert(path.clone(), body);
        out.headers.insert(path, header);
        subcommands.insert(name, cmd);
    }
    Ok(subcommands)
}

fn reject_mounts(header: &Header) -> Result<(), Diagnostic> {
    if let Some(node) = header.nodes.iter().find(|node| node.name == "mount") {
        return Err(Diagnostic::new(
            &header.path,
            "`mount` is not supported in a script tree: the directory is the discovery",
        )
        .at_line(node.line));
    }
    Ok(())
}

/// Resolve every `choices run="<path>.nu"` to the command whose body that path is.
fn resolve_providers(out: &mut Assembled) -> Result<(), Diagnostic> {
    let mut providers = Vec::new();
    for (path, header) in &out.headers {
        let dir = header.path.parent().unwrap_or(Path::new(""));
        let cmd = &header.spec.cmd;
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
            let provider = out
                .bodies
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
