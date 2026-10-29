use std::path::PathBuf;
use std::process::ExitCode;

use usage_rs::{Args, Cli, Run, Subcommands};

/// Typed Nushell commands from usage-annotated scripts
///
/// As an interpreter, `nusage <script> [args...]` runs a script whose first line is
/// `#!/usr/bin/env nusage`: the arguments are parsed against its `#USAGE` header and the
/// script runs in Nushell with its `$usage` record, as the generated module would run it.
///
/// Such a script calls another by its path, `./x.nu ...`, or as `nusage x.nu ...` or `nu x.nu
/// ...`: the call is that script's typed command, which runs it and returns its value typed,
/// while what it prints passes through. The path is the calling script's, not the working
/// directory's: `./x.nu` is the script beside it, wherever it runs from. `^./x.nu` is the plain
/// external, which returns text.
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
    Lsp(Lsp),
    Parse(Parse),
    Prelude(Prelude),
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
    /// argument. For outputs, selectors, media types, schemas, type annotations and `nusage-decode`
    /// pipelines a spec one does not own lacks; an `output`'s `nusage-args` child holds the
    /// words that ask for it where a `select` cannot, such as `--no-graph --template
    /// 'json(self)'`, and the wrapper owns the flags they name
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
/// `<document>:<path>: <what>`, and any finding is exit code 1; a check that did not run,
/// for a schema or document that cannot be read or a schema its metaschema refuses, is
/// exit code 2. What a binary prints for an `output` whose schema a spec or overlay
/// declares can be held to that schema this way, before a module decodes it.
#[derive(Args)]
struct Validate {
    /// The JSON Schema
    schema: PathBuf,
    /// The JSON documents, `-` for standard input
    documents: Vec<PathBuf>,
    /// Read each document as JSON lines: every line that is not blank is a document of its
    /// own, and a finding names the line, `<document>:<line>:<path>: <what>`
    #[usage(long)]
    lines: bool,
}

impl Run for Validate {
    type Output = Result<(), String>;

    fn run(self) -> Self::Output {
        let findings = match nusage::validate(&self.schema, &self.documents, self.lines) {
            Ok(findings) => findings,
            // Not a finding: nothing was held to anything, as the exit code says.
            Err(why) => {
                eprintln!("nusage: {why}");
                std::process::exit(2)
            }
        };
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

/// Print the line that stands in for a script's first where Nushell checks it
///
/// For an editor or a linter: with this line in place of the shebang, Nushell checks the
/// script as nusage runs it. The line binds `$usage` with its type, and defines a shadow for
/// each script the script calls by its path, as `./x.nu`, `nusage x.nu` or `nu x.nu`: that
/// script's typed command, named as the call writes it, which the interpreter and the module
/// define too. Every other line stays where it was. What the calls get wrong goes to
/// standard error, a line each, `<script>:<line>:<column>: <what>`.
#[derive(Args)]
struct Prelude {
    /// The script, whose shebang names nusage
    script: PathBuf,
    /// Print what the interpreter runs before the script instead: the shadows with their
    /// bodies, and the helpers they build an argv with
    #[usage(long)]
    run: bool,
}

impl Run for Prelude {
    type Output = Result<(), String>;

    fn run(self) -> Self::Output {
        if self.run {
            let nusage = std::env::current_exe().map_err(|err| err.to_string())?;
            print!(
                "{}",
                nusage::prelude_run(&self.script, &nusage).map_err(|e| e.to_string())?
            );
            return Ok(());
        }
        let (line, findings) = nusage::prelude(&self.script).map_err(|e| e.to_string())?;
        println!("{line}");
        for finding in findings {
            eprintln!("{finding}");
        }
        Ok(())
    }
}

/// Serve Nushell's language server for the scripts nusage runs
///
/// For an editor, in place of `nu --lsp`, which it starts and stands in front of. A script
/// whose shebang names nusage reaches Nushell with its first line replaced by the line `nusage
/// prelude` writes, so Nushell knows `$usage` and holds each call of another script to that
/// script's header; what the header and the calls get wrong joins Nushell's diagnostics, and
/// a definition of a called script leads to it. Every other line is the editor's, and any
/// other document passes as it is. Arguments after `--` go to `nu --lsp`.
#[derive(Args)]
struct Lsp {
    /// Arguments for `nu --lsp`, such as `--config <file>`
    args: Vec<String>,
}

impl Run for Lsp {
    type Output = Result<(), String>;

    fn run(self) -> Self::Output {
        let code = nusage::lsp(&self.args).map_err(|err| err.to_string())?;
        std::process::exit(code)
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
