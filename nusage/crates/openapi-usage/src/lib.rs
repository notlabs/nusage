//! An OpenAPI document as a usage spec, with the HTTP mapping beside it.
//!
//! usage describes a CLI: commands, their arguments and flags, and what they return. An API
//! described by OpenAPI is the same shape once each operation is a command: a path
//! parameter is a positional, a query or header parameter a flag, a JSON response an
//! output with its schema. [`transform`] writes that spec, which usage's own tools then
//! complete, document and check. What usage has no words for, the method, the path
//! template, where each parameter goes on the wire, the request body and how the API is
//! authenticated, goes in a second KDL document beside the spec, the [HTTP
//! mapping](Transformed::http), for whatever runs the commands. Each output's schema is
//! bundled into a file of its own, every `#/components/schemas/...` it reaches in its
//! `$defs`, read as draft 2020-12 whatever version the document is.
//!
//! OpenAPI 3.0 and 3.1 are read, as JSON; a YAML document is converted first. What is not
//! read: cookie parameters, parameters with a `content` rather than a `schema`, per-operation
//! security, and callbacks, links and webhooks. A boolean query or header parameter is a
//! switch, sent as `true` when given, since a Nushell flag takes no boolean value.

#![forbid(unsafe_code)]
#![warn(missing_docs)]

use std::collections::BTreeMap;

use serde::Deserialize;
use serde_json::{Map, Value};

/// What to call the spec.
#[derive(Debug, Clone, Default)]
pub struct Options {
    /// The spec's `name`: the document's title as a word when absent.
    pub name: Option<String>,
    /// The spec's `bin`: the name when absent.
    pub bin: Option<String>,
}

/// The spec and what goes beside it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Transformed {
    /// The usage spec, as KDL.
    pub spec: String,
    /// The HTTP mapping, as KDL: `base`, `auth`, and a `cmd` per command with its method,
    /// path template, where each parameter goes and its body.
    pub http: String,
    /// Each schema the spec and the mapping name, by the path they name it with, relative
    /// to the spec: `schemas/<cmd>.schema.json` for a command's output,
    /// `schemas/<cmd>.body.schema.json` for its request body.
    pub schemas: BTreeMap<String, Value>,
}

/// Why a document cannot be transformed.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[non_exhaustive]
pub enum Error {
    /// Not an OpenAPI document.
    #[error("not an OpenAPI document: {0}")]
    Document(String),
    /// A version other than 3.0 or 3.1.
    #[error("OpenAPI {0} is not read; 3.0 and 3.1 are")]
    Version(String),
    /// A `$ref` outside the document's components.
    #[error("{at}: `$ref` {reference:?} cannot be followed; only `#/components/...` can")]
    Reference {
        /// The operation or component it is in.
        at: String,
        /// The reference as written.
        reference: String,
    },
    /// An operation that cannot be read.
    #[error("{at}: {what}")]
    Operation {
        /// The operation, as `<METHOD> <path>`.
        at: String,
        /// What is wrong with it.
        what: String,
    },
}

/// The document as a spec.
pub fn transform(document: &Value, options: &Options) -> Result<Transformed, Error> {
    let doc: Document =
        serde_json::from_value(document.clone()).map_err(|err| Error::Document(err.to_string()))?;
    let version = doc.openapi.as_str();
    if !version.starts_with("3.0") && !version.starts_with("3.1") {
        return Err(Error::Version(doc.openapi.clone()));
    }
    let is_30 = version.starts_with("3.0");
    let name = options
        .name
        .clone()
        .unwrap_or_else(|| word(&doc.info.title));
    let bin = options.bin.clone().unwrap_or_else(|| name.clone());

    let mut spec = vec![
        Node::new("name").arg(name),
        Node::new("bin").arg(bin),
        Node::new("about").arg(line(&doc.info.title)),
    ];
    if let Some(description) = doc
        .info
        .description
        .as_deref()
        .filter(|d| !d.trim().is_empty())
    {
        spec.push(Node::new("long_about").arg(description.trim()));
    }
    if let Some(version) = &doc.info.version {
        spec.push(Node::new("version").arg(version));
    }

    let mut http = Vec::new();
    if let Some(server) = doc.servers.first() {
        http.push(Node::new("base").arg(&server.url));
    }
    http.extend(auths(&doc));

    let mut schemas = BTreeMap::new();
    let mut names: Vec<String> = Vec::new();
    for (path, item) in &doc.paths {
        let item: PathItem =
            serde_json::from_value(item.clone()).map_err(|err| Error::Operation {
                at: path.clone(),
                what: err.to_string(),
            })?;
        for method in METHODS {
            let Some(operation) = item.operations.get(*method) else {
                continue;
            };
            let at = format!("{} {path}", method.to_uppercase());
            let operation: Operation =
                serde_json::from_value(operation.clone()).map_err(|err| Error::Operation {
                    at: at.clone(),
                    what: err.to_string(),
                })?;
            let mut name = command_name(&operation, method, path);
            if names.contains(&name) {
                name = format!("{name}-{method}");
            }
            names.push(name.clone());
            let command = Command::read(&doc, &at, &name, method, path, &item, &operation)?;
            spec.push(command.spec_node());
            http.push(command.http_node());
            for (file, schema) in command.schemas {
                let mut schema = schema;
                if is_30 {
                    nushell_schema::dialect::from_openapi_30(&mut schema);
                }
                schemas.insert(file, schema);
            }
        }
    }
    Ok(Transformed {
        spec: document_text(&spec),
        http: document_text(&http),
        schemas,
    })
}

