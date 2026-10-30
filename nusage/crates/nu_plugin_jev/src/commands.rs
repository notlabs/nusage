//! The commands, each by its node of the spec: `jev`, which is the help, `jev ask` and `jev
//! noul`. A command's signature is the spec's; its input is the content judged, any value,
//! and its output the type the spec's `output` declares.

use nusage_plugin::nu_plugin::{EngineInterface, EvaluatedCall, PluginCommand};
use nusage_plugin::nu_protocol::{LabeledError, PipelineData, Signature, Span, Type, Value};
use nusage_plugin::{CommandTree, Declared, value};

use crate::{JevPlugin, MODEL};

/// `jev`: the help, as the root of a plugin's commands conventionally is.
pub struct Jev(Declared);

impl Jev {
    pub fn new(tree: &CommandTree) -> Result<Self, String> {
        Ok(Jev(Declared::new(
            tree,
            &[],
            vec![(Type::Nothing, Some(Type::String))],
        )?))
    }
}

impl PluginCommand for Jev {
    type Plugin = JevPlugin;

    fn name(&self) -> &str {
        &self.0.name
    }

    fn signature(&self) -> Signature {
        self.0.signature.clone()
    }

    fn description(&self) -> &str {
        &self.0.description
    }

    fn extra_description(&self) -> &str {
        &self.0.extra_description
    }

    fn run(
        &self,
        _plugin: &JevPlugin,
        engine: &EngineInterface,
        call: &EvaluatedCall,
        _input: PipelineData,
    ) -> Result<PipelineData, LabeledError> {
        Ok(PipelineData::value(
            Value::string(engine.get_help()?, call.head),
            None,
        ))
    }
}

/// The input as the content judged: a string as text, anything else as the JSON it is.
fn state(input: PipelineData, span: Span) -> Result<serde_json::Value, LabeledError> {
    let value = input.into_value(span)?;
    if matches!(value, Value::Nothing { .. }) {
        return Err(
            LabeledError::new("nothing to judge: the input is the content")
                .with_label("this call", span),
        );
    }
    value::to_json(&value)
}

/// `jev ask <questions> [--model]`.
pub struct Ask(Declared);

impl Ask {
    pub fn new(tree: &CommandTree) -> Result<Self, String> {
        Ok(Ask(Declared::new(tree, &["ask"], vec![(Type::Any, None)])?))
    }
}

impl PluginCommand for Ask {
    type Plugin = JevPlugin;

    fn name(&self) -> &str {
        &self.0.name
    }

    fn signature(&self) -> Signature {
        self.0.signature.clone()
    }

    fn description(&self) -> &str {
        &self.0.description
    }

    fn extra_description(&self) -> &str {
        &self.0.extra_description
    }

    fn run(
        &self,
        plugin: &JevPlugin,
        engine: &EngineInterface,
        call: &EvaluatedCall,
        input: PipelineData,
    ) -> Result<PipelineData, LabeledError> {
        let span = call.head;
        let questions: Value = call.req(0)?;
        let model: Option<String> = call.get_flag("model")?;
        let answer = plugin.judge(
            engine,
            model.as_deref().unwrap_or(MODEL),
            state(input, span)?,
            value::to_json(&questions)?,
            span,
        )?;
        Ok(PipelineData::value(value::from_json(answer, span), None))
    }
}

/// `jev noul <statement> [--model]`.
pub struct Noul(Declared);

impl Noul {
    pub fn new(tree: &CommandTree) -> Result<Self, String> {
        Ok(Noul(Declared::new(
            tree,
            &["noul"],
            vec![(Type::Any, None)],
        )?))
    }
}

impl PluginCommand for Noul {
    type Plugin = JevPlugin;

    fn name(&self) -> &str {
        &self.0.name
    }

    fn signature(&self) -> Signature {
        self.0.signature.clone()
    }

    fn description(&self) -> &str {
        &self.0.description
    }

    fn extra_description(&self) -> &str {
        &self.0.extra_description
    }

    fn run(
        &self,
        plugin: &JevPlugin,
        engine: &EngineInterface,
        call: &EvaluatedCall,
        input: PipelineData,
    ) -> Result<PipelineData, LabeledError> {
        let span = call.head;
        let statement: String = call.req(0)?;
        let model: Option<String> = call.get_flag("model")?;
        let questions = serde_json::json!({"answer": {"type": "noul", "instructions": statement}});
        let answer = plugin.judge(
            engine,
            model.as_deref().unwrap_or(MODEL),
            state(input, span)?,
            questions,
            span,
        )?;
        let probability = answer
            .pointer("/answers/answer/noul")
            .and_then(serde_json::Value::as_f64)
            .ok_or_else(|| {
                LabeledError::new(format!(
                    "the service answered without `answers.answer.noul`: {answer}"
                ))
                .with_label("this call", span)
            })?;
        Ok(PipelineData::value(Value::float(probability, span), None))
    }
}
