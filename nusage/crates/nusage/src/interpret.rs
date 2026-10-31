//! The interpreter entrypoint: `nus <script> [args...]`, what a `#!/usr/bin/env nus`
//! line runs when anything outside Nushell executes the script.
//!
//! usage's own parser reads the arguments against the script's header, so help, errors,
//! defaults and `negate` are usage's. The record a shim would hand the script is built from
//! the parse the same way, from the same model, and the script runs with it in an engine of
//! this process, the executor's ([`crate::executor`]), exactly as the shim runs it: `let
//! usage = ...; $in | run <script>`. A script inside a tree (a `mod.nu` beside it) is parsed
//! as that tree's command, with its siblings as providers and its ancestors' globals; a
//! script on its own is its own root.
//!
//! Before the script, the engine defines the shadows of the scripts it calls, which run them
//! in the same engine ([`crate::calls`]). Run by a shadow of another process's, with
//! `NUS_OUTPUT_FILE` naming a file, the interpreter writes the script's value there as NUON
//! for the shadow to read, when `NUS_OUTPUT_SCRIPT` names this script or nothing: mise runs
//! a task's dependencies with the same variables. The script's own calls see neither. The
//! value is otherwise printed as Nushell shows it, and an error reported as Nushell reports
//! it, with the exit code the script gave.

use std::io::IsTerminal;
use std::path::{Path, PathBuf};

use nu_protocol::{Record, Span, Value};
use nusage_model::{Execution, Param, ParamKind, value_from_text};
use nusage_spec::Diagnostic;
use usage::parse::{ParseOutput, ParseValue};

/// What usage made of a script's arguments.
pub enum Parsed {
    /// The `$usage` record the script will see.
    Record(Value),
    /// The arguments asked for help; this is the page.
    Help(String),
    /// usage rejected the arguments; this is why.
    Rejected(String),
}

/// Parse the arguments against the script's header, as usage does, into the record a shim
/// would build. In a tree, the arguments may select a subcommand of the script's command,
/// as usage routes them, by name, alias or `default_subcommand`: the record is then that
/// command's, and [`interpret`] runs its script.
pub fn parse(script: &Path, args: &[String]) -> Result<Parsed, Diagnostic> {
    Ok(route(script, args)?.0)
}

/// [`parse`], with the script of the command the arguments selected: the one to run.
pub fn route(script: &Path, args: &[String]) -> Result<(Parsed, PathBuf), Diagnostic> {
    let (root, path) = crate::calls::place_in_tree(script)?;
    let assembled = nusage_spec::assemble(&root)?;
    let tree = nusage_model::model(&assembled)?;
    let command = tree
        .commands
        .iter()
        .find(|command| command.path == path)
        .ok_or_else(|| {
            Diagnostic::new(
                script,
                format!("the tree at {} has no command `{path}`", root.display()),
            )
        })?;
    let mut argv = vec![assembled.spec.bin.clone()];
    argv.extend(path.words().iter().cloned());
    argv.extend(args.iter().cloned());
    // usage would run a `choices run=` command to check a value; here that command is a
    // Nushell script, and the shim does not check either.
    let parser = usage::parse::Parser::new(&assembled.spec).without_running_commands();
    let parsed = match parser.parse(&argv) {
        Ok(parsed) => parsed,
        // usage renders help as the error for `--help`; anything else is a usage error.
        Err(err) if args.iter().any(|arg| arg == "--help" || arg == "-h") => {
            return Ok((Parsed::Help(err.to_string()), script.to_path_buf()));
        }
        Err(err) => return Ok((Parsed::Rejected(err.to_string()), script.to_path_buf())),
    };
    // The command usage selected, which the script's own when nothing routed deeper.
    let mut selected: &[String] = &parsed.cmd.full_cmd;
    if selected.first() == Some(&assembled.spec.bin) {
        selected = &selected[1..];
    }
    let command = tree
        .commands
        .iter()
        .find(|candidate| candidate.path.words() == selected)
        .unwrap_or(command);
    let record =
        usage_record(command, &parsed).map_err(|message| Diagnostic::new(script, message))?;
    let run = match &command.execution {
        Execution::Script(body) => body.clone(),
        // The interpreter runs scripts; a spec's commands never reach it.
        Execution::External | Execution::Request(_) | Execution::Service => script.to_path_buf(),
    };
    Ok((Parsed::Record(record), run))
}

