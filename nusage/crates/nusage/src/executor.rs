//! Scripts run inside a process that lives across calls, in an engine of its own, rather
//! than in a `nu` started for each: what the interpreter does, done without the process.
//! A call is the interpreter's own code, the shadows of the scripts the script calls and
//! then `let usage = ...; $in | run <script>`, parsed once per content and kept, then run on
//! a fresh stack with the caller's environment, its working directory and `$usage`. The
//! shadows call `nus call`, which in this engine is a command of the engine's own, so a
//! script calling a script stays inside the process. What the script prints goes to the
//! process's standard output, as the interpreter's does; a plugin that talks to its engine
//! over that output cannot run a script, and says so.

// `ShellError` is Nushell's size, as every engine call's `Result` of it is.
#![allow(clippy::result_large_err)]

use std::collections::HashMap;
use std::hash::{DefaultHasher, Hash, Hasher};
use std::path::Path;
use std::sync::{Arc, Mutex, OnceLock};

use nusage_plugin::Context;
use nusage_plugin::nu_protocol::ast::Block;
use nusage_plugin::nu_protocol::engine::{Command, EngineState, Stack, StateWorkingSet};
use nusage_plugin::nu_protocol::{LabeledError, PipelineData, ShellError, Span, Value};

use crate::Parsed;

/// The engine scripts run in, and the scripts parsed into it so far.
pub struct Executor {
    natives: Mutex<Vec<Box<dyn Command>>>,
    engine: OnceLock<Mutex<EngineState>>,
    blocks: Mutex<HashMap<u64, Arc<Block>>>,
}

impl Default for Executor {
    fn default() -> Self {
        Self::new()
    }
}

impl Executor {
    pub fn new() -> Self {
        Executor {
            natives: Mutex::new(Vec::new()),
            engine: OnceLock::new(),
            blocks: Mutex::new(HashMap::new()),
        }
    }

    /// The commands the engine has as its own, beside Nushell's: given before the first
    /// call, since the engine is built on it.
    pub fn register(&self, natives: Vec<Box<dyn Command>>) {
        self.natives
            .lock()
            .expect("no panic holds the natives")
            .extend(natives);
    }

    fn engine(&self) -> Result<&Mutex<EngineState>, LabeledError> {
        if let Some(engine) = self.engine.get() {
            return Ok(engine);
        }
        let natives = self
            .natives
            .lock()
            .expect("no panic holds the natives")
            .clone();
        let state = nusage_plugin::command::engine(natives)?;
        Ok(self.engine.get_or_init(|| Mutex::new(state)))
    }

    /// Run `script` with `args` as the interpreter would, with `input` as its `$in`, in the
    /// caller's environment and working directory, and return its value. `--help` returns
    /// the help page as text; arguments usage rejects are an error saying why. An error is
    /// the engine's own, with its spans in the script, and an `exit` in the script is
    /// [`ShellError::Exit`].
    pub fn run(
        &self,
        cx: &dyn Context,
        script: &Path,
        args: &[String],
        input: PipelineData,
        span: Span,
    ) -> Result<PipelineData, ShellError> {
        if !cx.stdout_is_free() {
            return Err(LabeledError::new(
                "a script runs only where what it prints reaches the terminal: the plugin is \
                 talking to Nushell over its standard output",
            )
            .with_help("Nushell runs a plugin over a local socket by default; this one is not")
            .with_label("this call", span)
            .into());
        }
        let at = |err: String| LabeledError::new(err).with_label("this call", span);
        let cwd = cx.cwd()?;
        let script = if script.is_absolute() {
            script.to_path_buf()
        } else {
            Path::new(&cwd).join(script)
        };
        let (parsed, routed) = crate::route(&script, args).map_err(|err| at(err.to_string()))?;
        let record = match parsed {
            Parsed::Record(record) => record,
            Parsed::Help(page) => return Ok(PipelineData::value(Value::string(page, span), None)),
            Parsed::Rejected(why) => return Err(at(why).into()),
        };
        let path =
            std::path::absolute(&routed).map_err(|err| at(format!("cannot resolve: {err}")))?;
        let prelude =
            crate::prelude::runtime_in_engine(&path).map_err(|err| at(err.to_string()))?;
        let code = format!(
            "{prelude}let usage = ($env.NUS_USAGE | from nuon); $in | run {}",
            nusage_nu::word(&path.to_string_lossy())
        );
        let text = std::fs::read(&path).map_err(|err| at(format!("{}: {err}", path.display())))?;
        let block = self
            .block(&code, &text, &path, &cwd)
            .map_err(|err| at(err.to_string()))?;
        let engine = self
            .engine()?
            .lock()
            .expect("no panic holds the engine")
            .clone();
        let mut stack = Stack::new().collect_value();
        for (name, value) in cx.environment()? {
            stack.add_env_var(name, value);
        }
        stack.add_env_var("PWD".into(), Value::string(cwd, span));
        stack.add_env_var(
            "NUS_USAGE".into(),
            Value::string(nusage_nu::nuon(&record), span),
        );
        let data = nusage_plugin::nu_engine::eval_block::<
            nusage_plugin::nu_protocol::debugger::WithoutDebug,
        >(&engine, &mut stack, &block, input)?;
        Ok(data.body)
    }

