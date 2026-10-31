//! One implementation, two registrations. A command's logic runs on its evaluated arguments,
//! a context that answers for the caller's environment, and the input, and knows nothing of
//! where it was called from. [`Native`] registers it in an engine as a command of that
//! engine's own, and [`Adapter`] registers it in a plugin as a plugin command; both hand it
//! the same [`Args`] and a [`Context`]. So a command the plugin serves to the caller's shell
//! is the same code a script running inside the plugin's own engine calls, with no plugin
//! between them, which is what lets the plugin stand in for itself at every level.

// `ShellError` is Nushell's size, as every engine command's `Result` of it is.
#![allow(clippy::result_large_err)]

use std::collections::HashMap;
use std::marker::PhantomData;

use nu_engine::CallExt;
use nu_plugin::{EngineInterface, EvaluatedCall, Plugin, PluginCommand};
use nu_protocol::engine::{Call, Command, EngineState, Stack, StateWorkingSet};
use nu_protocol::{FromValue, LabeledError, PipelineData, ShellError, Signature, Span, Value};

use crate::Declared;

/// A command's arguments, evaluated: what the plugin protocol hands a plugin, and what an
/// engine's call evaluates to before the command runs.
#[derive(Debug, Clone)]
pub struct Args {
    pub head: Span,
    positional: Vec<Value>,
    named: Vec<(String, Option<Value>)>,
}

impl Args {
    /// Arguments given directly, as a process's command line is.
    pub fn new(head: Span, positional: Vec<Value>, named: Vec<(String, Option<Value>)>) -> Self {
        Args {
            head,
            positional,
            named,
        }
    }

    /// The arguments as the plugin protocol delivered them.
    pub fn from_plugin(call: &EvaluatedCall) -> Self {
        Args {
            head: call.head,
            positional: call.positional.clone(),
            named: call
                .named
                .iter()
                .map(|(name, value)| (name.item.clone(), value.clone()))
                .collect(),
        }
    }

    /// The arguments of an engine's call, evaluated against `signature`: every positional,
    /// and each flag the signature declares that the call gives.
    pub fn from_engine(
        signature: &Signature,
        engine_state: &EngineState,
        stack: &mut Stack,
        call: &Call,
    ) -> Result<Self, ShellError> {
        let positional: Vec<Value> = call.rest(engine_state, stack, 0)?;
        let mut named = Vec::new();
        for flag in &signature.named {
            if flag.arg.is_none() {
                if call.has_flag(engine_state, stack, &flag.long)? {
                    named.push((flag.long.clone(), Some(Value::bool(true, call.head))));
                }
            } else if let Some(value) = call.get_flag::<Value>(engine_state, stack, &flag.long)? {
                named.push((flag.long.clone(), Some(value)));
            }
        }
        Ok(Args {
            head: call.head,
            positional,
            named,
        })
    }

    pub fn req<T: FromValue>(&self, position: usize) -> Result<T, LabeledError> {
        match self.positional.get(position) {
            Some(value) => Ok(T::from_value(value.clone())?),
            None => Err(LabeledError::new(format!(
                "missing required positional argument {position}"
            ))
            .with_label("this call", self.head)),
        }
    }

    pub fn opt<T: FromValue>(&self, position: usize) -> Result<Option<T>, LabeledError> {
        self.positional
            .get(position)
            .map(|value| T::from_value(value.clone()).map_err(LabeledError::from))
            .transpose()
    }

    pub fn rest<T: FromValue>(&self, start: usize) -> Result<Vec<T>, LabeledError> {
        self.positional
            .iter()
            .skip(start)
            .map(|value| T::from_value(value.clone()).map_err(LabeledError::from))
            .collect()
    }

    /// Whether the switch is given; a switch given as `--flag=false` is not.
    pub fn has_flag(&self, name: &str) -> bool {
        self.named.iter().any(|(flag, value)| {
            flag == name && !matches!(value, Some(Value::Bool { val: false, .. }))
        })
    }

    pub fn get_flag<T: FromValue>(&self, name: &str) -> Result<Option<T>, LabeledError> {
        self.named
            .iter()
            .find(|(flag, value)| flag == name && value.is_some())
            .and_then(|(_, value)| value.clone())
            .map(|value| T::from_value(value).map_err(LabeledError::from))
            .transpose()
    }
}

