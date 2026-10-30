//! `nusage nu`: `nu`, as mise's command wrapper starts it in the `nusage-lsp` environment, so
//! an editor that starts `nu --lsp` gets nusage's language server without being told of it:
//! kakehashi with nusage's layer when kakehashi is on PATH, which highlights a script's header
//! and bridges the script to `nusage lsp`, else `nusage lsp` alone. Anything else is `nu`, as
//! it was asked for.

use std::ffi::OsStr;
use std::io;
use std::path::{Path, PathBuf};
use std::process::Command;

/// Set for the `nu` a language server of nusage's starts: that one is Nushell's own.
pub const SERVING: &str = "NUSAGE_LSP";

/// Set on the `nu` this runs, to this process's id. Should that `nu` lead back here, through
/// a shim or wrapper [`real_nu`] did not see for one, the `nusage nu` it reaches is this same
/// process, as mise's shims and wrappers exec on unix, and it stops instead of going round
/// for ever. A `nu` that Nushell starts in turn is a process of its own, and runs.
const RAN: &str = "NUSAGE_NU_PID";

/// nusage's layer for kakehashi: the queries it adds, by path under the layer.
const LAYER: &[(&str, &str)] = &[
    (
        "queries/nu/injections.scm",
        include_str!("kakehashi/queries/nu/injections.scm"),
    ),
    (
        "queries/kdl/injections.scm",
        include_str!("kakehashi/queries/kdl/injections.scm"),
    ),
];

/// Run as `nu` with these arguments; the exit code is what ran's.
pub fn run(args: &[String]) -> io::Result<i32> {
    let pid = std::process::id().to_string();
    if std::env::var(RAN).is_ok_and(|ran| ran == pid) {
        return Err(io::Error::other(
            "the `nu` on PATH leads back to `nusage nu`: there is no Nushell past it",
        ));
    }
    let Some(rest) = lsp_requested(args).filter(|_| std::env::var_os(SERVING).is_none()) else {
        return replace_with(Command::new(real_nu()).args(args).env(RAN, pid));
    };
    let nusage = std::env::current_exe()?;
    match on_path("kakehashi") {
        Some(kakehashi) => {
            let config = layer(&nusage, &rest)?;
            replace_with(Command::new(kakehashi).arg("--config-file").arg(config))
        }
        None => crate::lsp::serve(&rest),
    }
}

/// Whether `nu` is asked to serve its language server, and then the rest of its arguments:
/// `--lsp` among Nushell's own flags, before a script or a command takes the rest.
fn lsp_requested(args: &[String]) -> Option<Vec<String>> {
    // Nushell's flags that take the word after them, as `nu --help` lists them.
    const VALUED: &[&str] = &[
        "-c",
        "--commands",
        "-e",
        "--execute",
        "-m",
        "--table-mode",
        "--error-style",
        "--mcp-transport",
        "--mcp-port",
        "--mcp-host",
        "-I",
        "--include-path",
        "--config",
        "--env-config",
        "--config-home",
        "--log-level",
        "--log-target",
        "--log-file",
        "--log-include",
        "--log-exclude",
        "--ide-goto-def",
        "--ide-hover",
        "--ide-complete",
        "--ide-check",
        "--experimental-options",
        "--plugin-config",
        "--plugins",
    ];
    let mut words = args.iter().enumerate();
    while let Some((at, word)) = words.next() {
        if word == "--lsp" {
            let mut rest = args.to_vec();
            rest.remove(at);
            return Some(rest);
        }
        if VALUED.contains(&word.as_str()) {
            words.next();
        } else if !word.starts_with('-') {
            // A script: what follows is its own.
            return None;
        }
    }
    None
}

/// The `nu` to run: the first on PATH that is not one of mise's shims or wrappers, which would
/// lead back here; they are links to mise itself. Under mise's wrapper the PATH holds none of
/// them, mise takes their directories off it for the command, so the toolset's `nu` is first.
/// Should either stop being so, [`RAN`] stops the loop.
pub fn real_nu() -> PathBuf {
    let here = std::env::current_exe().and_then(std::fs::canonicalize).ok();
    let name = format!("nu{}", std::env::consts::EXE_SUFFIX);
    std::env::var_os("PATH")
        .iter()
        .flat_map(std::env::split_paths)
        .map(|dir| dir.join(&name))
        .find(|candidate| {
            let Ok(target) = std::fs::canonicalize(candidate) else {
                return false;
            };
            let mise = target.file_stem() == Some(OsStr::new("mise"));
            target.is_file() && !mise && Some(&target) != here.as_ref()
        })
        .unwrap_or_else(|| PathBuf::from(name))
}

/// A program on PATH.
fn on_path(program: &str) -> Option<PathBuf> {
    let name = format!("{program}{}", std::env::consts::EXE_SUFFIX);
    std::env::var_os("PATH")
        .iter()
        .flat_map(std::env::split_paths)
        .map(|dir| dir.join(&name))
        .find(|candidate| candidate.is_file())
}

