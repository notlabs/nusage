use std::fmt;
use std::path::{Path, PathBuf};

/// A problem reported by the interpreter, spec commands, or output validator.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error, serde::Serialize)]
pub struct Diagnostic {
    /// Stable identifier; renderers and callers need not interpret the message.
    pub code: &'static str,
    pub path: PathBuf,
    /// 1-based physical line in the source, when the problem points at one.
    pub line: Option<usize>,
    pub message: String,
    #[serde(flatten)]
    pub location: Box<DiagnosticLocation>,
}

/// Optional runtime locations, boxed to keep ordinary spec errors small.
#[derive(Debug, Default, Clone, PartialEq, Eq, serde::Serialize)]
pub struct DiagnosticLocation {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub column: Option<usize>,
    /// 1-based data record, excluding a consumed JSONL schema header.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub record: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub instance_path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub schema_path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub schema_uri: Option<String>,
}

impl Diagnostic {
    pub fn new(path: impl AsRef<Path>, message: impl Into<String>) -> Self {
        Self {
            code: "nusage::spec",
            path: path.as_ref().to_path_buf(),
            line: None,
            location: Box::default(),
            message: message.into(),
        }
    }

    pub fn with_code(mut self, code: &'static str) -> Self {
        self.code = code;
        self
    }

    pub fn at_line(mut self, line: usize) -> Self {
        self.line = Some(line);
        self
    }
}

impl fmt::Display for Diagnostic {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}:", self.path.display())?;
        if let Some(line) = self.line {
            write!(f, "{line}:")?;
        }
        if let Some(column) = self.location.column {
            write!(f, "{column}:")?;
        }
        if let Some(path) = &self.location.instance_path {
            write!(f, "{path}:")?;
        }
        write!(f, " {}", self.message)
    }
}
