//! Schema discovery and retrieval shared by explicit and automatic validation.
//! No tool names live here. A schema's dialect and its retrieval permission are separate.

use std::io::Read;
use std::path::Path;
use std::sync::Arc;
use std::time::Duration;

use globset::{GlobBuilder, GlobMatcher};
use nusage_spec::Diagnostic;
use serde_json::{Value, json};
use url::Url;

/// The identity used by the earlier nuon-schema implementation. Recognition is exact;
/// merely naming a standard JSON Schema draft does not make a JSONL record a header.
pub const NUON_DIALECT: &str = "https://gerrit.tail3b571d.ts.net/plugins/gitiles/notlabs/+/refs/heads/nusage/nuon-schema/nusage/nuon-schema/meta.json";
const DRAFT: &str = "https://json-schema.org/draft/2020-12/schema";
const MAX_SCHEMA_BYTES: u64 = 4 * 1024 * 1024;

struct Allowed {
    uri: Url,
    path: GlobMatcher,
}

/// Shared with jsonschema's retriever, so external references obey the same policy as
/// the schema a data record names. Redirects are refused rather than escaping the list.
#[derive(Clone)]
pub struct Resolver(Arc<Vec<Allowed>>);

impl Resolver {
    pub fn new(allow: Option<&str>) -> Result<Self, Diagnostic> {
        let error = |message| {
            Diagnostic::new("NUSAGE_SCHEMA_ALLOW", message).with_code("nusage::schema::policy")
        };
        let patterns: Vec<String> = serde_json::from_str(allow.unwrap_or("[]")).map_err(|e| {
            error(format!(
                "expected a JSON list of schema URLs or path globs: {e}"
            ))
        })?;
        let mut allowed = Vec::new();
        for pattern in patterns {
            let uri = Url::parse(&pattern).map_err(|e| error(e.to_string()))?;
            if !matches!(uri.scheme(), "https" | "http" | "file")
                || uri.host_str().is_some_and(|h| h.contains(['*', '[', ']']))
                || !uri.username().is_empty()
                || uri.password().is_some()
                || uri.fragment().is_some()
            {
                return Err(error(format!(
                    "use an http(s) or file URL with a literal host and no credentials or fragment: {pattern}"
                )));
            }
            let path = GlobBuilder::new(uri.path())
                .literal_separator(true)
                .build()
                .map_err(|e| error(e.to_string()))?
                .compile_matcher();
            allowed.push(Allowed { uri, path });
        }
        Ok(Self(Arc::new(allowed)))
    }

    pub fn allows(&self, uri: &Url) -> bool {
        self.0.iter().any(|a| {
            a.uri.scheme() == uri.scheme()
                && a.uri.host_str() == uri.host_str()
                && a.uri.port_or_known_default() == uri.port_or_known_default()
                && a.uri.query() == uri.query()
                && uri.username().is_empty()
                && uri.password().is_none()
                && a.path.is_match(uri.path())
        })
    }

    /// Relative names have the same base as before: the input file's directory, or PWD.
    pub fn named(&self, name: &str, base: &Url) -> Result<Option<(Url, Value)>, Diagnostic> {
        let uri = base.join(name).map_err(|e| failure(name, e.to_string()))?;
        if uri.as_str() == NUON_DIALECT {
            return Ok(Some((uri, json!({"$schema": DRAFT, "$ref": DRAFT}))));
        }
        let local = uri.scheme() == "file";
        if !local && !self.allows(&uri) {
            return Ok(None);
        }
        let schema = match self.read(&uri) {
            Err(e) if local && e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            result => result.map_err(|e| failure(uri.as_str(), e.to_string()))?,
        };
        // Preserve the old implicit local discovery rule. An explicit allowlist can
        // additionally opt a local schema in a standard dialect into validation.
        if local
            && !self.allows(&uri)
            && schema
                .get("$schema")
                .is_some_and(|v| v.as_str() != Some(NUON_DIALECT))
        {
            return Ok(None);
        }
        Ok(Some((uri, schema)))
    }

    fn read(&self, uri: &Url) -> std::io::Result<Value> {
        let reader: Box<dyn Read> = if uri.scheme() == "file" {
            let path = uri
                .to_file_path()
                .map_err(|()| std::io::Error::other("invalid file URL"))?;
            Box::new(std::fs::File::open(path)?)
        } else {
            let response = reqwest::blocking::Client::builder()
                .redirect(reqwest::redirect::Policy::none())
                .timeout(Duration::from_secs(10))
                .build()
                .map_err(std::io::Error::other)?
                .get(uri.clone())
                .send()
                .map_err(std::io::Error::other)?;
            if !response.status().is_success() {
                return Err(std::io::Error::other(format!(
                    "HTTP {} (redirects are not followed)",
                    response.status()
                )));
            }
            Box::new(response)
        };
        let mut bytes = Vec::new();
        reader.take(MAX_SCHEMA_BYTES + 1).read_to_end(&mut bytes)?;
        if bytes.len() as u64 > MAX_SCHEMA_BYTES {
            return Err(std::io::Error::other("schema exceeds 4 MiB"));
        }
        serde_json::from_slice(&bytes).map_err(std::io::Error::other)
    }
}

impl jsonschema::Retrieve for Resolver {
    fn retrieve(
        &self,
        uri: &jsonschema::Uri<String>,
    ) -> Result<Value, Box<dyn std::error::Error + Send + Sync>> {
        let uri = Url::parse(uri.as_str())?;
        if !self.allows(&uri) {
            return Err(
                format!("schema reference is not allowed by NUSAGE_SCHEMA_ALLOW: {uri}").into(),
            );
        }
        Ok(normalize(self.read(&uri)?))
    }
}

pub fn inline(value: &Value) -> bool {
    value.get("$schema").and_then(Value::as_str) == Some(NUON_DIALECT)
}

/// x-nu is an annotation vocabulary: the wire value is validated under 2020-12 before
/// the existing generated conversions run. Full codec reintegration is separate.
fn normalize(mut schema: Value) -> Value {
    if inline(&schema) {
        schema["$schema"] = DRAFT.into();
    }
    schema
}

pub fn compile(
    schema: Value,
    uri: &Url,
    resolver: &Resolver,
) -> Result<jsonschema::Validator, Diagnostic> {
    let schema = normalize(schema);
    jsonschema::meta::validate(&schema)
        .map_err(|e| failure(uri.as_str(), e.to_string()).with_code("nusage::schema::invalid"))?;
    let mut document = uri.clone();
    document.set_fragment(None);
    let registry = jsonschema::Registry::new()
        .retriever(resolver.clone())
        .add(document.as_str(), schema)
        .and_then(|builder| builder.prepare())
        .map_err(|e| failure(uri.as_str(), e.to_string()))?;
    jsonschema::options()
        .with_registry(&registry)
        .with_base_uri("urn:nusage:validation-root")
        .should_validate_formats(true)
        .build(&json!({"$ref": uri.as_str()}))
        .map_err(|e| failure(uri.as_str(), e.to_string()).with_code("nusage::schema::invalid"))
}

pub fn base(path: &Path) -> Result<Url, Diagnostic> {
    let path = std::path::absolute(path)
        .map_err(|e| failure(&path.display().to_string(), e.to_string()))?;
    Url::from_file_path(&path)
        .map_err(|()| failure(&path.display().to_string(), "invalid file path".into()))
}

fn failure(source: &str, message: String) -> Diagnostic {
    Diagnostic::new(source, message).with_code("nusage::schema::resolve")
}
