//! mise's tasks, as a script runs one: `mise run <task> ...`. mise knows what a name means
//! from a directory, its aliases, `:task` and a monorepo's `//path:task` among them, so it is
//! asked, the way it is asked to run the task.

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
}

/// The task `mise run <name>` runs in `dir`, or `None` when its run is not a file: the
/// commands of a config's `run`. What mise says when it cannot tell is the error.
pub fn task(dir: &Path, name: &str) -> Result<Option<Task>, String> {
    let output = Command::new("mise")
        .arg("-C")
        .arg(dir)
        .args(["tasks", "info", "--json", "--", name])
        .output()
        .map_err(|err| format!("cannot ask mise for its task `{name}`: {err}"))?;
    if !output.status.success() {
        let said = String::from_utf8_lossy(&output.stderr);
        let first = said
            .lines()
            .map(|line| line.trim_start_matches("mise ERROR").trim())
            .find(|line| !line.is_empty())
            .unwrap_or("no reason given");
        return Err(format!("mise: {first}"));
    }
    let info: Json = serde_json::from_slice(&output.stdout)
        .map_err(|err| format!("mise's account of the task `{name}` does not read: {err}"))?;
    let (Some(file), Some(source)) = (info["file"].as_str(), info["source"].as_str()) else {
        return Ok(None);
    };
    Ok(Some(Task {
        name: info["name"].as_str().unwrap_or(name).to_string(),
        file: config_root(Path::new(source)).join(file),
    }))
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
