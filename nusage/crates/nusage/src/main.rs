use std::path::PathBuf;
use std::process::ExitCode;

use nusage::Diagnostic;
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
    type Output = Result<(), Diagnostic>;

    fn run(self) -> Self::Output {
        let module = nusage::generate_with(&self.source, self.out.as_deref(), &self.overlay)?;
        match &self.out {
            Some(out) => std::fs::write(out, module)
                .map_err(|err| Diagnostic::new(out, err.to_string()).with_code("nusage::io")),
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
    type Output = Result<(), Diagnostic>;

    fn run(self) -> Self::Output {
        let spec = nusage::spec(&self.source, &self.overlay)?;
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
    type Output = Result<(), Diagnostic>;

    fn run(self) -> Self::Output {
        nusage::check(&self.source, &self.overlay, &self.module)
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
    type Output = Result<(), Diagnostic>;

    fn run(self) -> Self::Output {
        let overlay =
            nusage::switch_overlay(&self.source, &self.overlay, &self.switch, &self.framing)?;
        print!("{overlay}");
        Ok(())
    }
}

/// Validate JSON or JSONL, optionally passing checked data through
///
/// A schema file with no documents checks the schema alone. --auto discovers a schema
/// from the data, and --passthrough releases valid bytes on stdout; either defaults to
/// stdin. JSONL consumes a recognized inline NUON schema header and checks each record.
/// NUSAGE_SCHEMA_ALLOW is a JSON list of allowed URLs/path globs. NUSAGE_VALIDATE=off
/// bypasses pass-through checking. NUSAGE_DIAGNOSTICS=json selects JSON diagnostics.
#[derive(Args)]
struct Validate {
    /// The JSON Schema file; with --auto or --schema-json, the first input document
    schema: Option<PathBuf>,
    /// The JSON documents, '-' for standard input
    documents: Vec<PathBuf>,
    /// An embedded schema, as used by generated modules
    #[usage(long)]
    schema_json: Option<String>,
    /// Recognize schemas declared by the input; unknown declarations remain ordinary data
    #[usage(long)]
    auto: bool,
    /// One JSON document per line; stop at the first invalid record
    #[usage(long)]
    jsonl: bool,
    /// Write validated input to stdout, incrementally for JSONL
    #[usage(long)]
    passthrough: bool,
    /// Label the source in diagnostics, for example a wrapped command's stdout
    #[usage(long)]
    source: Option<String>,
    /// Diagnostic representation on stderr: human or json
    #[usage(long)]
    diagnostic_format: Option<String>,
    /// Internal transport for generated modules; implies --passthrough
    #[usage(long, hide)]
    nu: bool,
}

impl Run for Validate {
    type Output = Result<(), Diagnostic>;

    fn run(self) -> Self::Output {
        let format = self
            .diagnostic_format
            .or_else(|| std::env::var("NUSAGE_DIAGNOSTICS").ok())
            .unwrap_or_else(|| "human".into());
        let passthrough = self.passthrough || self.nu;
        let mut documents = self.documents;
        let schema = if self.auto || self.schema_json.is_some() {
            if let Some(document) = self.schema {
                documents.insert(0, document);
            }
            None
        } else {
            self.schema
        };
        let options = nusage::ValidationOptions {
            schema,
            schema_json: self.schema_json,
            auto: self.auto,
            jsonl: self.jsonl,
            passthrough,
            nu: self.nu,
            disabled: passthrough && std::env::var("NUSAGE_VALIDATE").as_deref() == Ok("off"),
            source: self.source,
            allow: std::env::var("NUSAGE_SCHEMA_ALLOW").ok(),
        };
        let result = if !matches!(format.as_str(), "human" | "json") {
            Err(
                Diagnostic::new("NUSAGE_DIAGNOSTICS", "expected human or json")
                    .with_code("nusage::diagnostic::format"),
            )
        } else {
            match std::env::var("NUSAGE_VALIDATE").as_deref() {
                Ok("off") if passthrough && !self.nu => {
                    nusage::passthrough(&documents, &mut std::io::stdout().lock())
                }
                Ok("off" | "auto") | Err(_) => {
                    nusage::validate_with(&options, &documents, &mut std::io::stdout().lock())
                }
                Ok(_) => Err(
                    nusage::Diagnostic::new("NUSAGE_VALIDATE", "expected auto or off")
                        .with_code("nusage::validation::options"),
                ),
            }
        };
        let findings = match result {
            Ok(findings) => findings,
            Err(d) if d.code == "nusage::io::broken_pipe" => return Ok(()),
            Err(d) => vec![d],
        };
        if findings.is_empty() {
            return Ok(());
        }
        if self.nu {
            if let Err(d) = nusage::write_packet(Err(&findings), &mut std::io::stdout().lock()) {
                if d.code == "nusage::io::broken_pipe" {
                    return Ok(());
                }
                return Err(d);
            }
            std::process::exit(1)
        }
        for finding in findings {
            report(&finding, Some(&format));
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
    type Output = Result<(), Diagnostic>;

    fn run(self) -> Self::Output {
        match nusage::parse(&self.script, &self.args)? {
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
                report(
                    &Diagnostic::new(&self.script, why).with_code("nusage::usage::arguments"),
                    None,
                );
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
                report(&err, None);
                ExitCode::FAILURE
            }
        };
    }
    match Nusage::parse().command.run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(message) => {
            report(&message, None);
            ExitCode::FAILURE
        }
    }
}

/// Both the interpreter and subcommands render the same diagnostic record.
fn report(diagnostic: &Diagnostic, format: Option<&str>) {
    let env = std::env::var("NUSAGE_DIAGNOSTICS").ok();
    if format.or(env.as_deref()) == Some("json") {
        let text = serde_json::to_string(diagnostic).unwrap_or_else(|error| {
            serde_json::json!({"code":"nusage::diagnostic::encode", "message":error.to_string()}).to_string()
        });
        eprintln!("{text}");
    } else {
        eprintln!("[{}] {diagnostic}", diagnostic.code);
    }
}
