//! The interpreter entrypoint: `nusage <script> [args...]`, what a `#!/usr/bin/env nusage`
//! line runs when anything outside Nushell executes the script.
//!
//! usage's own parser reads the arguments against the script's header, so help, errors,
//! defaults and `negate` are usage's. The record a shim would hand the script is built from
//! the parse the same way, from the same model, and Nushell runs the script with it exactly
//! as the shim does: `let usage = ...; $in | run <script>`. A script inside a tree (a
//! `mod.nu` beside it) is parsed as that tree's command, with its siblings as providers and
//! its ancestors' globals; a script on its own is its own root.

use std::io::IsTerminal;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use nu_protocol::{Record, Span, Value};
use nusage_model::{Param, ParamKind, value_from_text};
use nusage_spec::{CommandPath, Diagnostic};
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
/// would build.
pub fn parse(script: &Path, args: &[String]) -> Result<Parsed, Diagnostic> {
    let (root, path) = place_in_tree(script)?;
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
            return Ok(Parsed::Help(err.to_string()));
        }
        Err(err) => return Ok(Parsed::Rejected(err.to_string())),
    };
    let record =
        usage_record(command, &parsed).map_err(|message| Diagnostic::new(script, message))?;
    Ok(Parsed::Record(record))
}

/// Run the script with the arguments; the exit code is the script's, or 0 after printing
/// help, or 2 when usage rejects the arguments.
pub fn interpret(script: &Path, args: &[String]) -> Result<i32, Diagnostic> {
    let record = match parse(script, args)? {
        Parsed::Record(record) => record,
        Parsed::Help(page) => {
            println!("{page}");
            return Ok(0);
        }
        Parsed::Rejected(why) => {
            eprintln!("{why}");
            return Ok(2);
        }
    };
    let path = std::path::absolute(script)
        .map_err(|err| Diagnostic::new(script, format!("cannot resolve: {err}")))?;
    // The script's `$in` is standard input when something is piped in, read only if the
    // script reads it: `nu --stdin` would read a pipe to its end before the script runs, so
    // on unix a pipe or a file is opened as a stream through `/dev/stdin` instead. A
    // terminal, a socket or a closed descriptor gives the script no input.
    let script_word = nusage_nu::word(&path.to_string_lossy());
    let mut nu = Command::new("nu");
    let code = if cfg!(unix) {
        if stdin_is_stream() {
            format!(
                "let usage = ($env.NUSAGE_USAGE | from nuon); open --raw /dev/stdin | run {script_word}"
            )
        } else {
            format!("let usage = ($env.NUSAGE_USAGE | from nuon); run {script_word}")
        }
    } else {
        if !std::io::stdin().is_terminal() {
            nu.arg("--stdin");
        }
        format!("let usage = ($env.NUSAGE_USAGE | from nuon); $in | run {script_word}")
    };
    let status = nu
        .args(["-c", &code])
        .env("NUSAGE_USAGE", nusage_nu::nuon(&record))
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()
        .map_err(|err| Diagnostic::new(script, format!("cannot run `nu`: {err}")))?;
    Ok(status.code().unwrap_or(1))
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

/// Where the script stands: the root of the tree it belongs to and its path in it, or the
/// script itself and the root path when no `mod.nu` lies beside it. The tree's root is the
/// outermost directory that has a `mod.nu` in each directory down to the script's.
fn place_in_tree(script: &Path) -> Result<(PathBuf, CommandPath), Diagnostic> {
    let script = std::path::absolute(script)
        .map_err(|err| Diagnostic::new(script, format!("cannot resolve: {err}")))?;
    let Some(mut dir) = script.parent().filter(|dir| dir.join("mod.nu").is_file()) else {
        return Ok((script, CommandPath::root()));
    };
    while let Some(parent) = dir
        .parent()
        .filter(|parent| parent.join("mod.nu").is_file())
    {
        dir = parent;
    }
    let mut words: Vec<String> = script
        .strip_prefix(dir)
        .map_err(|_| Diagnostic::new(&script, "not inside its tree"))?
        .components()
        .map(|component| component.as_os_str().to_string_lossy().into_owned())
        .collect();
    // `db/migrate.nu` is `db migrate`; `db/mod.nu` is `db`.
    if let Some(last) = words.pop()
        && last != "mod.nu"
    {
        words.push(last.trim_end_matches(".nu").to_string());
    }
    let path = words
        .iter()
        .fold(CommandPath::root(), |path, word| path.child(word));
    Ok((dir.to_path_buf(), path))
}

/// The `$usage` record: `{cmd, args, flags}`, as the shim builds it.
fn usage_record(command: &nusage_model::Command, parsed: &ParseOutput) -> Result<Value, String> {
    let span = Span::unknown();
    let mut args = Record::new();
    for param in &command.positionals {
        let found = parsed
            .args
            .iter()
            .find(|(arg, _)| arg.name == param.usage_name)
            .map(|(_, value)| value);
        args.push(param.var.clone(), positional_value(param, found)?);
    }
    let mut flags = Record::new();
    for param in &command.flags {
        let found = parsed
            .flags
            .iter()
            .find(|(flag, _)| flag.name == param.usage_name)
            .map(|(_, value)| value);
        flags.push(param.var.clone(), flag_value(param, found)?);
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
