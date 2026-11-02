//! `nus nu`: `nu`, as a command wrapper standing in Nushell's place starts it (mise's
//! `[wrappers.nu]` with `args = ["nu"]`, say), so an editor that starts `nu --lsp` gets
//! nusage's language server without being told of it: kakehashi with nusage's layer when
//! kakehashi is on PATH, which highlights a script's header and bridges the script to `nus
//! lsp`, else `nus lsp` alone. Anything else is `nu`, as it was asked for. The arguments are
//! read by Nushell's own command line, as a usage spec, so `--lsp` is found among Nushell's
//! flags and never among a script's.

use std::ffi::OsStr;
use std::io;
use std::path::{Path, PathBuf};
use std::process::Command;

/// Set for the `nu` a language server of nusage's starts: that one is Nushell's own.
pub const SERVING: &str = "NUS_LSP";

/// Set on the `nu` this runs, to this process's id. Should that `nu` lead back here, through
/// a shim or wrapper [`real_nu`] did not see for one, the `nus nu` it reaches is this same
/// process, as a wrapper that execs on unix leaves it, and it stops instead of going round
/// for ever. A `nu` that Nushell starts in turn is a process of its own, and runs.
const RAN: &str = "NUS_NU_PID";

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
            "the `nu` on PATH leads back to `nus nu`: there is no Nushell past it",
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

/// Nushell's own command line, as a usage spec.
const SPEC: &str = include_str!("nu.usage.kdl");

/// Whether `nu` is asked to serve its language server, and then the rest of its arguments:
/// `--lsp` among Nushell's own flags, before a script or a command takes the rest. usage
/// reads the arguments by Nushell's spec; arguments it cannot read are Nushell's to refuse.
fn lsp_requested(args: &[String]) -> Option<Vec<String>> {
    let spec: usage::Spec = SPEC.parse().expect("Nushell's spec reads");
    let argv: Vec<String> = std::iter::once("nu".to_string())
        .chain(args.iter().cloned())
        .collect();
    let parsed = usage::parse::Parser::new(&spec)
        .without_running_commands()
        .parse(&argv)
        .ok()?;
    if !parsed.flags.keys().any(|flag| flag.name == "lsp") {
        return None;
    }
    let at = args.iter().position(|word| word == "--lsp")?;
    let mut rest = args.to_vec();
    rest.remove(at);
    Some(rest)
}

/// The `nu` to run: the first on PATH that is Nushell, a file named `nu` once its links are
/// followed, and not this program. A shim or wrapper is a link to another program, such as a
/// version manager's, and may lead back here, so it is passed over. A wrapper that takes its
/// own directory off PATH for the command it starts, as mise's does, leaves none to pass.
/// Should one that does not look so lead back here, [`RAN`] stops the loop.
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
            let nushell = target.file_stem() == Some(OsStr::new("nu"));
            target.is_file() && nushell && Some(&target) != here.as_ref()
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
/// configuration that bridges a script to `nus lsp` with Nushell's other arguments. The
/// layer is named by what it holds, so one written for other arguments stands beside it.
fn layer(nusage: &Path, args: &[String]) -> io::Result<PathBuf> {
    let config = config(nusage, args);
    let mut files: Vec<(&str, String)> = LAYER
        .iter()
        .map(|(path, text)| (*path, text.to_string()))
        .collect();
    files.push(("kakehashi.toml", config));
    let dir = crate::common::cache_dir()
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
/// language id an editor gives Nushell, is bridged to `nus lsp` as itself; the scripts
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
        r#"# nusage's layer for kakehashi, written by `nus nu --lsp`.
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

[languageServers.nus]
cmd = [{}]
languages = ["nu", "nushell"]
"#,
        cmd.join(", ")
    )
}

/// A name for the layer's contents, the same from one build of nusage to the next, so the
/// layers in the cache are as many as the contents they have had.
fn digest(files: &[(&str, String)]) -> String {
    crate::common::fnv1a(
        files
            .iter()
            .flat_map(|(path, text)| path.bytes().chain([0]).chain(text.bytes()).chain([0])),
    )
}

/// Become the command, as a wrapper should: on unix the process is replaced, so signals,
/// the terminal and the exit status are the command's own; elsewhere it runs to its end.
pub(crate) fn replace_with(command: &mut Command) -> io::Result<i32> {
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
        // A flag's value that reads as `--lsp` is the value, and a repeated flag takes its
        // value each time.
        assert_eq!(lsp_requested(&words("-c --lsp")), None);
        assert_eq!(
            lsp_requested(&words("--plugins a --plugins b --lsp")),
            Some(words("--plugins a --plugins b"))
        );
        // A flag Nushell does not have is Nushell's to refuse.
        assert_eq!(lsp_requested(&words("--no-such-flag --lsp")), None);
    }

    /// The spec is the Nushell nusage is built against: its version is that of the Nushell
    /// crates in Cargo.lock, and where the `nu` on PATH is that version, its flags are the
    /// ones `nu --help` lists, each taking a value as it does there.
    #[test]
    fn the_spec_is_nushells_own() {
        let spec: usage::Spec = SPEC.parse().unwrap();
        let lock = std::fs::read_to_string(
            Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../Cargo.lock"),
        )
        .unwrap();
        let crates = lock
            .split("[[package]]")
            .find(|package| package.contains("name = \"nu-protocol\""))
            .and_then(|package| {
                package.lines().find_map(|line| {
                    Some(
                        line.strip_prefix("version = \"")?
                            .strip_suffix('"')?
                            .to_string(),
                    )
                })
            })
            .expect("nu-protocol in Cargo.lock");
        assert_eq!(spec.version.as_deref(), Some(crates.as_str()));
        let version = Command::new(real_nu()).arg("--version").output();
        let Ok(version) = version else {
            return;
        };
        if String::from_utf8_lossy(&version.stdout).trim() != crates {
            return;
        }
        let help = Command::new(real_nu()).arg("--help").output().unwrap();
        let listed: std::collections::BTreeMap<String, bool> =
            String::from_utf8_lossy(&help.stdout)
                .lines()
                .filter_map(|line| {
                    let line = line.trim_start();
                    // `-c, --commands <string>`, `--stdin`: the long name, and a value when
                    // one is named.
                    let long = line.strip_prefix('-')?.rsplit(", ").next()?;
                    let (name, value) = match long.split_once(' ') {
                        Some((name, _)) => (name, true),
                        None => (long, false),
                    };
                    Some((name.trim_start_matches('-').to_string(), value))
                })
                .collect();
        let declared: std::collections::BTreeMap<String, bool> = spec
            .cmd
            .flags
            .iter()
            .filter_map(|flag| Some((flag.long.first()?.clone(), flag.arg.is_some())))
            .collect();
        assert_eq!(declared, listed);
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
        let config = config(Path::new("/bin/nus"), &words("--config x.nu"));
        assert!(
            config.contains(r#"cmd = ["/bin/nus", "lsp", "--", "--config", "x.nu"]"#),
            "{config}"
        );
        assert!(config.contains(r#"searchPaths = [".", "${KAKEHASHI_DATA_DIR}"]"#));
    }
}
