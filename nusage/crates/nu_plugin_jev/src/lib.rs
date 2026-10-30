//! Jev, TypeSafe AI's System One model, as a Nushell plugin: a judgment about the input as a
//! typed value, so a judgment stands in a pipeline as any other step does and a gate is a
//! step whose answer decides what follows. The commands are declared by the usage spec
//! beside this file, `jev.usage.kdl`, as every command of nusage's is, and the plugin takes
//! its signatures from it.
//!
//! The plugin is the hot path the `typesafe` module of the catalog would otherwise be: one
//! process across calls, holding the connection and the answers given so far, keyed by the
//! request that got them, so the same question of the same content is answered once. That
//! is the first form of the record a judgment leaves; where it rests across processes is the
//! store's question, not this plugin's.

use std::collections::HashMap;
use std::sync::Mutex;

use nusage_plugin::nu_plugin::{EngineInterface, Plugin, PluginCommand};
use nusage_plugin::nu_protocol::{LabeledError, Span};
use nusage_plugin::{CommandTree, Diagnostic, value};

mod commands;

pub use commands::{Ask, Jev, Noul};

/// The spec the commands are declared by.
pub const SPEC: &str = include_str!("../jev.usage.kdl");

/// Where the service is unless `$env.TYPESAFE_URL` says otherwise.
pub const BASE: &str = "https://api.typesafe.ai";

/// The model unless `--model` says otherwise.
pub const MODEL: &str = "jev-latest";

pub struct JevPlugin {
    tree: CommandTree,
    agent: ureq::Agent,
    /// Each answer by the request that got it, in canonical JSON.
    answers: Mutex<HashMap<String, serde_json::Value>>,
}

impl JevPlugin {
    pub fn new() -> Result<Self, Diagnostic> {
        let tree = nusage_plugin::commands("jev", SPEC)?;
        let agent = ureq::Agent::config_builder()
            .http_status_as_error(false)
            .timeout_global(Some(std::time::Duration::from_secs(120)))
            .build()
            .into();
        Ok(JevPlugin {
            tree,
            agent,
            answers: Mutex::new(HashMap::new()),
        })
    }

    /// The service's answer to `questions` about `state` from `model`: the one already
    /// given to this request, else the service's, kept. An answer kept keeps the plugin
    /// running, since it lives nowhere else yet.
    pub fn judge(
        &self,
        engine: &EngineInterface,
        model: &str,
        state: serde_json::Value,
        questions: serde_json::Value,
        span: Span,
    ) -> Result<serde_json::Value, LabeledError> {
        let request = serde_json::json!({"model": model, "state": state, "questions": questions});
        let key = value::canonical(&request);
        if let Some(answer) = self
            .answers
            .lock()
            .expect("no panic holds the answers")
            .get(&key)
        {
            return Ok(answer.clone());
        }
        let base =
            nusage_plugin::env(engine, &["TYPESAFE_URL"])?.unwrap_or_else(|| BASE.to_string());
        let token = nusage_plugin::env(engine, &["TYPESAFE_TOKEN", "TYPESAFE_API_KEY"])?
            .ok_or_else(|| {
                LabeledError::new("the service wants a key: set $env.TYPESAFE_TOKEN")
                    .with_label("this call", span)
            })?;
        let url = format!("{}/v1/systemone", base.trim_end_matches('/'));
        let mut response = self
            .agent
            .post(&url)
            .header("Authorization", &format!("Bearer {token}"))
            .send_json(&request)
            .map_err(|err| {
                LabeledError::new(format!("POST {url}: {err}")).with_label("this call", span)
            })?;
        let status = response.status().as_u16();
        let text = response.body_mut().read_to_string().map_err(|err| {
            LabeledError::new(format!("POST {url}: {err}")).with_label("this call", span)
        })?;
        if !(200..300).contains(&status) {
            return Err(
                LabeledError::new(format!("POST {url} answered {status}\n{text}"))
                    .with_label("this call", span),
            );
        }
        let answer: serde_json::Value = serde_json::from_str(&text).map_err(|err| {
            LabeledError::new(format!("POST {url}: the response is not JSON: {err}"))
                .with_label("this call", span)
        })?;
        self.answers
            .lock()
            .expect("no panic holds the answers")
            .insert(key, answer.clone());
        engine.set_gc_disabled(true)?;
        Ok(answer)
    }
}

impl Plugin for JevPlugin {
    fn version(&self) -> String {
        env!("CARGO_PKG_VERSION").into()
    }

    fn commands(&self) -> Vec<Box<dyn PluginCommand<Plugin = Self>>> {
        let tree = &self.tree;
        vec![
            Box::new(Jev::new(tree).expect("the spec has a root")),
            Box::new(Ask::new(tree).expect("the spec declares `ask`")),
            Box::new(Noul::new(tree).expect("the spec declares `noul`")),
        ]
    }
}
