//! The explicit checker and the generated wrappers use the same validation path.
//! JSONL is read and released one record at a time, before any Nu conversion.

use std::collections::HashMap;
use std::io::{BufRead, BufReader, Read, Write};
use std::path::{Path, PathBuf};
use std::sync::Arc;

use nusage_spec::Diagnostic;
use serde_json::Value;
use url::Url;

use crate::schema::{self, Resolver};

const MAX_RECORD_BYTES: u64 = 16 * 1024 * 1024;
const MAX_FINDINGS: usize = 32;

#[derive(Default)]
pub struct ValidationOptions {
    pub schema: Option<PathBuf>,
    pub schema_json: Option<String>,
    pub auto: bool,
    pub jsonl: bool,
    pub passthrough: bool,
    /// Private generated-module transport: serde Result packets, unwrapped by Nushell.
    pub nu: bool,
    pub disabled: bool,
    /// A command label for diagnostics; files retain their own names by default.
    pub source: Option<String>,
    pub allow: Option<String>,
}

/// Compatibility entrypoint for callers checking files. No automatic discovery.
pub fn validate(schema: &Path, documents: &[impl AsRef<Path>]) -> Result<Vec<String>, String> {
    let options = ValidationOptions {
        schema: Some(schema.into()),
        ..Default::default()
    };
    let paths: Vec<_> = documents.iter().map(|p| p.as_ref().to_owned()).collect();
    match validate_with(&options, &paths, &mut std::io::sink()) {
        Ok(findings) => Ok(findings.iter().map(ToString::to_string).collect()),
        Err(d) if d.code == "nusage::schema::invalid" => Ok(vec![d.to_string()]),
        Err(d) => Err(d.to_string()),
    }
}

/// Compile once, then check each input. No input means schema-only checking, except in
/// automatic/pass-through mode where it means stdin. Findings never enter the data stream.
pub fn validate_with(
    options: &ValidationOptions,
    documents: &[PathBuf],
    output: &mut impl Write,
) -> Result<Vec<Diagnostic>, Diagnostic> {
    let supplied =
        usize::from(options.schema.is_some()) + usize::from(options.schema_json.is_some());
    if supplied > 1 || (options.auto && supplied > 0) || (!options.auto && supplied == 0) {
        return Err(Diagnostic::new(
            "validate",
            "choose one schema file, --schema-json, or --auto",
        )
        .with_code("nusage::validation::options"));
    }
    if options.passthrough && documents.len() > 1 {
        return Err(
            Diagnostic::new("validate", "--passthrough accepts one input stream")
                .with_code("nusage::validation::options"),
        );
    }
    let resolver = Resolver::new(if options.disabled {
        None
    } else {
        options.allow.as_deref()
    })?;
    let cwd = std::env::current_dir().map_err(|e| io_error(Path::new("PWD"), e))?;
    let inline_uri = schema::base(&cwd.join(".nusage-inline.schema.json"))?;
    let explicit = if options.disabled {
        None
    } else if let Some(path) = &options.schema {
        let text = std::fs::read(path).map_err(|e| io_error(path, e))?;
        let value = serde_json::from_slice(&text).map_err(|e| parse_error(path, e))?;
        Some(Arc::new(schema::compile(
            value,
            &schema::base(path)?,
            &resolver,
        )?))
    } else if let Some(text) = &options.schema_json {
        let value =
            serde_json::from_str(text).map_err(|e| parse_error(Path::new("--schema-json"), e))?;
        Some(Arc::new(schema::compile(value, &inline_uri, &resolver)?))
    } else {
        None
    };
    let stdin = [PathBuf::from("-")];
    let documents = if documents.is_empty() && (options.auto || options.passthrough) {
        &stdin[..]
    } else {
        documents
    };
    let mut findings = Vec::new();
    for path in documents {
        let source = options.source.as_deref().map(Path::new).unwrap_or(path);
        let base = if path == Path::new("-") {
            inline_uri.clone()
        } else {
            schema::base(path)?
        };
        let reader: Box<dyn BufRead> = if path == Path::new("-") {
            Box::new(BufReader::new(std::io::stdin()))
        } else {
            Box::new(BufReader::new(
                std::fs::File::open(path).map_err(|e| io_error(path, e))?,
            ))
        };
        let mut session = Session {
            resolver: &resolver,
            schema: explicit.clone(),
            cache: HashMap::new(),
            base,
            source,
            auto: options.auto && !options.disabled,
            first: true,
            record: 0,
        };
        if options.jsonl {
            let mut reader = reader;
            let mut line = 0;
            loop {
                let mut bytes = Vec::new();
                (&mut reader)
                    .take(MAX_RECORD_BYTES + 1)
                    .read_until(b'\n', &mut bytes)
                    .map_err(|e| io_error(source, e))?;
                if bytes.is_empty() {
                    break;
                }
                line += 1;
                if bytes.len() as u64 > MAX_RECORD_BYTES {
                    return Err(Diagnostic::new(source, "JSONL record exceeds 16 MiB")
                        .with_code("nusage::json::limit")
                        .at_line(line));
                }
                // Compatibility with Nu's --objects, while keeping physical line numbers.
                if bytes.iter().all(u8::is_ascii_whitespace) {
                    continue;
                }
                match session.check(&bytes, Some(line)) {
                    Ok(Some(value)) if options.passthrough => {
                        if options.nu {
                            write_packet(Ok(value), output)?;
                        } else {
                            output
                                .write_all(&bytes)
                                .and_then(|()| output.flush())
                                .map_err(|e| io_error(source, e))?;
                        }
                    }
                    Ok(_) => {}
                    Err(errors) => {
                        findings.extend(errors);
                        break;
                    }
                }
            }
        } else {
            let mut bytes = Vec::new();
            reader
                .take(u64::MAX)
                .read_to_end(&mut bytes)
                .map_err(|e| io_error(source, e))?;
            match session.check(&bytes, None) {
                Ok(Some(value)) if options.passthrough => {
                    if options.nu {
                        write_packet(Ok(value), output)?;
                    } else {
                        output.write_all(&bytes).map_err(|e| io_error(source, e))?;
                    }
                }
                Ok(_) => {}
                Err(errors) => findings.extend(errors),
            }
        }
    }
    Ok(findings)
}