/// Run the script with the arguments; the exit code is the script's, or 0 after printing
/// help, or 2 when usage rejects the arguments.
pub fn interpret(script: &Path, args: &[String]) -> Result<i32, Diagnostic> {
    use nusage_plugin::nu_protocol::{ByteStream, PipelineData, ShellError};

    let (parsed, run) = route(script, args)?;
    if let Parsed::Help(page) = &parsed {
        println!("{page}");
        return Ok(0);
    }
    if let Parsed::Rejected(why) = &parsed {
        eprintln!("{why}");
        return Ok(2);
    }
    let path = std::path::absolute(&run)
        .map_err(|err| Diagnostic::new(script, format!("cannot resolve: {err}")))?;
    // The script runs in an engine of this process, as a called script does in the plugin's.
    // What addresses this process, the value file the caller named, is kept from the
    // script's own calls, which return their values inside the engine.
    let executor = std::sync::Arc::new(crate::executor::Executor::new());
    crate::commands::Commands::new(executor.clone()).map_err(|err| Diagnostic::new(script, err))?;
    let asked = match std::env::var_os(crate::calls::OUTPUT_VAR) {
        Some(file) if !file.is_empty() && value_is_asked_of(&path) => Some(PathBuf::from(file)),
        _ => None,
    };
    let cx = crate::executor::ProcessContext::without(&[
        crate::calls::OUTPUT_VAR,
        crate::calls::OUTPUT_SCRIPT_VAR,
    ]);
    let span = Span::unknown();
    // The script's `$in` is standard input when something is piped in, read only if the
    // script reads it. A terminal, a socket or a closed descriptor gives the script no input.
    let input = if stdin_is_stream() || (!cfg!(unix) && !std::io::stdin().is_terminal()) {
        match ByteStream::stdin(span) {
            Ok(stream) => PipelineData::byte_stream(stream, None),
            Err(_) => PipelineData::empty(),
        }
    } else {
        PipelineData::empty()
    };
    let named = std::path::absolute(script)
        .map_err(|err| Diagnostic::new(script, format!("cannot resolve: {err}")))?;
    let outcome = match executor.run(&cx, &named, args, input, span) {
        Ok(data) => deliver(&executor, data, asked.as_deref(), span),
        Err(err) => Err(err),
    };
    match outcome {
        Ok(()) => Ok(0),
        Err(ShellError::Exit { code, .. }) => Ok(code),
        Err(err) => {
            let code = err.exit_code().unwrap_or(1);
            executor.report(&err);
            Ok(if code == 0 { 1 } else { code })
        }
    }
}

/// The script's value where the caller wants it: as NUON in the file the caller named, or
/// on standard output as Nushell shows it.
#[allow(clippy::result_large_err)]
fn deliver(
    executor: &crate::executor::Executor,
    data: nusage_plugin::nu_protocol::PipelineData,
    asked: Option<&Path>,
    span: Span,
) -> Result<(), nusage_plugin::nu_protocol::ShellError> {
    use nusage_plugin::nu_protocol::{LabeledError, ShellError};
    match asked {
        Some(file) => {
            let value = data.into_value(span)?;
            std::fs::write(file, nusage_nu::nuon(&value)).map_err(|err| {
                ShellError::from(LabeledError::new(format!("{}: {err}", file.display())))
            })
        }
        None => executor.print(data),
    }
}

/// Whether the caller asks this script for its value: the one it names, or any when it names
/// none.
fn value_is_asked_of(script: &Path) -> bool {
    match std::env::var_os(crate::calls::OUTPUT_SCRIPT_VAR) {
        Some(asked) if !asked.is_empty() => {
            let asked = Path::new(&asked);
            match (std::fs::canonicalize(asked), std::fs::canonicalize(script)) {
                (Ok(asked), Ok(script)) => asked == script,
                _ => asked == script,
            }
        }
        _ => true,
    }
}

/// Whether standard input is a pipe or a regular file: what `/dev/stdin` opens as a stream.
#[cfg(unix)]
fn stdin_is_stream() -> bool {
    use std::os::unix::fs::FileTypeExt;
    std::fs::metadata("/dev/stdin")
        .map(|meta| meta.file_type().is_fifo() || meta.file_type().is_file())
        .unwrap_or(false)
}

#[cfg(not(unix))]
fn stdin_is_stream() -> bool {
    false
}

