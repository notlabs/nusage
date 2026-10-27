use std::fmt;
use std::path::{Path, PathBuf};

/// A problem in one script, named by file and, when known, the header line it came from.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub struct Diagnostic {
    pub path: PathBuf,
    /// 1-based line in the script, when the problem points at one.
    pub line: Option<usize>,
    pub message: String,
}

impl Diagnostic {
    pub fn new(path: impl AsRef<Path>, message: impl Into<String>) -> Self {
        Self {
            path: path.as_ref().to_path_buf(),
            line: None,
            message: message.into(),
        }
    }

    pub fn at_line(mut self, line: usize) -> Self {
        self.line = Some(line);
        self
    }
}

impl fmt::Display for Diagnostic {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self.line {
            Some(line) => write!(f, "{}:{}: {}", self.path.display(), line, self.message),
            None => write!(f, "{}: {}", self.path.display(), self.message),
        }
    }
}
