use std::path::PathBuf;
use std::process::ExitCode;

use usage_rs::{Args, Cli, Run, Subcommands};

/// Typed Nushell commands from usage-annotated scripts
///
/// As an interpreter, `nusage <script> [args...]` runs a script whose first line is
/// `#!/usr/bin/env nusage`: the arguments are parsed against its `#USAGE` header and the
/// script runs in Nushell with its `$usage` record, as the generated module would run it.
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
    Check(Check),
    Overlay(Overlay),
    Parse(Parse),
    Validate(Validate),
}

/// Write the module for a script, a tree of scripts, or a usage spec of a binary
///
/// A script's interface is the `#USAGE` header at the top of the file. A directory is a tree:
/// its `mod.nu` is the root command, each `x.nu` the subcommand `x`, each subdirectory with
/// its own `mod.nu` a group. The module defines one typed command per script whose body
/// hands the script its `$usage` record and `run`s it. A `.kdl` spec file describes a binary
/// on PATH: the module defines a command per command of the binary that runs it and decodes
/// its output; write it as `<bin>.nu` and `use <bin>.nu *`.
#[derive(Args)]
struct Generate {
    /// The script, the directory of scripts, or the `.kdl` spec file
    source: PathBuf,
    /// Where to write the module; `run` paths are relative to it. Standard output when absent
    #[usage(long, short = 'o')]
    out: Option<PathBuf>,
    /// A usage KDL document merged onto the spec file first: a `cmd` merges into the command
    /// of the same name, any other node replaces the one with the same name and first
    /// argument. For outputs, selectors, schemas and type annotations a spec one does not
    /// own lacks; an `output`'s `nusage-args` child holds the words that ask for it where a
    /// `select` cannot, such as `--no-graph --template 'json(self)'`, and the wrapper owns
    /// the flags they name
    #[usage(long)]
    overlay: Vec<PathBuf>,
}

impl Run for Generate {
    type Output = Result<(), String>;

    fn run(self) -> Self::Output {
        let module = nusage::generate_with(&self.source, self.out.as_deref(), &self.overlay)
            .map_err(|e| e.to_string())?;
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
    /// The script, the directory of scripts, or the `.kdl` spec file
    source: PathBuf,
    /// A usage KDL document merged onto the spec file first, as for `generate`
    #[usage(long)]
    overlay: Vec<PathBuf>,
}

impl Run for Spec {
    type Output = Result<(), String>;

    fn run(self) -> Self::Output {
        let spec = nusage::spec(&self.source, &self.overlay).map_err(|e| e.to_string())?;
        print!("{spec}");
        Ok(())
    }
}

/// Check a generated module against the spec of its source
///
/// Every command the spec shows must be a definition with the spec's positionals, flags
/// and completers, named as `generate` names them, with its description once. The spec is
/// read by usage itself, so this holds the generator to usage rather than to its own model;
/// `generate` runs the same check on what it writes.
#[derive(Args)]
struct Check {
    /// The script, the directory of scripts, or the `.kdl` spec file the module was
    /// generated from
    source: PathBuf,
    /// The generated module
    module: PathBuf,
    /// A usage KDL document merged onto the spec file first, as for `generate`
    #[usage(long)]
    overlay: Vec<PathBuf>,
}

impl Run for Check {
    type Output = Result<(), String>;

    fn run(self) -> Self::Output {
        nusage::check(&self.source, &self.overlay, &self.module).map_err(|e| e.to_string())
    }
}

/// Print an overlay declaring a framed output for every command that has a switch
///
/// For a binary whose spec declares no `output` but whose commands share a switch that
/// selects one, such as `--json`: every command with the switch gets `output <framing>
/// framing=<framing> select=<switch>`, so its wrapper asks for and decodes that output. Save
/// it and pass it to `generate --overlay`; a second overlay adds the types. A command already
/// declaring such an output is left alone.
#[derive(Args)]
struct Overlay {
    /// The `.kdl` spec file
    source: PathBuf,
    /// A usage KDL document merged onto the spec file first, as for `generate`
    #[usage(long)]
    overlay: Vec<PathBuf>,
    /// The switch that selects the output, with its dashes, so written `--switch=--json`
    #[usage(long)]
    switch: String,
    /// The output's framing: `json` for one document, `jsonl` for one per line
    #[usage(long)]
    framing: String,
}

impl Run for Overlay {
    type Output = Result<(), String>;

    fn run(self) -> Self::Output {
        let overlay =
            nusage::switch_overlay(&self.source, &self.overlay, &self.switch, &self.framing)
                .map_err(|e| e.to_string())?;
        print!("{overlay}");
        Ok(())
    }
}

/// Hold JSON documents to a JSON Schema
///
/// The schema is held to its metaschema first, then each document to the schema; `-` is
/// standard input, and no document holds the schema alone. Every finding is a line,
/// `<document>:<path>: <what>`, and any finding is exit code 1. What a binary prints for
/// an `output` whose schema a spec or overlay declares can be held to that schema this way,
/// before a module decodes it.
#[derive(Args)]
struct Validate {
    /// The JSON Schema
    schema: PathBuf,
    /// The JSON documents, `-` for standard input
    documents: Vec<PathBuf>,
}

impl Run for Validate {
    type Output = Result<(), String>;

    fn run(self) -> Self::Output {
        let findings = nusage::validate(&self.schema, &self.documents)?;
        if findings.is_empty() {
            return Ok(());
        }
        for finding in findings {
            eprintln!("{finding}");
        }
        std::process::exit(1)
    }
}

/// Print the `$usage` record a script would see for the arguments, as NUON
///
/// What `nusage <script> [args...]` hands the script, without running it: the arguments
/// parsed by usage against the `#USAGE` header. Put the script's arguments after `--`.
#[derive(Args)]
struct Parse {
    /// The script
    script: PathBuf,
    /// The script's arguments
    args: Vec<String>,
}

impl Run for Parse {
    type Output = Result<(), String>;

    fn run(self) -> Self::Output {
        match nusage::parse(&self.script, &self.args).map_err(|e| e.to_string())? {
            nusage::Parsed::Record(record) => {
                println!("{}", nusage_nu::nuon(&record));
                Ok(())
            }
            nusage::Parsed::Help(page) => {
                println!("{page}");
                Ok(())
            }
            // usage's refusal, with the exit code the interpreter gives it.
            nusage::Parsed::Rejected(why) => {
                eprintln!("{why}");
                std::process::exit(2)
            }
        }
    }
}

fn main() -> ExitCode {
    // `nusage <script> [args...]`, the shebang form: the first argument names a file. The
    // subcommands are words, never files.
    let argv: Vec<String> = std::env::args().collect();
    if let Some(first) = argv.get(1)
        && std::path::Path::new(first).is_file()
    {
        return match nusage::interpret(std::path::Path::new(first), &argv[2..]) {
            Ok(code) => ExitCode::from(code.clamp(0, 255) as u8),
            Err(err) => {
                eprintln!("nusage: {err}");
                ExitCode::FAILURE
            }
        };
    }
    match Nusage::parse().command.run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(message) => {
            eprintln!("nusage: {message}");
            ExitCode::FAILURE
        }
    }
}
