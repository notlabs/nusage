use std::fmt;

use crate::Value;

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
/// if it needs to be. Whether Nushell accepts it as a definition (a parser keyword such as
/// `run` is not one) is for [`check_module`](crate::check_module) to say.
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
        word(&self.0)
    }
}

/// Text in a syntax position (a command name, an argument, a path, a completion word):
/// bare when Nushell reads it back as itself, else double-quoted. The rule is Nushell's own,
/// from `nu-utils`.
pub fn word(text: &str) -> String {
    if nu_utils::needs_quoting(text) {
        nu_utils::escape_quote_string(text)
    } else {
        text.to_string()
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
    pub items: Vec<Item>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Item {
    Def(Def),
    /// Nushell source written as given: a fixed block the generator ships, such as helper
    /// definitions, kept as Nushell rather than modelled.
    Verbatim(String),
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

/// An attribute line above a definition: `@name 'arg' 'arg'`, each argument a string,
/// single-quoted so it reads as written, or a raw string when it contains `'`.
#[derive(Debug, Clone, PartialEq)]
pub struct Attr {
    pub name: FlagName,
    pub args: Vec<String>,
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
                    optional: false,
                    default: None,
                    ..
                } => 0,
                Param::Positional { .. } => 1,
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
        /// A default makes the positional optional; it is written `name: type = value`.
        default: Option<Value>,
        completer: Option<Completer>,
        doc: Option<String>,
    },
    Rest {
        name: Ident,
        /// The element type.
        ty: Type,
        completer: Option<Completer>,
        doc: Option<String>,
    },
    Flag {
        long: FlagName,
        short: Option<char>,
        /// `None` is a switch.
        ty: Option<Type>,
        default: Option<Value>,
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
    /// `const NAME = EXPR`: evaluated where the parser reads it, as `path self` must be.
    Const { name: Ident, value: Expr },
    /// A definition inside a body, where only the rest of the body sees it.
    Def(Box<Def>),
    /// `A | B | C`
    Pipeline(Vec<Expr>),
}

#[derive(Debug, Clone, PartialEq)]
pub enum Expr {
    /// `$name`, including `$in`.
    Var(Ident),
    /// `$name.a.b`: a cell path into a variable, each part quoted when it needs to be.
    Cell { var: Ident, path: Vec<String> },
    /// Nushell as written: a literal the printer has no value for, such as `1kB` or a
    /// datetime, which it copies verbatim.
    Raw(String),
    /// A value written as NUON.
    Literal(Value),
    /// `{k: v ...}`, keys quoted when they need to be; the printer decides the layout.
    Record(Vec<(String, Expr)>),
    /// `[a b]`
    List(Vec<Expr>),
    /// `name arg arg`, arguments printed as given.
    Call { name: CommandName, args: Vec<Expr> },
    /// `^name arg arg`: an external command.
    External { name: String, args: Vec<Expr> },
    /// A string in argument position: bare when Nushell reads it back as itself, else quoted.
    Str(String),
    /// `(expr)`: a call or pipeline where a value is expected, such as a record field.
    Group(Box<Expr>),
    /// `lhs and rhs`, `lhs or rhs`.
    Infix {
        lhs: Box<Expr>,
        op: Infix,
        rhs: Box<Expr>,
    },
    /// `a | b | c` where an expression is expected: a `let` value, a branch, a closure body.
    Pipeline(Vec<Expr>),
    /// `if cond { then } else { otherwise }`
    If {
        cond: Box<Expr>,
        then: Box<Expr>,
        otherwise: Box<Expr>,
    },
    /// `{ body }`: a closure with no parameters, run on its input.
    Closure(Box<Expr>),
    /// `{|param| body }`: a closure with one parameter.
    ClosureWith { param: Ident, body: Box<Expr> },
    /// `...$x` or `...(expr)`: a list spread into a call's arguments.
    Spread(Box<Expr>),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Infix {
    And,
    Or,
    Eq,
    Add,
    Mul,
}

impl Infix {
    pub fn as_str(self) -> &'static str {
        match self {
            Infix::And => "and",
            Infix::Or => "or",
            Infix::Eq => "==",
            Infix::Add => "+",
            Infix::Mul => "*",
        }
    }
}
