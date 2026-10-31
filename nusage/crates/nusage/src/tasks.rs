//! mise's tasks, as a script runs one: `mise run <task> ...`. mise knows what a name means
//! from a directory, its aliases, `:task` and a monorepo's `//path:task` among them, so it is
//! asked, the way it is asked to run the task: for the task, for the environment it would
//! run the task in, and to run a task whose run is not a file.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::process::Command;

use serde_json::Value as Json;

/// A task whose run is a file.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Task {
    /// The task's name as mise gives it, which names it from anywhere mise names it from here.
    pub name: String,
    /// The file it runs.
    pub file: PathBuf,
    /// Its config's root, which its relative paths are read from.
    pub root: PathBuf,
    /// The directory mise runs it in: its `dir`, or its config's root.
    pub dir: PathBuf,
    /// The tasks mise runs before it, in order.
    pub depends: Vec<Dep>,
    /// The tasks mise runs after it, in order.
    pub depends_post: Vec<Dep>,
}

/// A task another task depends on, with the arguments it is run with.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Dep {
    pub task: String,
    pub args: Vec<String>,
}

impl Dep {
    /// A dependency as mise's account writes it: a name, a name with words after it, a list
    /// of the name and its arguments, or a table with `task` and `args`.
    fn read(json: &Json) -> Option<Dep> {
        match json {
            Json::String(text) => {
                let mut words = text.split_whitespace().map(str::to_string);
                Some(Dep {
                    task: words.next()?,
                    args: words.collect(),
                })
            }
            Json::Array(items) => {
                let mut words = items.iter().filter_map(Json::as_str).map(str::to_string);
                Some(Dep {
                    task: words.next()?,
                    args: words.collect(),
                })
            }
            Json::Object(table) => Some(Dep {
                task: table.get("task")?.as_str()?.to_string(),
                args: table
                    .get("args")
                    .and_then(Json::as_array)
                    .map(|args| {
                        args.iter()
                            .filter_map(Json::as_str)
                            .map(str::to_string)
                            .collect()
                    })
                    .unwrap_or_default(),
            }),
            _ => None,
        }
    }
}

/// mise, asked from `dir`, with `env` over this process's environment when given: a caller's
/// environment, which is where mise reads its own settings from.
fn mise(dir: &Path, env: Option<&HashMap<String, String>>) -> Command {
    let mut command = Command::new("mise");
    command.arg("-C").arg(dir);
    if let Some(env) = env {
        command.envs(env);
    }
    command
}

/// The first line mise gives for a failure, without its colours and its own prefix.
fn said(stderr: &[u8]) -> String {
    let said = plain(&String::from_utf8_lossy(stderr));
    said.lines()
        .map(|line| line.trim_start_matches("mise ERROR").trim())
        .find(|line| !line.is_empty())
        .unwrap_or("no reason given")
        .to_string()
}

/// The task `mise run <name>` runs in `dir`, or `None` when its run is not a file: the
/// commands of a config's `run`. What mise says when it cannot tell is the error.
pub fn task(dir: &Path, name: &str) -> Result<Option<Task>, String> {
    task_in(dir, name, None)
}

/// [`task`], with mise asked in `env` when given.
pub fn task_in(
    dir: &Path,
    name: &str,
    env: Option<&HashMap<String, String>>,
) -> Result<Option<Task>, String> {
    let output = mise(dir, env)
        .args(["tasks", "info", "--json", "--", name])
        .output()
        .map_err(|err| format!("cannot ask mise for its task `{name}`: {err}"))?;
    if !output.status.success() {
        return Err(format!("mise: {}", said(&output.stderr)));
    }
    let info: Json = serde_json::from_slice(&output.stdout)
        .map_err(|err| format!("mise's account of the task `{name}` does not read: {err}"))?;
    let (Some(file), Some(source)) = (info["file"].as_str(), info["source"].as_str()) else {
        return Ok(None);
    };
    let root = config_root(Path::new(source));
    let deps = |field: &str| {
        info[field]
            .as_array()
            .map(|deps| deps.iter().filter_map(Dep::read).collect())
            .unwrap_or_default()
    };
    Ok(Some(Task {
        name: info["name"].as_str().unwrap_or(name).to_string(),
        file: root.join(file),
        dir: info["dir"]
            .as_str()
            .filter(|dir| !dir.is_empty())
            .map_or_else(|| root.clone(), |dir| root.join(dir)),
        root,
        depends: deps("depends"),
        depends_post: deps("depends_post"),
    }))
}

