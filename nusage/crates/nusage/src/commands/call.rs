//! `nus call <script> <program> ...args`: a script run as a call of it, which the shadows of
//! called scripts make. The program is `nus`, and the script runs in the executor's engine,
//! inside this process; or `mise`, and mise runs the task in a process of its own, as the
//! Nushell helper of the same name runs every program, with the value coming back through
//! the file `NUS_OUTPUT_FILE` names. What the script prints passes through either way.

use std::sync::Arc;

use nusage_plugin::nu_protocol::{LabeledError, PipelineData, Type, Value};
use nusage_plugin::{Args, CommandTree, Context, Declared, Run};

use crate::executor::Executor;

#[derive(Clone)]
pub struct Call {
    declared: Declared,
    executor: Arc<Executor>,
}

impl Call {
    pub fn new(tree: &CommandTree, executor: Arc<Executor>) -> Result<Self, String> {
        Ok(Call {
            declared: Declared::new(tree, &["call"], vec![(Type::Any, Some(Type::Any))])?,
            executor,
        })
    }
}

/// Whether the program named is nus itself: `nus`, or a path to a binary of that name.
fn is_nus(program: &str) -> bool {
    std::path::Path::new(program)
        .file_stem()
        .is_some_and(|stem| stem == "nus")
}

impl Run for Call {
    fn declared(&self) -> &Declared {
        &self.declared
    }

    fn run(
        &self,
        cx: &dyn Context,
        args: &Args,
        input: PipelineData,
    ) -> Result<PipelineData, LabeledError> {
        let span = args.head;
        let script: String = args.req(0)?;
        let program: String = args.req(1)?;
        let rest: Vec<String> = args.rest(2)?;
        cx.keep_alive()?;
        if is_nus(&program) {
            // `nus <script> ...argv`: the script named again, then its arguments.
            let argv = match rest.first() {
                Some(first) if first == &script => &rest[1..],
                _ => &rest[..],
            };
            return self
                .executor
                .run(cx, std::path::Path::new(&script), argv, input, span)
                .map_err(LabeledError::from);
        }
        spawn(cx, &script, &program, &rest, input, span)
    }
}

/// The program run as the Nushell helper runs it: with the input on its standard input,
/// the value file named in its environment, and the value read back when it wrote one.
fn spawn(
    cx: &dyn Context,
    script: &str,
    program: &str,
    args: &[String],
    input: PipelineData,
    span: nusage_plugin::nu_protocol::Span,
) -> Result<PipelineData, LabeledError> {
    use std::io::Write;
    use std::process::{Command, Stdio};

    let at = |err: String| LabeledError::new(err).with_label("this call", span);
    let file = std::env::temp_dir().join(format!(
        "nusage-{}-{}.nuon",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or_default()
    ));
    let text = match input {
        PipelineData::Empty => None,
        PipelineData::Value(Value::Nothing { .. }, _) => None,
        other => Some(
            other
                .into_value(span)?
                .to_expanded_string("\n", &nusage_plugin::nu_protocol::Config::default()),
        ),
    };
    let mut command = Command::new(program);
    command
        .args(args)
        .current_dir(cx.cwd()?)
        .env("NUS_OUTPUT_FILE", &file)
        .env("NUS_OUTPUT_SCRIPT", script)
        .stdin(if text.is_some() {
            Stdio::piped()
        } else {
            Stdio::null()
        });
    for (name, value) in cx.environment()? {
        if let Ok(value) = value.coerce_string() {
            command.env(name, value);
        }
    }
    let mut child = command
        .spawn()
        .map_err(|err| at(format!("cannot run `{program}`: {err}")))?;
    if let (Some(text), Some(mut stdin)) = (text, child.stdin.take()) {
        let _ = stdin.write_all(text.as_bytes());
    }
    let status = child
        .wait()
        .map_err(|err| at(format!("`{program}`: {err}")))?;
    if !status.success() {
        let _ = std::fs::remove_file(&file);
        return Err(at(format!(
            "`{program}` exited with {}",
            status
                .code()
                .map_or("a signal".to_string(), |c| c.to_string())
        )));
    }
    let Ok(written) = std::fs::read_to_string(&file) else {
        return Ok(PipelineData::empty());
    };
    let _ = std::fs::remove_file(&file);
    let value = nuon::from_nuon(&written, Some(span))
        .map_err(|err| at(format!("the value `{program}` wrote is not NUON: {err}")))?;
    Ok(PipelineData::value(value, None))
}