/// The `$usage` record: `{cmd, args, flags}`, as the shim builds it.
fn usage_record(command: &nusage_model::Command, parsed: &ParseOutput) -> Result<Value, String> {
    let span = Span::unknown();
    // A clause's instances are flattened: a repeated positional collects every instance's
    // values, any other parameter takes the first instance's.
    let clause = command.clause.as_deref().unwrap_or_default();
    let instances = parsed.clauses.get(clause).into_iter().flatten();
    let instance_flags = parsed.clause_flags.get(clause).into_iter().flatten();
    let mut args = Record::new();
    for param in &command.positionals {
        let found = if param.clause {
            let mut found: Vec<&ParseValue> = instances
                .clone()
                .filter_map(|instance| {
                    instance
                        .iter()
                        .find(|(arg, _)| arg.name == param.usage_name)
                        .map(|(_, value)| value)
                })
                .collect();
            if param.kind == ParamKind::Rest {
                let items: Vec<String> = found
                    .iter()
                    .flat_map(|value| match value {
                        ParseValue::MultiString(items) => items.clone(),
                        ParseValue::String(item) => vec![item.clone()],
                        _ => Vec::new(),
                    })
                    .collect();
                args.push(
                    param.var.clone(),
                    positional_value(param, Some(&ParseValue::MultiString(items)))?,
                );
                continue;
            }
            found.drain(..).next()
        } else {
            parsed
                .args
                .iter()
                .find(|(arg, _)| arg.name == param.usage_name)
                .map(|(_, value)| value)
        };
        args.push(param.var.clone(), positional_value(param, found)?);
    }
    let mut flags = Record::new();
    for param in &command.flags {
        let found = if param.clause {
            instance_flags.clone().find_map(|instance| {
                instance
                    .iter()
                    .find(|(flag, _)| flag.name == param.usage_name)
                    .map(|(_, value)| value)
            })
        } else {
            parsed
                .flags
                .iter()
                .find(|(flag, _)| flag.name == param.usage_name)
                .map(|(_, value)| value)
        };
        flags.push(param.var.clone(), flag_value(param, found)?);
    }
    // Whatever else the call bound on the way to the command, as usage reports it: an
    // ancestor's own flag before a default subcommand's word, a sigil argument. A declared
    // parameter is typed and defaulted above; these are as bound.
    for (arg, value) in &parsed.args {
        let name = nusage_model::identifier(&arg.name).var;
        if !args.contains(&name) {
            args.push(name, as_bound(value));
        }
    }
    for (flag, value) in &parsed.flags {
        let name = nusage_model::identifier(&flag.name).var;
        if !flags.contains(&name) {
            flags.push(name, as_bound(value));
        }
    }
    let mut record = Record::new();
    record.push(
        "cmd",
        Value::list(
            command
                .path
                .words()
                .iter()
                .map(|word| Value::string(word, span))
                .collect(),
            span,
        ),
    );
    record.push("args", Value::record(args, span));
    record.push("flags", Value::record(flags, span));
    // The words after an `external_subcommand`, when the command declares one and the call
    // reached it.
    if let Some(external) = &parsed.external {
        record.push(
            "external",
            Value::list(
                external
                    .iter()
                    .map(|word| Value::string(word, span))
                    .collect(),
                span,
            ),
        );
    }
    Ok(Value::record(record, span))
}

fn positional_value(param: &Param, found: Option<&ParseValue>) -> Result<Value, String> {
    let span = Span::unknown();
    let typed = |text: &str| value_from_text(text, &param.ty);
    Ok(match (param.kind, found) {
        (ParamKind::Rest, None) => Value::list(Vec::new(), span),
        (ParamKind::Rest, Some(ParseValue::MultiString(items))) => Value::list(
            items
                .iter()
                .map(|item| typed(item))
                .collect::<Result<_, _>>()?,
            span,
        ),
        (ParamKind::Rest, Some(ParseValue::String(item))) => Value::list(vec![typed(item)?], span),
        (_, None) => Value::nothing(span),
        (_, Some(ParseValue::String(text))) => typed(text)?,
        (_, Some(ParseValue::MultiString(items))) => match items.first() {
            Some(text) => typed(text)?,
            None => Value::nothing(span),
        },
        (_, Some(other)) => {
            return Err(format!(
                "usage parsed `{}` as {other:?}, not a value",
                param.usage_name
            ));
        }
    })
}

/// A value as usage bound it, untyped: text, a list of text, a switch, a count.
fn as_bound(value: &ParseValue) -> Value {
    let span = Span::unknown();
    match value {
        ParseValue::String(text) => Value::string(text, span),
        ParseValue::MultiString(items) => Value::list(
            items.iter().map(|item| Value::string(item, span)).collect(),
            span,
        ),
        ParseValue::Bool(flag) => Value::bool(*flag, span),
        ParseValue::MultiBool(flags) => {
            Value::int(flags.iter().filter(|on| **on).count() as i64, span)
        }
    }
}

fn flag_value(param: &Param, found: Option<&ParseValue>) -> Result<Value, String> {
    let span = Span::unknown();
    let typed = |text: &str| value_from_text(text, &param.ty);
    Ok(match (param.kind, found) {
        (ParamKind::Switch, None) => Value::bool(false, span),
        (ParamKind::Switch, Some(ParseValue::Bool(on))) => Value::bool(*on, span),
        (ParamKind::Count, None) => Value::int(0, span),
        (ParamKind::Count, Some(ParseValue::MultiBool(each))) => {
            Value::int(each.len() as i64, span)
        }
        (ParamKind::Count, Some(ParseValue::Bool(on))) => Value::int(i64::from(*on), span),
        (ParamKind::Repeated, None) => Value::list(Vec::new(), span),
        (ParamKind::Repeated, Some(ParseValue::MultiString(items))) => Value::list(
            items
                .iter()
                .map(|item| typed(item))
                .collect::<Result<_, _>>()?,
            span,
        ),
        (ParamKind::Repeated, Some(ParseValue::String(item))) => {
            Value::list(vec![typed(item)?], span)
        }
        (ParamKind::Valued, None) => Value::nothing(span),
        (ParamKind::Valued, Some(ParseValue::String(text))) => typed(text)?,
        (_, Some(other)) => {
            return Err(format!(
                "usage parsed `--{}` as {other:?}, which its kind does not take",
                param.usage_name
            ));
        }
        (kind, _) => return Err(format!("`{}` is a {kind:?}, not a flag", param.usage_name)),
    })
}
