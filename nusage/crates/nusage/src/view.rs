//! A view: the directory `NUS_VIEW` names, of modules a script imports by a path that is not
//! beside it, as `use pkg+notlabs/catalog/jj`. The interpreter puts the view on the script's
//! `NU_LIB_DIRS`, alone, so an import resolves to the script's own directory or the view
//! and nowhere else. Nushell looks beside the script first; an entry of the view's that is
//! also beside the script would take the view's place without a word, so the interpreter
//! refuses the script instead. `bins.nuon` in the view, when present, is the map of binaries
//! the generated wrappers run (`$env.NUS_BINS`). What fills the view is not nusage's concern.

use std::path::{Path, PathBuf};

/// The variable that names the view.
pub const VAR: &str = "NUS_VIEW";

/// The view's map of binaries, by the name a wrapper runs to the path it runs.
const BINS: &str = "bins.nuon";

/// The view `NUS_VIEW` names: none when it is unset or empty, an error when it names no
/// directory by an absolute path.
pub fn current() -> Result<Option<PathBuf>, String> {
    let Some(value) = std::env::var_os(VAR).filter(|value| !value.is_empty()) else {
        return Ok(None);
    };
    let dir = PathBuf::from(value);
    if !dir.is_absolute() {
        return Err(format!("{VAR} is {}, not an absolute path", dir.display()));
    }
    if !dir.is_dir() {
        return Err(format!(
            "{VAR} names {}, which is no directory",
            dir.display()
        ));
    }
    Ok(Some(dir))
}

/// The view's entries that the directory `dir` also holds, which an import from a script in
/// `dir` would reach there instead: every name at the view's top but its map of binaries
/// and hidden ones.
pub fn shadowed(view: &Path, dir: &Path) -> Vec<String> {
    let Ok(entries) = std::fs::read_dir(view) else {
        return Vec::new();
    };
    let mut names: Vec<String> = entries
        .filter_map(|entry| entry.ok()?.file_name().into_string().ok())
        .filter(|name| name != BINS && !name.starts_with('.'))
        .filter(|name| dir.join(name).symlink_metadata().is_ok())
        .collect();
    names.sort();
    names
}

/// Why a script in `dir` cannot have the view: an entry beside it would take the place of the
/// view's, so its imports would not mean what the view says.
pub fn refusal(view: &Path, dir: &Path) -> Option<String> {
    let shadowed = shadowed(view, dir);
    if shadowed.is_empty() {
        return None;
    }
    Some(format!(
        "{} beside the script would take the place of the view's in {}: an import names one \
         module",
        shadowed
            .iter()
            .map(|name| format!("`{name}`"))
            .collect::<Vec<_>>()
            .join(", "),
        view.display()
    ))
}

/// The view as a checker reads it, opening the line that stands in for a script's first:
/// the view as its only library directory, which the imports after it resolve against.
pub fn check_prefix(view: &Path) -> String {
    format!(
        "const NU_LIB_DIRS = [{}]; ",
        nusage_nu::word(&view.to_string_lossy())
    )
}

/// The lines that open a script's program: the view as its only library directory, and the
/// view's map of binaries, as the NUON text a process started from the script also gets.
pub fn prelude(view: &Path) -> Result<String, String> {
    let mut code = format!(
        "const NU_LIB_DIRS = [{}]\n",
        nusage_nu::word(&view.to_string_lossy())
    );
    let bins = view.join(BINS);
    if bins.exists() {
        let text = std::fs::read_to_string(&bins)
            .map_err(|err| format!("cannot read {}: {err}", bins.display()))?;
        code.push_str(&format!(
            "$env.NUS_BINS = {}\n",
            nusage_nu::nuon(&nu_protocol::Value::string(
                text.trim(),
                nu_protocol::Span::unknown()
            ))
        ));
    }
    Ok(code)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// An empty directory of the test's own.
    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("nusage-view-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn an_entry_beside_the_script_shadows_the_views() {
        let root = scratch("shadowed");
        let view = root.join("view");
        let dir = root.join("project");
        std::fs::create_dir_all(view.join("pkg+notlabs/catalog/jj")).unwrap();
        std::fs::create_dir_all(view.join("pkg+other")).unwrap();
        std::fs::create_dir_all(view.join(".hidden")).unwrap();
        std::fs::write(view.join(BINS), "{}").unwrap();
        std::fs::create_dir_all(dir.join("pkg+other")).unwrap();
        std::fs::write(dir.join(BINS), "{}").unwrap();
        std::fs::create_dir_all(dir.join(".hidden")).unwrap();
        assert_eq!(shadowed(&view, &dir), ["pkg+other"]);
        assert!(shadowed(&view, &root.join("elsewhere")).is_empty());
        std::fs::remove_dir_all(&root).unwrap();
    }

    #[test]
    fn the_prelude_names_the_view_and_its_binaries() {
        let root = scratch("prelude");
        let view = root.as_path();
        let lines = prelude(view).unwrap();
        assert_eq!(
            lines,
            format!(
                "const NU_LIB_DIRS = [{}]\n",
                nusage_nu::word(&view.to_string_lossy())
            )
        );
        std::fs::write(view.join(BINS), "{jj: \"/opt/jj\"}\n").unwrap();
        let lines = prelude(view).unwrap();
        assert!(
            lines.ends_with("$env.NUS_BINS = \"{jj: \\\"/opt/jj\\\"}\"\n"),
            "{lines}"
        );
        std::fs::remove_dir_all(&root).unwrap();
    }
}
