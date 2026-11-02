//! The interpreter entrypoint: `nus <script> [args...]`, what a `#!/usr/bin/env nus`
//! line runs when anything outside Nushell executes the script.
//!
//! usage's own parser reads the arguments against the script's header, so help, errors,
//! defaults and `negate` are usage's. The `$usage` record is built from the parse, and the
//! script runs in the `nu` on PATH, as Nushell runs any script: what nusage hands it is the
//! definitions of the scripts it calls ([`crate::calls`]), from a file of their own, then
//! `let usage = ...; $in | run <script>`. A script inside a tree (a `mod.nu` beside it) is
//! parsed as that tree's command, with its siblings as providers and its ancestors'
//! globals; a script on its own is its own root. The interpreter becomes that `nu`, so the
//! script's value is shown as Nushell shows it, an error reported as Nushell reports it, and
//! the exit code the script's.

use std::io::IsTerminal;
use std::path::{Path, PathBuf};
use std::process::Command as Process;

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
    let (parsed, run) = route(script, args)?;
    let record = match parsed {
        Parsed::Help(page) => {
            println!("{page}");
            return Ok(0);
        }
        Parsed::Rejected(why) => {
            eprintln!("{why}");
            return Ok(2);
        }
        Parsed::Record(record) => record,
    };
    let path = std::path::absolute(&run)
        .map_err(|err| Diagnostic::new(script, format!("cannot resolve: {err}")))?;
    let code = program(&path, &record)?;
    let mut nu = Process::new(crate::nu::real_nu());
    // The script's `$in` is standard input when something is piped in, read only if the
    // script reads it. A terminal, a socket or a closed descriptor gives the script no input.
    if stdin_is_stream() || (!cfg!(unix) && !std::io::stdin().is_terminal()) {
        nu.arg("--stdin");
    }
    nu.arg("-c").arg(code);
    crate::nu::replace_with(&mut nu).map_err(|err| {
        Diagnostic::new(
            script,
            format!("cannot run the `nu` on PATH, which nusage runs scripts in: {err}"),
        )
    })
}

/// What the interpreter hands `nu` for the script at `script` with `record` as its
/// `$usage`: the definitions of the scripts it calls, `source`d from a file named by its
/// contents, then the record and the script `run` with the input. The definitions are
/// written once for each of their contents, so a command line holds no more than the
/// record and two paths.
pub fn program(script: &Path, record: &Value) -> Result<String, Diagnostic> {
    let definitions = crate::prelude::runtime(script)?;
    let mut code = String::new();
    if !definitions.is_empty() {
        let file = written(&definitions).map_err(|err| {
            Diagnostic::new(script, format!("cannot keep its definitions: {err}"))
        })?;
        code.push_str(&format!(
            "source {}\n",
            nusage_nu::word(&file.to_string_lossy())
        ));
    }
    code.push_str(&format!("let usage = {}\n", nusage_nu::nuon(record)));
    code.push_str(&format!(
        "$in | run {}\n",
        nusage_nu::word(&script.to_string_lossy())
    ));
    Ok(code)
}

/// `text` in the user's cache, in a file named by what it holds: written when no file holds
/// it yet, beside it first and then moved, so a run reading it never sees half of it.
fn written(text: &str) -> std::io::Result<PathBuf> {
    let dir = crate::common::cache_dir()
        .join("nusage")
        .join("definitions");
    let name = crate::common::fnv1a(text.bytes());
    let file = dir.join(format!("{name}.nu"));
    if std::fs::read_to_string(&file).ok().as_deref() == Some(text) {
        return Ok(file);
    }
    std::fs::create_dir_all(&dir)?;
    let partial = dir.join(format!(".{name}.{}", std::process::id()));
    std::fs::write(&partial, text)?;
    std::fs::rename(&partial, &file)?;
    Ok(file)
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
