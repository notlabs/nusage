//! The command line: the subcommands of `nus`, as usage-rs derives them, and what each
//! runs. Here rather than in `main.rs` so that the CLI's own usage spec, [`Nusage::to_kdl`],
//! is a library value: a plugin takes its signatures from it, so a command inside Nushell and
//! the same command on the command line are one interface, declared once.

use std::path::PathBuf;

use usage_rs::{Args, Cli, Run, Subcommands};

/// Typed Nushell commands from usage-annotated scripts
///
/// As an interpreter, `nus <script> [args...]` runs a script whose first line is
/// `#!/usr/bin/env nus`: the arguments are parsed against its `#USAGE` header and the
/// script runs in Nushell with its `$usage` record, as the generated module would run it.
///
/// Such a script calls another by its path, `./x.nu ...`, or as `nus x.nu ...` or `nu x.nu
/// ...`: the call is that script's typed command, which runs it and returns its value typed,
/// while what it prints passes through. The path is the calling script's, not the working
/// directory's: `./x.nu` is the script beside it, wherever it runs from. `^./x.nu` is the plain
/// external, which returns text.
#[derive(Cli)]
#[usage(name = "nus", bin = "nus", version)]
pub struct Nusage {
    #[usage(subcommand)]
    pub command: Commands,
}

#[derive(Subcommands)]
#[usage(run)]
pub enum Commands {
    Generate(Generate),
    Spec(Spec),
    Model(Model),
    Check(Check),
    Overlay(Overlay),
    Lsp(Lsp),
    Nu(Nu),
    Parse(Parse),
    Prelude(Prelude),
    Inspect(Inspect),
    Validate(Validate),
    Call(Call),
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
pub struct Generate {
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
    /// The HTTP mapping beside a spec that describes a service, `<name>.http.kdl` as
    /// `openapi-usage` writes it: then each command's wrapper sends the request the mapping
    /// says, with the body as its input, and decodes the response as a binary's output.
    /// The service's base URL and credentials come from the environment, `$env.<NAME>_URL`
    /// and `$env.<NAME>_TOKEN`, as the module's helpers say
    #[usage(long)]
    http: Option<PathBuf>,
}

impl Run for Generate {
    type Output = Result<(), String>;