/// The environment mise runs a task in `dir` with: its configs' variables and the tools'
/// paths, as `mise env` gives them.
pub fn environment(
    dir: &Path,
    env: Option<&HashMap<String, String>>,
) -> Result<HashMap<String, String>, String> {
    let output = mise(dir, env)
        .args(["env", "--json"])
        .output()
        .map_err(|err| format!("cannot ask mise for its environment: {err}"))?;
    if !output.status.success() {
        return Err(format!("mise: {}", said(&output.stderr)));
    }
    let vars: HashMap<String, Json> = serde_json::from_slice(&output.stdout)
        .map_err(|err| format!("mise's account of its environment does not read: {err}"))?;
    Ok(vars
        .into_iter()
        .filter_map(|(name, value)| match value {
            Json::String(text) => Some((name, text)),
            Json::Null => None,
            other => Some((name, other.to_string())),
        })
        .collect())
}

/// `mise run <name> ...args` in `dir`, with what it prints passing through; the error is
/// the exit mise gave.
pub fn run(
    dir: &Path,
    name: &str,
    args: &[String],
    env: Option<&HashMap<String, String>>,
) -> Result<(), String> {
    let status = mise(dir, env)
        .args(["run", name])
        .args(args)
        .status()
        .map_err(|err| format!("cannot run mise: {err}"))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!(
            "`mise run {name}` exited with {}",
            status
                .code()
                .map_or("a signal".to_string(), |code| code.to_string())
        ))
    }
}

/// Text without the terminal's colours, which mise writes when its own task runs this.
fn plain(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut chars = text.chars();
    while let Some(c) = chars.next() {
        if c == '\u{1b}' && chars.clone().next() == Some('[') {
            chars
                .by_ref()
                .find(|c| ('@'..='~').contains(c) && *c != '[');
        } else {
            out.push(c);
        }
    }
    out
}

/// The directory a config's relative paths are read from, as mise has it: the config's own,
/// or the project's for one in `.config/`, for a `config.toml` in `mise/` or `.mise/`, and
/// for a fragment in their `conf.d/`. A file task's source is the file, which is absolute.
fn config_root(source: &Path) -> PathBuf {
    let names: Vec<String> = source
        .components()
        .map(|component| component.as_os_str().to_string_lossy().into_owned())
        .collect();
    let back = |n: usize| names.iter().rev().nth(n).map_or("", String::as_str);
    let up = |n: usize| {
        source
            .ancestors()
            .nth(n)
            .unwrap_or(Path::new(""))
            .to_path_buf()
    };
    let mise_dir = |name: &str| name == "mise" || name == ".mise";
    let config_name = |name: &str| name.starts_with("config.") && name.ends_with(".toml");
    if back(1) == "conf.d" && mise_dir(back(2)) {
        up(if back(3) == ".config" { 4 } else { 3 })
    } else if mise_dir(back(1)) && config_name(back(0)) {
        up(if back(2) == ".config" { 3 } else { 2 })
    } else if back(1) == ".config" {
        up(2)
    } else {
        up(1)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_dependency_is_read_in_each_form() {
        let dep = |task: &str, args: &[&str]| Dep {
            task: task.into(),
            args: args.iter().map(|arg| arg.to_string()).collect(),
        };
        assert_eq!(
            Dep::read(&serde_json::json!("build")),
            Some(dep("build", &[]))
        );
        assert_eq!(
            Dep::read(&serde_json::json!("build --release")),
            Some(dep("build", &["--release"]))
        );
        assert_eq!(
            Dep::read(&serde_json::json!(["build", "--release"])),
            Some(dep("build", &["--release"]))
        );
        assert_eq!(
            Dep::read(
                &serde_json::json!({"task": "build", "args": ["--release"], "optional": true})
            ),
            Some(dep("build", &["--release"]))
        );
        assert_eq!(Dep::read(&serde_json::json!({"optional": true})), None);
    }

    #[test]
    fn colours_are_taken_out() {
        assert_eq!(
            plain("\u{1b}[31mmise\u{1b}[0m \u{1b}[31mERROR\u{1b}[0m Task not found: nope"),
            "mise ERROR Task not found: nope"
        );
    }

    #[test]
    fn a_configs_paths_are_its_projects() {
        for source in [
            "/p/mise.toml",
            "/p/.config/mise.toml",
            "/p/.mise/config.toml",
            "/p/mise/config.toml",
            "/p/.config/mise/config.toml",
            "/p/.config/mise/config.local.toml",
            "/p/.config/mise/conf.d/a.toml",
            "/p/.mise/conf.d/a.toml",
        ] {
            assert_eq!(config_root(Path::new(source)), Path::new("/p"), "{source}");
        }
        // A project of a monorepo named `mise`, with its own config.
        assert_eq!(
            config_root(Path::new("/p/mise/mise.toml")),
            Path::new("/p/mise")
        );
    }
}