    /// `data` written to standard output as Nushell shows a value, a table where the value
    /// is one, with the engine's own `table`.
    pub fn print(&self, data: PipelineData) -> Result<(), ShellError> {
        let engine = self
            .engine()?
            .lock()
            .expect("no panic holds the engine")
            .clone();
        let mut stack = Stack::new().collect_value();
        let cwd = std::env::current_dir().unwrap_or_default();
        stack.add_env_var(
            "PWD".into(),
            Value::string(cwd.to_string_lossy(), Span::unknown()),
        );
        data.print_table(&engine, &mut stack, false, false)
    }

    /// `err` reported on standard error as Nushell reports it, with its spans in the source
    /// the engine holds.
    pub fn report(&self, err: &ShellError) {
        match self.engine() {
            Ok(engine) => {
                let engine = engine.lock().expect("no panic holds the engine");
                nusage_plugin::nu_protocol::report_shell_error(None, &engine, err);
            }
            Err(_) => eprintln!("Error: {err}"),
        }
    }

    /// The code parsed into the engine, kept by the content of the code and of the script
    /// it runs, which `run` reads at parse time.
    fn block(
        &self,
        code: &str,
        script_text: &[u8],
        path: &Path,
        cwd: &str,
    ) -> Result<Arc<Block>, ShellError> {
        let mut hasher = DefaultHasher::new();
        code.hash(&mut hasher);
        script_text.hash(&mut hasher);
        let key = hasher.finish();
        if let Some(block) = self
            .blocks
            .lock()
            .expect("no panic holds the blocks")
            .get(&key)
        {
            return Ok(block.clone());
        }
        let engine = self.engine().map_err(ShellError::from)?;
        let mut state = engine.lock().expect("no panic holds the engine");
        // The caller's working directory, for what a `const` works out at parse time.
        state.add_env_var("PWD".into(), Value::string(cwd, Span::unknown()));
        let block = {
            let mut working_set = StateWorkingSet::new(&state);
            let name = path.to_string_lossy();
            let block = nusage_plugin::nu_parser::parse(
                &mut working_set,
                Some(&name),
                code.as_bytes(),
                false,
            );
            if let Some(err) = working_set.parse_errors.first() {
                return Err(ShellError::from(LabeledError::new(format!(
                    "{}: does not parse as nus runs it: {err}",
                    path.display()
                ))));
            }
            if let Some(err) = working_set.compile_errors.first() {
                return Err(ShellError::from(LabeledError::new(format!(
                    "{}: does not compile as nus runs it: {err}",
                    path.display()
                ))));
            }
            let delta = working_set.render();
            state.merge_delta(delta)?;
            block
        };
        self.blocks
            .lock()
            .expect("no panic holds the blocks")
            .insert(key, block.clone());
        Ok(block)
    }
}

/// The error as text, with what its labels and the errors inside it say, for a command
/// line that has no span to point at.
pub fn describe(err: &LabeledError) -> String {
    let mut text = err.msg.clone();
    for label in err.labels.iter() {
        if !label.text.is_empty() {
            text.push_str(&format!(" ({})", label.text));
        }
    }
    for inner in err.inner.iter() {
        text.push_str(&format!("\n  {inner:?}"));
    }
    text
}

/// The process itself as a context: the CLI's, whose environment and directory are its own
/// and whose standard output is the terminal. Variables named in `without` are kept from
/// what runs: the ones that address this process, which a script's own calls must not see.
#[derive(Default)]
pub struct ProcessContext {
    pub without: Vec<String>,
}

impl ProcessContext {
    /// The process's environment less `names`.
    pub fn without(names: &[&str]) -> Self {
        ProcessContext {
            without: names.iter().map(|name| name.to_string()).collect(),
        }
    }
}

impl Context for ProcessContext {
    fn env(&self, name: &str) -> Result<Option<String>, LabeledError> {
        if self.without.iter().any(|kept| kept == name) {
            return Ok(None);
        }
        Ok(std::env::var(name).ok())
    }

    fn environment(&self) -> Result<HashMap<String, Value>, LabeledError> {
        Ok(std::env::vars()
            .filter(|(name, _)| !self.without.iter().any(|kept| kept == name))
            .map(|(name, value)| (name, Value::string(value, Span::unknown())))
            .collect())
    }

    fn cwd(&self) -> Result<String, LabeledError> {
        std::env::current_dir()
            .map(|dir| dir.to_string_lossy().into_owned())
            .map_err(|err| LabeledError::new(format!("no working directory: {err}")))
    }

    fn stdout_is_free(&self) -> bool {
        true
    }

    fn keep_alive(&self) -> Result<(), LabeledError> {
        Ok(())
    }
}
