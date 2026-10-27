use std::path::PathBuf;
use std::process::ExitCode;

use usage_rs::{Args, Cli, Run, Subcommands};

/// Typed Nushell commands from usage-annotated scripts
#[derive(Cli)]
#[usage(bin = "nusage", version)]
struct Nusage {
    #[usage(subcommand)]
    command: Commands,
}

#[derive(Subcommands)]
#[usage(run)]
enum Commands {
    Generate(Generate),
    Spec(Spec),
}

/// Write the module for a script, a tree of scripts, or a usage spec of a binary
///
/// A script's interface is the `#USAGE` header at the top of the file. A directory is a tree:
/// its `mod.nu` is the root command, each `x.nu` the subcommand `x`, each subdirectory with
/// its own `mod.nu` a group. The module defines one typed command per script whose body
/// hands the script its `$usage` record and `run`s it. A `.kdl` spec file describes a binary
/// on PATH: the module defines an `extern` per command under its full name, for
/// `use <file> *`; the file cannot be named `<bin>.nu`.
#[derive(Args)]
struct Generate {
    /// The script, the directory of scripts, or the `.kdl` spec file
    source: PathBuf,
    /// Where to write the module; `run` paths are relative to it. Standard output when absent
    #[usage(long, short = 'o')]
    out: Option<PathBuf>,
}

impl Run for Generate {
    type Output = Result<(), String>;

    fn run(self) -> Self::Output {
        let module =
            nusage::generate(&self.source, self.out.as_deref()).map_err(|e| e.to_string())?;
        match &self.out {
            Some(out) => {
                std::fs::write(out, module).map_err(|err| format!("{}: {err}", out.display()))
            }
            None => {
                print!("{module}");
                Ok(())
            }
        }
    }
}

/// Print the assembled usage spec of a script or a tree, as KDL
///
/// The tree's per-file headers merged into one spec, which every usage tool can read.
#[derive(Args)]
struct Spec {
    /// The script, or the directory of scripts
    source: PathBuf,
}

impl Run for Spec {
    type Output = Result<(), String>;

    fn run(self) -> Self::Output {
        let spec = nusage::spec(&self.source).map_err(|e| e.to_string())?;
        print!("{spec}");
        Ok(())
    }
}

fn main() -> ExitCode {
    match Nusage::parse().command.run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(message) => {
            eprintln!("nusage: {message}");
            ExitCode::FAILURE
        }
    }
}