const METHODS: &[&str] = &[
    "get", "put", "post", "delete", "options", "head", "patch", "trace",
];

#[derive(Deserialize)]
struct Document {
    openapi: String,
    info: Info,
    #[serde(default)]
    servers: Vec<Server>,
    #[serde(default)]
    paths: Map<String, Value>,
    #[serde(default)]
    components: Components,
    #[serde(default)]
    security: Vec<Map<String, Value>>,
}

#[derive(Deserialize)]
struct Info {
    title: String,
    #[serde(default)]
    description: Option<String>,
    #[serde(default)]
    version: Option<String>,
}

#[derive(Deserialize)]
struct Server {
    url: String,
}

#[derive(Deserialize, Default)]
struct Components {
    #[serde(default)]
    schemas: Map<String, Value>,
    #[serde(default)]
    parameters: Map<String, Value>,
    #[serde(default)]
    responses: Map<String, Value>,
    #[serde(default, rename = "requestBodies")]
    request_bodies: Map<String, Value>,
    #[serde(default, rename = "securitySchemes")]
    security_schemes: Map<String, Value>,
}

#[derive(Deserialize)]
struct PathItem {
    #[serde(default)]
    parameters: Vec<Value>,
    #[serde(flatten)]
    operations: Map<String, Value>,
}

#[derive(Deserialize)]
struct Operation {
    #[serde(default, rename = "operationId")]
    operation_id: Option<String>,
    #[serde(default)]
    summary: Option<String>,
    #[serde(default)]
    description: Option<String>,
    #[serde(default)]
    parameters: Vec<Value>,
    #[serde(default, rename = "requestBody")]
    request_body: Option<Value>,
    #[serde(default)]
    responses: Map<String, Value>,
    #[serde(default)]
    deprecated: bool,
}

#[derive(Deserialize, Clone)]
struct Parameter {
    name: String,
    #[serde(rename = "in")]
    location: String,
    #[serde(default)]
    required: bool,
    #[serde(default)]
    description: Option<String>,
    #[serde(default)]
    schema: Option<Value>,
}

#[derive(Deserialize)]
struct Content {
    #[serde(default)]
    content: Map<String, Value>,
    #[serde(default)]
    required: bool,
}

/// A command of the spec, with its transport.
struct Command {
    name: String,
    method: String,
    path: String,
    help: Option<String>,
    deprecated: bool,
    positionals: Vec<Param>,
    flags: Vec<Param>,
    body: Option<Body>,
    /// The output schema's file, when a 2xx response is JSON.
    output: Option<String>,
    schemas: Vec<(String, Value)>,
}

/// A parameter as the spec spells it and as the wire names it.
struct Param {
    /// On the wire.
    wire: String,
    /// In the spec: a word.
    spec: String,
    location: String,
    required: bool,
    help: Option<String>,
    ty: ParamType,
}

