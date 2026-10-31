//! `nus call <script> <program> ...args`: a script run as a call of it, which the shadows of
//! called scripts make. The program is `nus`, and the script runs in the executor's engine,
//! inside this process. Or it is `mise`, with a task as the shadow names one, `-C <dir> run
//! <task> ...args`: the task's file runs in the engine too, as mise would run it, in the
//! task's directory with mise's environment over the caller's, after the tasks it depends on
//! and before the ones that follow it, each run the same way when its run is a file nusage
//! runs and by mise when not. Any other program runs in a process of its own, as the Nushell
//! helper of the same name runs every program, with the value coming back through the file
//! `NUS_OUTPUT_FILE` names. What the script prints passes through either way.

use std::collections::{HashMap, HashSet};
use std::path::Path;
use std::sync::Arc;

use nusage_plugin::nu_protocol::{LabeledError, PipelineData, Type, Value};
use nusage_plugin::{Args, CommandTree, Context, Declared, Run};

use crate::executor::{Executor, Within};
use crate::tasks::{self, Dep, Task};

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
        if let Some((dir, task, argv)) = named_task(&program, &rest) {
            return self.task(cx, dir, task, argv, input, span);
        }
        spawn(cx, &script, &program, &rest, input, span)
    }
}

/// The task a shadow's call names, `mise -C <dir> run <task> ...argv`, and its arguments.
fn named_task<'a>(program: &str, args: &'a [String]) -> Option<(&'a Path, &'a str, &'a [String])> {
    let is_mise = Path::new(program)
        .file_stem()
        .is_some_and(|stem| stem == "mise");
    match args {
        [flag, dir, run, task, argv @ ..] if is_mise && flag == "-C" && run == "run" => {
            Some((Path::new(dir), task, argv))
        }
        _ => None,
    }
}

impl Call {
    /// `mise run <task> ...argv` from `dir`, run here: the task's file in the engine, in
    /// mise's environment for `dir`, with the tasks around it before and after.
    fn task(
        &self,
        cx: &dyn Context,
        dir: &Path,
        task: &str,
        argv: &[String],
        input: PipelineData,
        span: nusage_plugin::nu_protocol::Span,
    ) -> Result<PipelineData, LabeledError> {
        let at = |err: String| LabeledError::new(err).with_label("this call", span);
        let caller: HashMap<String, String> = cx
            .environment()?
            .into_iter()
            .filter_map(|(name, value)| value.coerce_string().ok().map(|value| (name, value)))
            .collect();
        let dir = if dir.is_absolute() {
            dir.to_path_buf()
        } else {
            Path::new(&cx.cwd()?).join(dir)
        };
        let Some(task) = tasks::task_in(&dir, task, Some(&caller)).map_err(at)? else {
            // A task whose run is not a file is mise's to run, as it was.
            tasks::run(&dir, task, argv, Some(&caller)).map_err(at)?;
            return Ok(PipelineData::empty());
        };
        let mut env = tasks::environment(&dir, Some(&caller)).map_err(at)?;
        env.insert("MISE_ORIGINAL_CWD".into(), cx.cwd()?);
        let mut run = TaskRun {
            call: self,
            cx,
            dir: &dir,
            caller: &caller,
            env,
            done: HashSet::new(),
            span,
        };
        run.task(&task, argv, input)
    }
}

/// One `mise run`, as it runs here: each task once, however many depend on it.
struct TaskRun<'a> {
    call: &'a Call,
    cx: &'a dyn Context,
    dir: &'a Path,
    caller: &'a HashMap<String, String>,
    env: HashMap<String, String>,
    done: HashSet<String>,
    span: nusage_plugin::nu_protocol::Span,
}

impl TaskRun<'_> {
    /// The task, after what it depends on and before what follows it; its value.
    fn task(
        &mut self,
        task: &Task,
        argv: &[String],
        input: PipelineData,
    ) -> Result<PipelineData, LabeledError> {
        self.done.insert(task.name.clone());
        for dep in &task.depends {
            self.dep(dep)?;
        }
        let value = self.file(task, argv, input)?;
        for dep in &task.depends_post {
            self.dep(dep)?;
        }
        Ok(value)
    }

    /// A task another depends on: run as the task is when its run is a file nusage runs,
    /// by mise when not, or when mise names it but does not describe it, as a pattern
    /// for several; and not again when it ran already.
    fn dep(&mut self, dep: &Dep) -> Result<(), LabeledError> {
        let at = |err: String| LabeledError::new(err).with_label("this call", self.span);
        if self.done.contains(&dep.task) {
            return Ok(());
        }
        self.done.insert(dep.task.clone());
        match tasks::task_in(self.dir, &dep.task, Some(self.caller)) {
            Ok(Some(task)) if self.done.contains(&task.name) => Ok(()),
            Ok(Some(task)) if crate::calls::is_nusage_script(&task.file) => {
                self.task(&task, &dep.args, PipelineData::empty())?;
                Ok(())
            }
            _ => tasks::run(self.dir, &dep.task, &dep.args, Some(self.caller)).map_err(at),
        }
    }

    /// The task's file in the engine, in its directory, with what mise tells a task.
    fn file(
        &self,
        task: &Task,
        argv: &[String],
        input: PipelineData,
    ) -> Result<PipelineData, LabeledError> {
        let mut env = self.env.clone();
        let text = |path: &Path| path.to_string_lossy().into_owned();
        env.insert("MISE_TASK_NAME".into(), task.name.clone());
        env.insert("MISE_TASK_FILE".into(), text(&task.file));
        if let Some(parent) = task.file.parent() {
            env.insert("MISE_TASK_DIR".into(), text(parent));
        }
        env.insert("MISE_CONFIG_ROOT".into(), text(&task.root));
        env.insert("MISE_PROJECT_ROOT".into(), text(&task.root));
        let within = Within {
            inner: self.cx,
            cwd: text(&task.dir),
            env,
        };
        self.call
            .executor
            .run(&within, &task.file, argv, input, self.span)
            .map_err(LabeledError::from)
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
