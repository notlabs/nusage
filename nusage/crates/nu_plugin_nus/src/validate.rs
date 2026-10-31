//! `nus validate`, as the CLI has it: a schema, documents, `--lines`. The documents are
//! the files named and the input, with `-` consuming the input at that position. Text is
//! one JSON document, or one per line with `--lines`; a value is the document it is,
//! including null; a stream is one document per item. No input is no document. The result
//! is every finding as a row, `{document, line, path, what}`, and no rows when every
//! document conforms. A schema that cannot be read or is not in the dialect is an error,
//! as the CLI's exit code 2 says nothing was held to anything.

use nusage_plugin::nu_plugin::{EngineInterface, EvaluatedCall, PluginCommand};
use nusage_plugin::nu_protocol::{
    LabeledError, PipelineData, Record, Signature, Span, Spanned, Type, Value,
};
use nusage_plugin::{CommandTree, Declared, value};
use nushell_schema::validate::Schema;

use crate::NusagePlugin;

pub struct Validate(Declared);

impl Validate {
    pub fn new(tree: &CommandTree) -> Result<Self, String> {
        let findings = nusage_plugin::nu_type(
            "table<document: string, line: oneof<int, nothing>, path: string, what: string>",
        )?;
        Ok(Validate(Declared::new(
            tree,
            &["validate"],
            vec![
                (Type::Nothing, Some(findings.clone())),
                (Type::String, Some(findings.clone())),
                (Type::Any, Some(findings)),
            ],
        )?))
    }
}

/// The documents held to the schema so far: a finding a row each.
struct Held {
    schema: Schema,
    lines: bool,
    span: Span,
    findings: Vec<Value>,
}

impl Held {
    fn json(&mut self, name: &str, line: Option<usize>, document: &serde_json::Value) {
        for finding in self.schema.findings(document) {
            self.findings
                .push(row(name, line, &finding.path, &finding.what, self.span));
        }
    }

    /// Text as one document, or one per line that is not blank with `--lines`; text that is
    /// not JSON is a finding on the document, with no path into it.
    fn text(&mut self, name: &str, text: &str) {
        if self.lines {
            for (index, line) in text.lines().enumerate() {
                if !line.trim().is_empty() {
                    self.one(name, Some(index + 1), line);
                }
            }
        } else {
            self.one(name, None, text);
        }
    }

    fn one(&mut self, name: &str, line: Option<usize>, text: &str) {
        match serde_json::from_str::<serde_json::Value>(text) {
            Ok(document) => self.json(name, line, &document),
            Err(err) => self
                .findings
                .push(row(name, line, "", &err.to_string(), self.span)),
        }
    }

    fn input(&mut self, name: &str, input: PipelineData) -> Result<(), LabeledError> {
        match input {
            PipelineData::Empty => {}
            PipelineData::Value(Value::String { val, .. }, _) => self.text(name, &val),
            PipelineData::Value(other, _) => self.json(name, None, &value::to_json(&other)?),
            PipelineData::ByteStream(stream, _) => self.text(name, &stream.into_string()?),
            PipelineData::ListStream(stream, _) => {
                for (index, item) in stream.into_iter().enumerate() {
                    self.json(name, Some(index + 1), &value::to_json(&item)?);
                }
            }
        }
        Ok(())
    }
}

/// A finding as a row.
fn row(document: &str, line: Option<usize>, path: &str, what: &str, span: Span) -> Value {
    let mut record = Record::new();
    record.push("document", Value::string(document, span));
    record.push(
        "line",
        match line {
            Some(line) => Value::int(line as i64, span),
            None => Value::nothing(span),
        },
    );
    record.push("path", Value::string(path, span));
    record.push("what", Value::string(what, span));
    Value::record(record, span)
}

impl PluginCommand for Validate {
    type Plugin = NusagePlugin;

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
        _plugin: &NusagePlugin,
        engine: &EngineInterface,
        call: &EvaluatedCall,
        input: PipelineData,
    ) -> Result<PipelineData, LabeledError> {
        let span = call.head;
        let schema: Spanned<String> = call.req(0)?;
        let documents: Vec<Spanned<String>> = call.rest(1)?;
        let lines = call.has_flag("lines")?;
        let cwd = std::path::PathBuf::from(engine.get_current_dir()?);
        let schema_path = cwd.join(&schema.item);
        let text = std::fs::read_to_string(&schema_path).map_err(|err| {
            LabeledError::new(format!("{}: {err}", schema_path.display()))
                .with_label("the schema", schema.span)
        })?;
        let schema_json: serde_json::Value = serde_json::from_str(&text).map_err(|err| {
            LabeledError::new(format!("{}: {err}", schema_path.display()))
                .with_label("not JSON", schema.span)
        })?;
        let schema = Schema::new(&schema_json).map_err(|err| {
            LabeledError::new(format!("{}: {err}", schema_path.display()))
                .with_label("not a schema in the dialect", schema.span)
        })?;
        let mut held = Held {
            schema,
            lines,
            span,
            findings: Vec::new(),
        };
        let mut input = Some(input);
        for document in &documents {
            if document.item == "-" {
                match input.take() {
                    // Like an exhausted stdin, an explicitly requested empty input is an
                    // empty document. Without `-`, no input holds the schema alone.
                    None | Some(PipelineData::Empty) => held.text("-", ""),
                    Some(input) => held.input("-", input)?,
                }
                continue;
            }
            let path = cwd.join(&document.item);
            let text = std::fs::read_to_string(&path).map_err(|err| {
                LabeledError::new(format!("{}: {err}", path.display()))
                    .with_label("the document", document.span)
            })?;
            held.text(&document.item, &text);
        }
        if let Some(input) = input {
            held.input("input", input)?;
        }
        let findings = held.findings;
        Ok(PipelineData::value(Value::list(findings, span), None))
    }
}