enum ParamType {
    /// Text, or anything the spec cannot type.
    Text,
    /// A Nushell type annotation: `int`, `float`, `bool`.
    Typed(&'static str),
    /// One of these values.
    Choices(Vec<String>),
    /// Several values of the type.
    List(Box<ParamType>),
}

struct Body {
    media: String,
    required: bool,
    /// The schema's file, when the body is JSON.
    schema: Option<String>,
}

impl Command {
    #[allow(clippy::too_many_arguments)]
    fn read(
        doc: &Document,
        at: &str,
        name: &str,
        method: &str,
        path: &str,
        item: &PathItem,
        operation: &Operation,
    ) -> Result<Command, Error> {
        // The path item's parameters apply to every operation; an operation's own override
        // them by name and location.
        let mut parameters: Vec<Parameter> = Vec::new();
        for raw in item.parameters.iter().chain(&operation.parameters) {
            let resolved = resolve(doc, at, raw, "parameters")?;
            let parameter: Parameter =
                serde_json::from_value(resolved).map_err(|err| Error::Operation {
                    at: at.to_string(),
                    what: format!("a parameter: {err}"),
                })?;
            parameters
                .retain(|seen| seen.name != parameter.name || seen.location != parameter.location);
            parameters.push(parameter);
        }
        let mut positionals = Vec::new();
        let mut flags = Vec::new();
        for parameter in parameters {
            let param = Param {
                wire: parameter.name.clone(),
                spec: word(&parameter.name),
                location: parameter.location.clone(),
                required: parameter.required || parameter.location == "path",
                help: parameter.description.as_deref().map(line),
                ty: param_type(parameter.schema.as_ref()),
            };
            match parameter.location.as_str() {
                "path" => positionals.push(param),
                "query" | "header" => flags.push(param),
                // Cookies are not a CLI's to set.
                _ => {}
            }
        }
        // The positionals in the order the path names them.
        positionals.sort_by_key(|param| path.find(&format!("{{{}}}", param.wire)));

        let mut schemas = Vec::new();
        let body = match &operation.request_body {
            Some(raw) => {
                let resolved = resolve(doc, at, raw, "requestBodies")?;
                let content: Content =
                    serde_json::from_value(resolved).map_err(|err| Error::Operation {
                        at: at.to_string(),
                        what: format!("the request body: {err}"),
                    })?;
                content.content.iter().next().map(|(media, media_type)| {
                    let schema = is_json(media)
                        .then(|| media_type.get("schema"))
                        .flatten()
                        .map(|schema| {
                            let file = format!("schemas/{name}.body.schema.json");
                            schemas.push((file.clone(), bundle(doc, at, schema)));
                            file
                        });
                    Body {
                        media: media.clone(),
                        required: content.required,
                        schema,
                    }
                })
            }
            None => None,
        };
        let mut output = None;
        if let Some(response) = success(&operation.responses) {
            let resolved = resolve(doc, at, response, "responses")?;
            let content: Content =
                serde_json::from_value(resolved).map_err(|err| Error::Operation {
                    at: at.to_string(),
                    what: format!("a response: {err}"),
                })?;
            if let Some(schema) = content
                .content
                .iter()
                .find(|(media, _)| is_json(media))
                .and_then(|(_, media_type)| media_type.get("schema"))
            {
                let file = format!("schemas/{name}.schema.json");
                schemas.push((file.clone(), bundle(doc, at, schema)));
                output = Some(file);
            }
        }
        let schemas = schemas
            .into_iter()
            .map(|(file, schema)| schema.map(|schema| (file, schema)))
            .collect::<Result<Vec<_>, _>>()?;
        Ok(Command {
            name: name.to_string(),
            method: method.to_string(),
            path: path.to_string(),
            help: operation
                .summary
                .as_deref()
                .or(operation.description.as_deref())
                .map(line),
            deprecated: operation.deprecated,
            positionals,
            flags,
            body,
            output,
            schemas,
        })
    }

    fn spec_node(&self) -> Node {
        let mut cmd = Node::new("cmd").arg(&self.name);
        if let Some(help) = &self.help {
            cmd = cmd.prop("help", help);
        }
        if self.deprecated {
            cmd = cmd.flag("deprecated");
        }
        for param in &self.flags {
            let mut flag = Node::new("flag").arg(format!("--{}", param.spec));
            if let Some(help) = &param.help {
                flag = flag.prop("help", help);
            }
            if param.required {
                flag = flag.flag("required");
            }
            // A boolean is a switch: given, it goes on the wire as `true`. A Nushell flag
            // takes no boolean value.
            if matches!(param.ty, ParamType::Typed("bool")) {
                cmd = cmd.child(flag);
                continue;
            }
            let (ty, choices) = match &param.ty {
                ParamType::List(inner) => {
                    flag = flag.flag("var");
                    annotation(inner)
                }
                other => annotation(other),
            };
            let value = format!("<{}>", param.spec.to_uppercase().replace('-', "_"));
            let mut arg = Node::new("arg").typed(ty, value);
            if let Some(choices) = choices {
                arg = arg.child(Node::new("choices").args(choices));
            }
            cmd = cmd.child(flag.child(arg));
        }
        for param in &self.positionals {
            let (ty, choices) = annotation(&param.ty);
            let mut arg = Node::new("arg").typed(ty, format!("<{}>", param.spec));
            if let Some(help) = &param.help {
                arg = arg.prop("help", help);
            }
            if let Some(choices) = choices {
                arg = arg.child(Node::new("choices").args(choices));
            }
            cmd = cmd.child(arg);
        }
        if let Some(file) = &self.output {
            let output = Node::new("output")
                .arg("json")
                .prop("framing", "json")
                .flag("default")
                .child(Node::new("schema").prop("file", file));
            cmd = cmd.child(output);
        }
        cmd
    }