/// Write nusage's layer for kakehashi where it can be read, and return its configuration
/// file: the queries that inject a script's header and its `run=` scripts, and the
/// configuration that bridges a script to `nusage lsp` with Nushell's other arguments. The
/// layer is named by what it holds, so one written for other arguments stands beside it.
fn layer(nusage: &Path, args: &[String]) -> io::Result<PathBuf> {
    let config = config(nusage, args);
    let mut files: Vec<(&str, String)> = LAYER
        .iter()
        .map(|(path, text)| (*path, text.to_string()))
        .collect();
    files.push(("kakehashi.toml", config));
    let dir = cache_dir()
        .join("nusage")
        .join("kakehashi")
        .join(digest(&files));
    for (path, text) in &files {
        let file = dir.join(path);
        if std::fs::read_to_string(&file).ok().as_deref() != Some(text) {
            std::fs::create_dir_all(file.parent().expect("a file in the layer"))?;
            std::fs::write(&file, text)?;
        }
    }
    Ok(dir.join("kakehashi.toml"))
}

/// kakehashi's configuration in nusage's layer. Its queries come first and kakehashi's data
/// after, which holds the parsers and queries it installs; this kakehashi serves Nushell
/// documents alone, so what the layer adds to KDL is for headers. A script, under either
/// language id an editor gives Nushell, is bridged to `nusage lsp` as itself; the scripts
/// its header's `run=` names are not, being a word each. `sh` is read with bash's parser.
fn config(nusage: &Path, args: &[String]) -> String {
    let quoted = |text: &str| serde_json::to_string(text).expect("a string");
    let mut cmd = vec![
        quoted(&nusage.to_string_lossy()),
        quoted("lsp"),
        quoted("--"),
    ];
    cmd.extend(args.iter().map(|arg| quoted(arg)));
    format!(
        r#"# nusage's layer for kakehashi, written by `nusage nu --lsp`.
searchPaths = [".", "${{KAKEHASHI_DATA_DIR}}"]

[languages.nushell]
base = "nu"

[languages.sh]
base = "bash"

[languages.nu.bridge._self]
enabled = true

[languages.nu.bridge.nu]
enabled = false

[languages.nushell.bridge._self]
enabled = true

[languages.nushell.bridge.nu]
enabled = false

[languageServers.nusage]
cmd = [{}]
languages = ["nu", "nushell"]
"#,
        cmd.join(", ")
    )
}

/// The user's cache directory, as each platform has one.
fn cache_dir() -> PathBuf {
    let var = |name: &str| std::env::var_os(name).filter(|value| !value.is_empty());
    if cfg!(windows) {
        if let Some(dir) = var("LOCALAPPDATA") {
            return PathBuf::from(dir);
        }
    } else if cfg!(target_os = "macos") {
        if let Some(home) = var("HOME") {
            return PathBuf::from(home).join("Library/Caches");
        }
    } else if let Some(dir) = var("XDG_CACHE_HOME") {
        return PathBuf::from(dir);
    } else if let Some(home) = var("HOME") {
        return PathBuf::from(home).join(".cache");
    }
    std::env::temp_dir()
}

/// A name for the layer's contents, the same from one build of nusage to the next (FNV-1a),
/// so the layers in the cache are as many as the contents they have had.
fn digest(files: &[(&str, String)]) -> String {
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for (path, text) in files {
        for byte in path.bytes().chain([0]).chain(text.bytes()).chain([0]) {
            hash = (hash ^ u64::from(byte)).wrapping_mul(0x0100_0000_01b3);
        }
    }
    format!("{hash:016x}")
}

/// Become the command, as a wrapper should: on unix the process is replaced, so signals,
/// the terminal and the exit status are the command's own; elsewhere it runs to its end.
fn replace_with(command: &mut Command) -> io::Result<i32> {
    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        Err(command.exec())
    }
    #[cfg(not(unix))]
    {
        Ok(command.status()?.code().unwrap_or(1))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn words(text: &str) -> Vec<String> {
        text.split_whitespace().map(str::to_string).collect()
    }

    #[test]
    fn lsp_is_asked_for_among_nushells_own_flags() {
        assert_eq!(lsp_requested(&words("--lsp")), Some(vec![]));
        assert_eq!(
            lsp_requested(&words("--config x.nu --lsp -n")),
            Some(words("--config x.nu -n"))
        );
        // A script's own flag, and a command's.
        assert_eq!(lsp_requested(&words("script.nu --lsp")), None);
        assert_eq!(lsp_requested(&words("-c foo --lsp")), Some(words("-c foo")));
        assert_eq!(lsp_requested(&words("--ide-check 10 x.nu")), None);
        assert_eq!(lsp_requested(&words("--mcp")), None);
    }

    #[test]
    fn the_layers_name_is_its_contents() {
        let files = |text: &str| vec![("a", text.to_string())];
        assert_eq!(digest(&files("x")), digest(&files("x")));
        assert_ne!(digest(&files("x")), digest(&files("y")));
        // FNV-1a's own value for the empty input, so the name holds across builds.
        assert_eq!(digest(&[]), "cbf29ce484222325");
    }

    #[test]
    fn the_layer_bridges_a_script_to_nusage_with_nushells_arguments() {
        let config = config(Path::new("/bin/nusage"), &words("--config x.nu"));
        assert!(
            config.contains(r#"cmd = ["/bin/nusage", "lsp", "--", "--config", "x.nu"]"#),
            "{config}"
        );
        assert!(config.contains(r#"searchPaths = [".", "${KAKEHASHI_DATA_DIR}"]"#));
    }
}
