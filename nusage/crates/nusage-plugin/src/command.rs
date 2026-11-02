//! A command's logic, apart from how the plugin receives it. The logic runs on its
//! evaluated arguments, a context that answers for the caller's environment, and the input,
//! and knows nothing of where it was called from; [`Adapter`] registers it in a plugin as a
//! plugin command, handing it the protocol's [`Args`] and the engine interface as its
//! [`Context`].

use std::collections::HashMap;
use std::marker::PhantomData;

use nu_plugin::{EngineInterface, EvaluatedCall, Plugin, PluginCommand};
use nu_protocol::{FromValue, LabeledError, PipelineData, Signature, Span, Value};

use crate::Declared;

/// A command's arguments, evaluated, as the plugin protocol hands a plugin.
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
/// directory, which a plugin reads over the protocol.
pub trait Context {
    /// The environment variable, as text, when set.
    fn env(&self, name: &str) -> Result<Option<String>, LabeledError>;
    /// The whole environment, as the caller's shell has it.
    fn environment(&self) -> Result<HashMap<String, Value>, LabeledError>;
    /// The caller's working directory, absolute.
    fn cwd(&self) -> Result<String, LabeledError>;
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
}

/// A command's logic, with what the spec declares of it, cloned into its registration and
/// shared between calls.
pub trait Run: Clone + Send + Sync + 'static {
    fn declared(&self) -> &Declared;
    fn run(
        &self,
        cx: &dyn Context,
        args: &Args,
        input: PipelineData,
    ) -> Result<PipelineData, LabeledError>;
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