/// What a command asks of where it was called from: the caller's environment and working
/// directory, which a plugin reads over the protocol and an engine's command reads from the
/// stack, and two things about the process it runs in.
pub trait Context {
    /// The environment variable, as text, when set.
    fn env(&self, name: &str) -> Result<Option<String>, LabeledError>;
    /// The whole environment, as the caller's shell has it.
    fn environment(&self) -> Result<HashMap<String, Value>, LabeledError>;
    /// The caller's working directory, absolute.
    fn cwd(&self) -> Result<String, LabeledError>;
    /// Whether what runs here may write to standard output and reach the terminal: not in
    /// a plugin that talks to its engine over standard output.
    fn stdout_is_free(&self) -> bool;
    /// Keep the process running between calls, for the state it now holds; nothing where
    /// the process is the caller's own.
    fn keep_alive(&self) -> Result<(), LabeledError>;
}

impl Context for EngineInterface {
    fn env(&self, name: &str) -> Result<Option<String>, LabeledError> {
        Ok(match self.get_env_var(name)? {
            Some(value) => Some(value.coerce_into_string()?),
            None => None,
        })
    }

    fn environment(&self) -> Result<HashMap<String, Value>, LabeledError> {
        Ok(self.get_env_vars()?)
    }

    fn cwd(&self) -> Result<String, LabeledError> {
        Ok(self.get_current_dir()?)
    }

    fn stdout_is_free(&self) -> bool {
        !self.is_using_stdio()
    }

    fn keep_alive(&self) -> Result<(), LabeledError> {
        Ok(self.set_gc_disabled(true)?)
    }
}

/// An engine's state and stack as a command's context.
pub struct EngineContext<'a> {
    pub engine_state: &'a EngineState,
    pub stack: &'a Stack,
}

impl Context for EngineContext<'_> {
    fn env(&self, name: &str) -> Result<Option<String>, LabeledError> {
        self.stack
            .get_env_var(self.engine_state, name)
            .map(|value| {
                value
                    .clone()
                    .coerce_into_string()
                    .map_err(LabeledError::from)
            })
            .transpose()
    }

    fn environment(&self) -> Result<HashMap<String, Value>, LabeledError> {
        Ok(self.stack.get_env_vars(self.engine_state))
    }

    fn cwd(&self) -> Result<String, LabeledError> {
        Ok(self
            .engine_state
            .cwd(Some(self.stack))?
            .to_string_lossy()
            .into_owned())
    }

    fn stdout_is_free(&self) -> bool {
        true
    }

    fn keep_alive(&self) -> Result<(), LabeledError> {
        Ok(())
    }
}

/// A command's logic, with what the spec declares of it. One implementation serves both
/// registrations, so it is cloned into each and shared between calls.
pub trait Run: Clone + Send + Sync + 'static {
    fn declared(&self) -> &Declared;
    fn run(
        &self,
        cx: &dyn Context,
        args: &Args,
        input: PipelineData,
    ) -> Result<PipelineData, LabeledError>;
}

/// The command as an engine's own: registered in a [`StateWorkingSet`], it is called like
/// any other, with no plugin between.
#[derive(Clone)]
pub struct Native<R: Run>(pub R);

impl<R: Run> Command for Native<R> {
    fn name(&self) -> &str {
        &self.0.declared().name
    }

    fn signature(&self) -> Signature {
        self.0.declared().signature.clone()
    }

    fn description(&self) -> &str {
        &self.0.declared().description
    }

    fn extra_description(&self) -> &str {
        &self.0.declared().extra_description
    }

    fn run(
        &self,
        engine_state: &EngineState,
        stack: &mut Stack,
        call: &Call,
        input: PipelineData,
    ) -> Result<PipelineData, ShellError> {
        let args = Args::from_engine(&self.0.declared().signature, engine_state, stack, call)?;
        let cx = EngineContext {
            engine_state,
            stack,
        };
        self.0.run(&cx, &args, input).map_err(ShellError::from)
    }
}

/// The command as a plugin's: the plugin protocol delivers the arguments evaluated, and the
/// engine interface is the context.
pub struct Adapter<P, R> {
    run: R,
    plugin: PhantomData<fn() -> P>,
}

impl<P, R> Adapter<P, R> {
    pub fn new(run: R) -> Self {
        Adapter {
            run,
            plugin: PhantomData,
        }
    }
}

impl<P: Plugin, R: Run> PluginCommand for Adapter<P, R> {
    type Plugin = P;

    fn name(&self) -> &str {
        &self.run.declared().name
    }

    fn signature(&self) -> Signature {
        self.run.declared().signature.clone()
    }

    fn description(&self) -> &str {
        &self.run.declared().description
    }

    fn extra_description(&self) -> &str {
        &self.run.declared().extra_description
    }

    fn run(
        &self,
        _plugin: &P,
        engine: &EngineInterface,
        call: &EvaluatedCall,
        input: PipelineData,
    ) -> Result<PipelineData, LabeledError> {
        self.run.run(engine, &Args::from_plugin(call), input)
    }
}

