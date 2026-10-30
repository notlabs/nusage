//! The commands, each by its node of the spec.

use nusage_plugin::nu_plugin::{EngineInterface, EvaluatedCall, PluginCommand};
use nusage_plugin::nu_protocol::{LabeledError, PipelineData, Signature, Type, Value};
use nusage_plugin::{CommandTree, Declared};

use crate::Plugin;

/// `NAME hello <who> [--shout]`.
pub struct Hello(Declared);

impl Hello {
    pub fn new(tree: &CommandTree) -> Result<Self, String> {
        Ok(Hello(Declared::new(
            tree,
            &["hello"],
            vec![(Type::Nothing, None)],
        )?))
    }
}

impl PluginCommand for Hello {
    type Plugin = Plugin;

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
        _plugin: &Plugin,
        _engine: &EngineInterface,
        call: &EvaluatedCall,
        _input: PipelineData,
    ) -> Result<PipelineData, LabeledError> {
        let who: String = call.req(0)?;
        let mut greeting = format!("hello {who}");
        if call.has_flag("shout")? {
            greeting = greeting.to_uppercase();
        }
        Ok(PipelineData::value(Value::string(greeting, call.head), None))
    }
}