    fn http_node(&self) -> Node {
        let mut cmd = Node::new("cmd")
            .arg(&self.name)
            .prop("method", &self.method)
            .prop("path", &self.path);
        for param in &self.positionals {
            cmd = cmd.child(Node::new("path").arg(&param.wire).prop("arg", &param.spec));
        }
        for param in &self.flags {
            cmd = cmd.child(
                Node::new(&param.location)
                    .arg(&param.wire)
                    .prop("flag", &param.spec),
            );
        }
        if let Some(body) = &self.body {
            let mut node = Node::new("body").arg(&body.media);
            if let Some(schema) = &body.schema {
                node = node.prop("schema", schema);
            }
            if body.required {
                node = node.flag("required");
            }
            cmd = cmd.child(node);
        }
        cmd
    }
}

/// The type annotation and the choices a parameter's spec arg carries.
fn annotation(ty: &ParamType) -> (Option<&'static str>, Option<&[String]>) {
    match ty {
        ParamType::Text => (None, None),
        ParamType::Typed(ty) => (Some(ty), None),
        ParamType::Choices(choices) => (None, Some(choices)),
        ParamType::List(inner) => annotation(inner),
    }
}

fn param_type(schema: Option<&Value>) -> ParamType {
    let Some(schema) = schema else {
        return ParamType::Text;
    };
    if let Some(values) = schema.get("enum").and_then(Value::as_array) {
        let choices: Vec<String> = values
            .iter()
            .filter_map(|value| match value {
                Value::String(text) => Some(text.clone()),
                Value::Number(n) => Some(n.to_string()),
                Value::Bool(b) => Some(b.to_string()),
                _ => None,
            })
            .collect();
        if !choices.is_empty() {
            return ParamType::Choices(choices);
        }
    }
    let ty = match schema.get("type") {
        Some(Value::String(ty)) => Some(ty.as_str()),
        Some(Value::Array(types)) => types
            .iter()
            .filter_map(Value::as_str)
            .find(|t| *t != "null"),
        _ => None,
    };
    match ty {
        Some("integer") => ParamType::Typed("int"),
        Some("number") => ParamType::Typed("float"),
        Some("boolean") => ParamType::Typed("bool"),
        Some("array") => ParamType::List(Box::new(param_type(schema.get("items")))),
        _ => ParamType::Text,
    }
}

/// The first response that says success, a `2xx` before `2XX` before `default`.
fn success(responses: &Map<String, Value>) -> Option<&Value> {
    let mut codes: Vec<&String> = responses
        .keys()
        .filter(|code| code.starts_with('2'))
        .collect();
    codes.sort();
    codes
        .first()
        .map(|code| &responses[*code])
        .or_else(|| responses.get("default"))
}

fn is_json(media: &str) -> bool {
    let media = media.split(';').next().unwrap_or(media).trim();
    media == "application/json" || media.ends_with("+json")
}

/// `value`, or the component it refers to.
fn resolve(doc: &Document, at: &str, value: &Value, kind: &str) -> Result<Value, Error> {
    let Some(reference) = value.get("$ref").and_then(Value::as_str) else {
        return Ok(value.clone());
    };
    let components = match kind {
        "parameters" => &doc.components.parameters,
        "responses" => &doc.components.responses,
        "requestBodies" => &doc.components.request_bodies,
        _ => unreachable!("a component kind"),
    };
    reference
        .strip_prefix(&format!("#/components/{kind}/"))
        .and_then(|name| components.get(name))
        .cloned()
        .ok_or_else(|| Error::Reference {
            at: at.to_string(),
            reference: reference.to_string(),
        })
}

/// The schema on its own: every `#/components/schemas/<name>` it reaches in its `$defs`,
/// and the references rewritten to them.
fn bundle(doc: &Document, at: &str, schema: &Value) -> Result<Value, Error> {
    let mut defs = Map::new();
    let mut pending: Vec<String> = Vec::new();
    let mut root = schema.clone();
    rewrite(&mut root, at, &mut pending)?;
    while let Some(name) = pending.pop() {
        if defs.contains_key(&name) {
            continue;
        }
        let Some(component) = doc.components.schemas.get(&name) else {
            return Err(Error::Reference {
                at: at.to_string(),
                reference: format!("#/components/schemas/{name}"),
            });
        };
        let mut component = component.clone();
        rewrite(&mut component, at, &mut pending)?;
        defs.insert(name, component);
    }
    let mut bundled = Map::new();
    bundled.insert(
        "$schema".into(),
        Value::String("https://json-schema.org/draft/2020-12/schema".into()),
    );
    if !defs.is_empty() {
        bundled.insert("$defs".into(), Value::Object(defs));
    }
    match root {
        Value::Object(fields) => bundled.extend(fields),
        // `true` or `false`: anything, or nothing.
        other => return Ok(other),
    }
    Ok(Value::Object(bundled))
}

/// Every `$ref` in `schema` as `#/$defs/<name>`, the names collected.
fn rewrite(schema: &mut Value, at: &str, pending: &mut Vec<String>) -> Result<(), Error> {
    match schema {
        Value::Object(object) => {
            if let Some(Value::String(reference)) = object.get_mut("$ref") {
                let Some(name) = reference.strip_prefix("#/components/schemas/") else {
                    return Err(Error::Reference {
                        at: at.to_string(),
                        reference: reference.clone(),
                    });
                };
                let name = name.to_string();
                *reference = format!("#/$defs/{name}");
                pending.push(name);
            }
            for (key, member) in object.iter_mut() {
                if key != "$ref" {
                    rewrite(member, at, pending)?;
                }
            }
        }
        Value::Array(members) => {
            for member in members {
                rewrite(member, at, pending)?;
            }
        }
        _ => {}
    }
    Ok(())
}

/// How the API is authenticated, from the document's `security` and the schemes it names:
/// an `auth` node per scheme, `"bearer"`, `"basic"`, `"header"` or `"query"` with the
/// `name` of the key, or the scheme's type as written for the rest.
fn auths(doc: &Document) -> Vec<Node> {
    let Some(requirement) = doc.security.first() else {
        return Vec::new();
    };
    requirement
        .keys()
        .filter_map(|name| {
            let scheme = doc.components.security_schemes.get(name)?;
            let ty = scheme.get("type").and_then(Value::as_str)?;
            let text = |key: &str| scheme.get(key).and_then(Value::as_str).map(str::to_string);
            let kind = match (ty, text("scheme").as_deref(), text("in").as_deref()) {
                ("http", Some("bearer"), _) => "bearer".to_string(),
                ("http", Some("basic"), _) => "basic".to_string(),
                ("apiKey", _, Some(location)) => location.to_string(),
                _ => ty.to_string(),
            };
            let mut auth = Node::new("auth").arg(kind);
            if ty == "apiKey" {
                auth = auth.prop("name", text("name").unwrap_or_default());
            }
            Some(auth)
        })
        .collect()
}

/// The command's name: `operationId` as a word, else the method and the path's words.
fn command_name(operation: &Operation, method: &str, path: &str) -> String {
    if let Some(id) = operation
        .operation_id
        .as_deref()
        .filter(|id| !id.trim().is_empty())
    {
        return word(id);
    }
    let words: Vec<&str> = path
        .split('/')
        .filter(|segment| !segment.is_empty())
        .map(|segment| segment.trim_matches(|c| c == '{' || c == '}'))
        .collect();
    word(&format!("{method} {}", words.join(" ")))
}

/// Text as a word of a spec: lower case, the words joined by `-`, a camel-case boundary a
/// word boundary too.
fn word(text: &str) -> String {
    let mut out = String::new();
    let mut previous_lower = false;
    for c in text.chars() {
        if c.is_ascii_alphanumeric() {
            if c.is_ascii_uppercase() && previous_lower {
                out.push('-');
            }
            out.push(c.to_ascii_lowercase());
            previous_lower = c.is_ascii_lowercase() || c.is_ascii_digit();
        } else {
            if !out.ends_with('-') && !out.is_empty() {
                out.push('-');
            }
            previous_lower = false;
        }
    }
    out.trim_end_matches('-').to_string()
}

/// Text on one line, for a `help`: the first paragraph, its lines joined.
fn line(text: &str) -> String {
    text.trim()
        .split("\n\n")
        .next()
        .unwrap_or_default()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

/// A KDL node as a spec is written by hand: `name "arg" key="value" { children }`, every
/// string quoted, so a KDL reader of either version takes it.
struct Node {
    name: String,
    args: Vec<Entry>,
    props: Vec<(String, Entry)>,
    children: Vec<Node>,
}

enum Entry {
    Str(String),
    /// `(ty)"text"`: a string with a type annotation.
    Typed(&'static str, String),
    Bool(bool),
}

impl Node {
    fn new(name: &str) -> Node {
        Node {
            name: name.to_string(),
            args: Vec::new(),
            props: Vec::new(),
            children: Vec::new(),
        }
    }

    fn arg(mut self, text: impl Into<String>) -> Node {
        self.args.push(Entry::Str(text.into()));
        self
    }

    fn args<T: Into<String>>(mut self, texts: impl IntoIterator<Item = T>) -> Node {
        for text in texts {
            self = self.arg(text);
        }
        self
    }

    fn typed(mut self, ty: Option<&'static str>, text: impl Into<String>) -> Node {
        self.args.push(match ty {
            Some(ty) => Entry::Typed(ty, text.into()),
            None => Entry::Str(text.into()),
        });
        self
    }

    fn prop(mut self, key: &str, text: impl Into<String>) -> Node {
        self.props.push((key.to_string(), Entry::Str(text.into())));
        self
    }

    /// `key=#true`.
    fn flag(mut self, key: &str) -> Node {
        self.props.push((key.to_string(), Entry::Bool(true)));
        self
    }

    fn child(mut self, node: Node) -> Node {
        self.children.push(node);
        self
    }

    fn write(&self, out: &mut String, depth: usize) {
        out.push_str(&"    ".repeat(depth));
        out.push_str(&self.name);
        for arg in &self.args {
            out.push(' ');
            arg.write(out);
        }
        for (key, value) in &self.props {
            out.push(' ');
            out.push_str(key);
            out.push('=');
            value.write(out);
        }
        if !self.children.is_empty() {
            out.push_str(" {\n");
            for child in &self.children {
                child.write(out, depth + 1);
            }
            out.push_str(&"    ".repeat(depth));
            out.push('}');
        }
        out.push('\n');
    }
}

impl Entry {
    fn write(&self, out: &mut String) {
        match self {
            Entry::Str(text) => out.push_str(&quote(text)),
            Entry::Typed(ty, text) => {
                out.push('(');
                out.push_str(ty);
                out.push(')');
                out.push_str(&quote(text));
            }
            Entry::Bool(true) => out.push_str("#true"),
            Entry::Bool(false) => out.push_str("#false"),
        }
    }
}

/// The text as a KDL quoted string.
fn quote(text: &str) -> String {
    let mut out = String::with_capacity(text.len() + 2);
    out.push('"');
    for c in text.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            other => out.push(other),
        }
    }
    out.push('"');
    out
}

fn document_text(nodes: &[Node]) -> String {
    let mut out = String::new();
    for node in nodes {
        node.write(&mut out, 0);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn words_and_names() {
        assert_eq!(word("listPets"), "list-pets");
        assert_eq!(word("repos/get-content"), "repos-get-content");
        assert_eq!(word("Swagger Petstore"), "swagger-petstore");
        assert_eq!(word("per_page"), "per-page");
        assert_eq!(word("X-GitHub-Api-Version"), "x-git-hub-api-version");
        assert_eq!(word("v2Beta"), "v2-beta");
        let unnamed = Operation {
            operation_id: None,
            summary: None,
            description: None,
            parameters: Vec::new(),
            request_body: None,
            responses: Map::new(),
            deprecated: false,
        };
        assert_eq!(
            command_name(&unnamed, "get", "/repos/{owner}/{repo}/issues"),
            "get-repos-owner-repo-issues"
        );
    }

    #[test]
    fn a_help_is_one_line() {
        assert_eq!(
            line("  List all\n  pets.\n\nThe long story."),
            "List all pets."
        );
    }
}