/// An engine with Nushell's commands and `natives` as its own: what a script runs in inside
/// the plugin, where a call of a command the plugin serves reaches the same code directly.
/// `print` is Nushell's shell's, not its command set's, so the engine carries one of its
/// own, which writes to the process's standard output and error as the shell's does.
pub fn engine(natives: Vec<Box<dyn Command>>) -> Result<EngineState, ShellError> {
    let mut state = nu_command::add_shell_command_context(nu_cmd_lang::create_default_context());
    let delta = {
        let mut working_set = StateWorkingSet::new(&state);
        working_set.add_decl(Box::new(Print));
        for native in natives {
            working_set.add_decl(native);
        }
        working_set.render()
    };
    state.merge_delta(delta)?;
    Ok(state)
}

/// `print`, as the shell has it: each value given, or the input, written to standard
/// output, or to standard error with `--stderr`, a newline after each unless
/// `--no-newline`; `--raw` writes a string or binary as it is.
#[derive(Clone)]
struct Print;

impl Command for Print {
    fn name(&self) -> &str {
        "print"
    }

    fn signature(&self) -> Signature {
        Signature::build("print")
            .input_output_types(vec![
                (nu_protocol::Type::Nothing, nu_protocol::Type::Nothing),
                (nu_protocol::Type::Any, nu_protocol::Type::Nothing),
            ])
            .rest("rest", nu_protocol::SyntaxShape::Any, "The values to print")
            .switch(
                "no-newline",
                "Print without a newline after each value",
                Some('n'),
            )
            .switch("stderr", "Print to standard error instead", Some('e'))
            .switch("raw", "Print a string or binary as it is", Some('r'))
            .category(nu_protocol::Category::Strings)
    }

    fn description(&self) -> &str {
        "Print the given values to stdout."
    }

    fn run(
        &self,
        engine_state: &EngineState,
        stack: &mut Stack,
        call: &Call,
        input: PipelineData,
    ) -> Result<PipelineData, ShellError> {
        use std::io::Write;
        let values: Vec<Value> = call.rest(engine_state, stack, 0)?;
        let no_newline = call.has_flag(engine_state, stack, "no-newline")?;
        let to_stderr = call.has_flag(engine_state, stack, "stderr")?;
        let raw = call.has_flag(engine_state, stack, "raw")?;
        let config = stack.get_config(engine_state);
        let values = if values.is_empty() {
            match input {
                PipelineData::Empty => Vec::new(),
                other => vec![other.into_value(call.head)?],
            }
        } else {
            values
        };
        let mut text = Vec::new();
        for value in values {
            match value {
                Value::String { val, .. } if raw => text.extend_from_slice(val.as_bytes()),
                Value::Binary { val, .. } if raw => text.extend_from_slice(&val),
                other => text.extend_from_slice(other.to_expanded_string("\n", &config).as_bytes()),
            }
            if !no_newline {
                text.push(b'\n');
            }
        }
        let written = if to_stderr {
            std::io::stderr().write_all(&text)
        } else {
            std::io::stdout()
                .write_all(&text)
                .and_then(|()| std::io::stdout().flush())
        };
        written.map_err(|err| ShellError::from(LabeledError::new(format!("print: {err}"))))?;
        Ok(PipelineData::empty())
    }
}

/// `source` parsed into `engine_state` and run in `cwd` with `input`: the shape of a call
/// of the executor, here for what the executor does not yet do.
pub fn eval(
    engine_state: &mut EngineState,
    cwd: &str,
    source: &str,
    input: PipelineData,
) -> Result<PipelineData, ShellError> {
    let block = {
        let mut working_set = StateWorkingSet::new(engine_state);
        let block = nu_parser::parse(&mut working_set, Some("source"), source.as_bytes(), false);
        if let Some(err) = working_set.parse_errors.first() {
            return Err(ShellError::from(LabeledError::new(format!(
                "the source does not parse: {err}"
            ))));
        }
        if let Some(err) = working_set.compile_errors.first() {
            return Err(ShellError::from(LabeledError::new(format!(
                "the source does not compile: {err}"
            ))));
        }
        let delta = working_set.render();
        engine_state.merge_delta(delta)?;
        block
    };
    let mut stack = Stack::new().collect_value();
    stack.add_env_var("PWD".into(), Value::string(cwd, Span::unknown()));
    let data = nu_engine::eval_block::<nu_protocol::debugger::WithoutDebug>(
        engine_state,
        &mut stack,
        &block,
        input,
    )?;
    Ok(data.body)
}