struct Session<'a> {
    resolver: &'a Resolver,
    schema: Option<Arc<jsonschema::Validator>>,
    cache: HashMap<String, Option<Arc<jsonschema::Validator>>>,
    base: Url,
    source: &'a Path,
    auto: bool,
    first: bool,
    record: usize,
}

impl Session<'_> {
    /// None means a recognized inline JSONL header, which is not a data record.
    fn check(
        &mut self,
        bytes: &[u8],
        line: Option<usize>,
    ) -> Result<Option<Value>, Vec<Diagnostic>> {
        let value: Value = serde_json::from_slice(bytes).map_err(|e| {
            let mut d = parse_error(self.source, e);
            if let Some(line) = line {
                d.line = Some(line);
                d.location.record = Some(self.record + 1);
            }
            vec![d]
        })?;
        let first = std::mem::replace(&mut self.first, false);
        if self.auto && self.schema.is_none() && first && line.is_some() && schema::inline(&value) {
            self.schema = Some(Arc::new(
                schema::compile(value, &self.base, self.resolver)
                    .map_err(|d| vec![self.context(d, line)])?,
            ));
            return Ok(None);
        }
        self.record += 1;
        let validator = if let Some(validator) = &self.schema {
            Some(validator.clone())
        } else if self.auto {
            self.named(&value)
                .map_err(|d| vec![self.context(d, line)])?
        } else {
            None
        };
        if let Some(validator) = validator {
            let findings: Vec<_> = validator
                .iter_errors(&value)
                .take(MAX_FINDINGS)
                .map(|e| {
                    let mut d = Diagnostic::new(self.source, e.to_string())
                        .with_code("nusage::validation::invalid");
                    d.location.instance_path = Some(e.instance_path().to_string());
                    d.location.schema_path = Some(e.schema_path().to_string());
                    d.location.schema_uri = e.absolute_keyword_location().map(ToString::to_string);
                    self.context(d, line)
                })
                .collect();
            if !findings.is_empty() {
                return Err(findings);
            }
        }
        Ok(Some(value))
    }

    fn named(&mut self, value: &Value) -> Result<Option<Arc<jsonschema::Validator>>, Diagnostic> {
        let Some(name) = value.get("$schema").and_then(Value::as_str) else {
            return Ok(None);
        };
        if let Some(cached) = self.cache.get(name) {
            return Ok(cached.clone());
        }
        let validator = self
            .resolver
            .named(name, &self.base)?
            .map(|(uri, schema)| schema::compile(schema, &uri, self.resolver).map(Arc::new))
            .transpose()?;
        // Bound memory for an unbounded stream whose records name different schemas.
        if self.cache.len() >= 64 {
            self.cache.clear();
        }
        self.cache.insert(name.into(), validator.clone());
        Ok(validator)
    }

    fn context(&self, mut d: Diagnostic, line: Option<usize>) -> Diagnostic {
        if d.path != self.source {
            d.location.schema_uri = Some(d.path.display().to_string());
            d.path = self.source.into();
        }
        d.line = line;
        d.location.record = line.filter(|_| self.record > 0).map(|_| self.record);
        d
    }
}

fn parse_error(source: &Path, e: serde_json::Error) -> Diagnostic {
    let mut d = Diagnostic::new(source, e.to_string())
        .with_code("nusage::json::parse")
        .at_line(e.line());
    d.location.column = Some(e.column());
    d
}

fn io_error(source: &Path, e: std::io::Error) -> Diagnostic {
    let code = if e.kind() == std::io::ErrorKind::BrokenPipe {
        "nusage::io::broken_pipe"
    } else {
        "nusage::io"
    };
    Diagnostic::new(source, e.to_string()).with_code(code)
}

/// An internal Result envelope lets a generated module raise native Nu errors instead
/// of mistaking a failed external validator for EOF. Public pass-through remains raw.
pub fn write_packet(
    result: Result<Value, &[Diagnostic]>,
    output: &mut impl Write,
) -> Result<(), Diagnostic> {
    let bytes = serde_json::to_vec(&result).map_err(|e| {
        Diagnostic::new("stdout", e.to_string()).with_code("nusage::diagnostic::encode")
    })?;
    output
        .write_all(&bytes)
        .and_then(|()| output.write_all(b"\n"))
        .and_then(|()| output.flush())
        .map_err(|e| io_error(Path::new("stdout"), e))
}

/// The opt-out preserves bytes, including headers, without parsing or resolving schemas.
pub fn passthrough(
    documents: &[PathBuf],
    output: &mut impl Write,
) -> Result<Vec<Diagnostic>, Diagnostic> {
    if documents.len() > 1 {
        return Err(
            Diagnostic::new("validate", "--passthrough accepts one input stream")
                .with_code("nusage::validation::options"),
        );
    }
    let stdin = PathBuf::from("-");
    let path = documents.first().unwrap_or(&stdin);
    let mut reader: Box<dyn Read> = if path == Path::new("-") {
        Box::new(std::io::stdin())
    } else {
        Box::new(std::fs::File::open(path).map_err(|e| io_error(path, e))?)
    };
    std::io::copy(&mut reader, output).map_err(|e| io_error(path, e))?;
    Ok(Vec::new())
}