    fn run(self) -> Self::Output {
        let module = crate::generate_with(
            &self.source,
            self.out.as_deref(),
            &self.overlay,
            self.http.as_deref(),
        )
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
pub struct Spec {
    /// The script, the directory of scripts, or the `.kdl` spec file
    source: PathBuf,
    /// A usage KDL document merged onto the spec file first, as for `generate`
    #[usage(long)]
    overlay: Vec<PathBuf>,
}

impl Run for Spec {
    type Output = Result<(), String>;

    fn run(self) -> Self::Output {
        let spec = crate::spec(&self.source, &self.overlay).map_err(|e| e.to_string())?;
        print!("{spec}");
        Ok(())
    }
}

/// Print the command model of a script, a tree or a spec, as NUON
///
/// What a target is handed: every command with its parameters, their types and defaults,
/// its output and how a binary's or a service's is selected and decoded, and what runs when
/// it is called, after every decision between usage's vocabulary and a Nushell signature is
/// made and before any Nushell is written. `spec` prints the stage before it, `generate`
/// the one after.
#[derive(Args)]
pub struct Model {
    /// The script, the directory of scripts, or the `.kdl` spec file
    source: PathBuf,
    /// A usage KDL document merged onto the spec file first, as for `generate`
    #[usage(long)]
    overlay: Vec<PathBuf>,
    /// The HTTP mapping beside the spec, as for `generate`
    #[usage(long)]
    http: Option<PathBuf>,
}

impl Run for Model {
    type Output = Result<(), String>;

    fn run(self) -> Self::Output {
        let model = crate::model(&self.source, &self.overlay, self.http.as_deref())
            .map_err(|e| e.to_string())?;
        println!("{model}");
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
pub struct Check {
    /// The script, the directory of scripts, or the `.kdl` spec file the module was
    /// generated from
    source: PathBuf,
    /// The generated module
    module: PathBuf,
    /// A usage KDL document merged onto the spec file first, as for `generate`
    #[usage(long)]
    overlay: Vec<PathBuf>,
    /// The HTTP mapping beside the spec, as for `generate`
    #[usage(long)]
    http: Option<PathBuf>,
}

impl Run for Check {
    type Output = Result<(), String>;

    fn run(self) -> Self::Output {
        crate::check(
            &self.source,
            &self.overlay,
            self.http.as_deref(),
            &self.module,
        )
        .map_err(|e| e.to_string())
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
pub struct Overlay {
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
            crate::switch_overlay(&self.source, &self.overlay, &self.switch, &self.framing)
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
pub struct Validate {
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
        let findings = match crate::validate(&self.schema, &self.documents, self.lines) {
            Ok(findings) => findings,
            // Not a finding: nothing was held to anything, as the exit code says.
            Err(why) => {
                eprintln!("nus: {why}");
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

/// Run a script as a call of it, and print its value as NUON
///
/// What the shadow of a called script does: `nus call <script> nus <script> [args]...` runs
/// the script in an engine of this process with its `$usage` from the arguments, and
/// `nus call <script> mise -C <dir> run <task>` runs the task through mise, which writes
/// the script's value to the file `NUS_OUTPUT_FILE` names. The value is printed as NUON;
/// what the script prints passes through. Put the program's arguments after `--` when they
/// carry flags. Inside Nushell the same command is the plugin's, returning the value itself.
#[derive(Args)]
pub struct Call {
    /// The script that is called
    script: PathBuf,
    /// The program that runs it, `nus` or `mise`
    program: String,
    /// The program's arguments
    args: Vec<String>,
}

impl Run for Call {
    type Output = Result<(), String>;

    fn run(self) -> Self::Output {
        use nusage_plugin::nu_protocol::{PipelineData, Span, Value};
        let executor = std::sync::Arc::new(crate::executor::Executor::new());
        let commands = crate::commands::Commands::new(executor)?;
        let mut words = vec![self.script.to_string_lossy().into_owned(), self.program];
        words.extend(self.args);
        let args = nusage_plugin::Args::new(
            Span::unknown(),
            words
                .into_iter()
                .map(|w| Value::string(w, Span::unknown()))
                .collect(),
            Vec::new(),
        );
        let out = nusage_plugin::Run::run(
            &commands.call,
            &crate::executor::ProcessContext,
            &args,
            PipelineData::empty(),
        )
        .map_err(|err| crate::executor::describe(&err))?;
        let value = out
            .into_value(Span::unknown())
            .map_err(|err| err.to_string())?;
        if !matches!(value, Value::Nothing { .. }) {
            println!("{}", nusage_nu::nuon(&value));
        }
        Ok(())
    }
}

/// Print the `$usage` record a script would see for the arguments, as NUON
///
/// What `nus <script> [args...]` hands the script, without running it: the arguments
/// parsed by usage against the `#USAGE` header. Put the script's arguments after `--`.
#[derive(Args)]
pub struct Parse {
    /// The script
    script: PathBuf,
    /// The script's arguments
    args: Vec<String>,
}

impl Run for Parse {
    type Output = Result<(), String>;

    fn run(self) -> Self::Output {
        match crate::parse(&self.script, &self.args).map_err(|e| e.to_string())? {
            crate::Parsed::Record(record) => {
                println!("{}", nusage_nu::nuon(&record));
                Ok(())
            }
            crate::Parsed::Help(page) => {
                println!("{page}");
                Ok(())
            }
            // usage's refusal, with the exit code the interpreter gives it.
            crate::Parsed::Rejected(why) => {
                eprintln!("{why}");
                std::process::exit(2)
            }
        }
    }
}

/// Inspect a script's resolved calls and findings as JSON, without running it
///
/// The same analysis as the interpreter and language server. Calls are resolved command
/// shadows, not a complete dependency graph; paths are absolute and finding spans are
/// UTF-8 byte offsets. Header and call findings remain structured data in the result.
#[derive(Args)]
pub struct Inspect {
    /// The script whose shebang names nusage
    script: PathBuf,
}

impl Run for Inspect {
    type Output = Result<(), String>;

    fn run(self) -> Self::Output {
        let inspection = crate::inspect(&self.script).map_err(|e| e.to_string())?;
        println!(
            "{}",
            serde_json::to_string_pretty(&inspection).map_err(|e| e.to_string())?
        );
        Ok(())
    }
}

/// Print the line that stands in for a script's first where Nushell checks it
///
/// For an editor or a linter: with this line in place of the shebang, Nushell checks the
/// script as nusage runs it. The line binds `$usage` with its type, and defines a shadow for
/// each script the script calls by its path, as `./x.nu`, `nus x.nu` or `nu x.nu`: that
/// script's typed command, named as the call writes it, which the interpreter and the module
/// define too. Every other line stays where it was. What the calls get wrong goes to
/// standard error, a line each, `<script>:<line>:<column>: <what>`.
#[derive(Args)]
pub struct Prelude {
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
                crate::prelude_run(&self.script, &nusage).map_err(|e| e.to_string())?
            );
            return Ok(());
        }
        let (line, findings) = crate::prelude(&self.script).map_err(|e| e.to_string())?;
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
pub struct Lsp {
    /// Arguments for `nu --lsp`, such as `--config <file>`
    args: Vec<String>,
}

impl Run for Lsp {
    type Output = Result<(), String>;

    fn run(self) -> Self::Output {
        let code = crate::lsp(&self.args).map_err(|err| err.to_string())?;
        std::process::exit(code)
    }
}

/// Run as `nu`, as mise's command wrapper does
///
/// In the `nus-lsp` environment mise starts every `nu` as `nus nu`, so an editor that
/// starts `nu --lsp` gets nusage's language server unasked: kakehashi with nusage's layer when
/// kakehashi is on PATH, which highlights a script's header and bridges the script to `nusage
/// lsp`, else `nus lsp` alone. Anything else is `nu` itself, as it was asked for. The
/// arguments are Nushell's, flags included.
#[derive(Args)]
pub struct Nu {
    /// Nushell's arguments
    args: Vec<String>,
}

impl Run for Nu {
    type Output = Result<(), String>;

    fn run(self) -> Self::Output {
        let code = crate::nu(&self.args).map_err(|err| err.to_string())?;
        std::process::exit(code)
    }
}
