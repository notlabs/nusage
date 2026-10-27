use std::fmt;

use crate::Literal;
use crate::literal::{is_bare_word, quote};

/// A Nushell type as written in a signature: `int`, `list<string>`, `record<x: int>`.
///
/// Carried verbatim. Nushell's parser is the authority on whether it is a type; `nu-check`
/// on the generated file is where a wrong one surfaces.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Type(String);

impl Type {
    /// A non-empty type text with no surrounding whitespace.
    pub fn new(text: impl Into<String>) -> Result<Self, SyntaxError> {
        let text: String = text.into();
        let trimmed = text.trim();
        if trimmed.is_empty() {
            return Err(SyntaxError("a type cannot be empty".into()));
        }
        if trimmed.contains('\n') {
            return Err(SyntaxError(format!(
                "a type cannot span lines: {trimmed:?}"
            )));
        }
        Ok(Self(trimmed.to_string()))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// A parameter or variable name: letters, digits and `_`, not starting with a digit.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Ident(String);

impl Ident {
    pub fn new(text: impl Into<String>) -> Result<Self, SyntaxError> {
        let text: String = text.into();
        let valid = text
            .chars()
            .next()
            .is_some_and(|c| c.is_ascii_alphabetic() || c == '_')
            && text.chars().all(|c| c.is_ascii_alphanumeric() || c == '_');
        if !valid {
            return Err(SyntaxError(format!("not an identifier: {text:?}")));
        }
        Ok(Self(text))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// A flag's long name as typed by the user, without the dashes: `dry-run`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FlagName(String);

impl FlagName {
    pub fn new(text: impl Into<String>) -> Result<Self, SyntaxError> {
        let text: String = text.into();
        let valid = text.chars().next().is_some_and(|c| c.is_ascii_alphabetic())
            && text
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_');
        if !valid {
            return Err(SyntaxError(format!("not a flag name: {text:?}")));
        }
        Ok(Self(text))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// A command name, possibly several words: `main`, `db`, `db migrate`. Quoted when printed
/// if it needs to be.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CommandName(String);

impl CommandName {
    pub fn new(text: impl Into<String>) -> Result<Self, SyntaxError> {
        let text: String = text.into();
        if text.trim().is_empty() || text.starts_with('-') || text.contains('\n') {
            return Err(SyntaxError(format!("not a command name: {text:?}")));
        }
        Ok(Self(text))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }

    /// As it appears after `def` or as a completer reference.
    pub fn printed(&self) -> String {
        if is_bare_word(&self.0) {
            self.0.clone()
        } else {
            quote(&self.0)
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SyntaxError(pub String);

impl fmt::Display for SyntaxError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for SyntaxError {}

/// A module file: a preamble of statements, then definitions.
#[derive(Debug, Clone, PartialEq)]
pub struct Module {
    pub preamble: Vec<Stmt>,
    pub defs: Vec<Def>,
}

/// A custom command definition.
#[derive(Debug, Clone, PartialEq)]
pub struct Def {
    pub export: bool,
    /// Comment paragraphs above the definition: the first is the description, the rest the
    /// extra description. Each paragraph is one or more lines.
    pub doc: Vec<Vec<String>>,
    pub attrs: Vec<Attr>,
    pub name: CommandName,
    pub params: Params,
    /// `: input -> output`, when declared.
    pub io: Option<(Type, Type)>,
    pub body: Vec<Stmt>,
}

/// An attribute line above a `def`: `@name value`.
#[derive(Debug, Clone, PartialEq)]
pub struct Attr {
    pub name: FlagName,
    pub value: Literal,
}

/// The parameters of a signature, in the order Nushell requires: required positionals,
/// optional positionals, at most one rest, then flags. The constructor enforces it.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Params {
    items: Vec<Param>,
}

impl Params {
    pub fn new(items: Vec<Param>) -> Result<Self, SyntaxError> {
        let mut stage = 0;
        for item in &items {
            let this = match item {
                Param::Positional {
                    optional: false, ..
                } => 0,
                Param::Positional { optional: true, .. } => 1,
                Param::Rest { .. } => 2,
                Param::Flag { .. } => 3,
            };
            if this < stage {
                return Err(SyntaxError(
                    "parameters must be ordered: required, optional, rest, flags".into(),
                ));
            }
            if this == 2 && stage == 2 {
                return Err(SyntaxError("only one rest parameter is allowed".into()));
            }
            stage = this;
        }
        Ok(Self { items })
    }

    pub fn iter(&self) -> impl Iterator<Item = &Param> {
        self.items.iter()
    }

    pub fn is_empty(&self) -> bool {
        self.items.is_empty()
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum Param {
    Positional {
        name: Ident,
        ty: Type,
        optional: bool,
        completer: Option<Completer>,
        doc: Option<String>,
    },
    Rest {
        name: Ident,
        /// The element type.
        ty: Type,
        doc: Option<String>,
    },
    Flag {
        long: FlagName,
        short: Option<char>,
        /// `None` is a switch.
        ty: Option<Type>,
        default: Option<Literal>,
        completer: Option<Completer>,
        doc: Option<String>,
    },
}

/// What completes a parameter: an inline list, or a command.
#[derive(Debug, Clone, PartialEq)]
pub enum Completer {
    List(Vec<String>),
    Command(CommandName),
}

#[derive(Debug, Clone, PartialEq)]
pub enum Stmt {
    /// `alias NAME = TARGET`
    Alias {
        name: CommandName,
        target: CommandName,
    },
    /// `let NAME = EXPR`
    Let { name: Ident, value: Expr },
    /// `A | B | C`
    Pipeline(Vec<Expr>),
}

#[derive(Debug, Clone, PartialEq)]
pub enum Expr {
    /// `$name`, including `$in`.
    Var(Ident),
    Literal(Literal),
    /// `{k: v ...}`; the printer decides the layout.
    Record(Vec<(Ident, Expr)>),
    /// `[a b]`
    List(Vec<Expr>),
    /// `name arg arg`, arguments printed as given.
    Call {
        name: CommandName,
        args: Vec<Expr>,
    },
    /// A path argument, written bare when it can be.
    Path(String),
}
