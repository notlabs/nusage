//! `nus activate <shell>`: what activates nusage in a shell, as `mise activate` does for mise,
//! in mise's place. For Nushell the environment mise resolves for the working directory and
//! `MISE_ENV` is an overlay, `mise`, and the typed commands of the packages it names are
//! another, `nus`, above it, reloaded by a hook before each prompt when the environment
//! changed. The script, `activate.nu`, says how; this fills in the paths it is written with.

use std::path::Path;

/// The script for Nushell, with the paths of this `nus` and its cache in it.
const NU: &str = include_str!("activate.nu");

/// What activates nusage in `shell`: the shells are `nu`.
pub fn script(shell: &str) -> Result<String, String> {
    match shell {
        "nu" => {
            let nus = std::env::current_exe()
                .map_err(|err| format!("cannot find this nus to write into the script: {err}"))?;
            let root = crate::common::cache_dir().join("nusage").join("activate");
            Ok(nu(&nus, &root))
        }
        other => Err(format!("cannot activate `{other}`: the shells are `nu`")),
    }
}

/// The script for Nushell: `nus` runs the packages' module where the environment has no `nus`
/// of its own, and each shell writes its modules in a directory of `root`.
fn nu(nus: &Path, root: &Path) -> String {
    // A JSON string is a Nushell string, escapes and all.
    let quoted = |path: &Path| serde_json::to_string(&path.to_string_lossy()).expect("a string");
    NU.replace("\"@nus@\"", &quoted(nus))
        .replace("\"@root@\"", &quoted(root))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_script_has_this_nus_and_its_cache_written_in() {
        let script = nu(
            Path::new("/opt/a \"b\"/nus"),
            Path::new("/c/nusage/activate"),
        );
        assert!(script.contains(r#""/opt/a \"b\"/nus""#), "{script}");
        assert!(script.contains(r#""/c/nusage/activate""#), "{script}");
        assert!(!script.contains('@'), "{script}");
    }

    #[test]
    fn only_nushell_is_a_shell_to_activate() {
        assert!(script("nu").is_ok());
        assert!(script("bash").unwrap_err().contains("`bash`"));
    }
}
