//! The Nushell-facing view of an assembled usage spec.
//!
//! Every lossy decision between usage's vocabulary and a Nushell signature is made here, once,
//! in [`model`]: which usage argument becomes which parameter kind, what type it gets, how a
//! repeated or counted flag is spelled, the order of inherited flags, the `$usage` record
//! shape, which header nodes ride along as attributes, and what a completion provider may
//! look like. The result is plain data a target turns into a module; it names no Nushell
//! syntax and performs no I/O.

mod build;

pub use build::model;
pub use nusage_spec::{CommandPath, Diagnostic};

use std::path::PathBuf;

/// Every command of a script or tree, in the order a module should define them: each command
/// before its subcommands, and among siblings the completion providers first, so a parameter's
/// completer is defined before the parameter that names it.
#[derive(Debug, Clone, PartialEq)]
pub struct CommandTree {
    pub bin: String,
    pub commands: Vec<Command>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Command {
    pub path: CommandPath,
    /// usage `about`: the description.
    pub about: Option<String>,
    /// usage `long_about`: the extra description.
    pub about_long: Option<String>,
    /// Positional parameters, in declaration order.
    pub positionals: Vec<Param>,
    /// Flags: inherited globals outermost first, then the command's own, in declaration order.
    pub flags: Vec<Param>,
    /// The output type, from the annotation on the command's default `output` node.
    pub output: Option<NuType>,
    /// Header nodes carried verbatim, in header order.
    pub attributes: Vec<String>,
    /// The script that is the command's body.
    pub body: PathBuf,
    /// Whether another command names this one as a completion provider.
    pub is_provider: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Param {
    /// The name usage gave it: `target`, `dry-run`.
    pub usage_name: String,
    /// The Nushell variable, in `snake_case`: `dry_run`. Also the key in `$usage`.
    pub var: String,
    pub kind: ParamKind,
    /// The value's type. For `Rest` and `Repeated`, the element type.
    pub ty: NuType,
    /// The flag's long name as typed, without dashes: `dry-run`. `None` for positionals.
    pub long: Option<String>,
    pub short: Option<char>,
    pub completer: Option<Completer>,
    /// The declared default, typed by `ty`. `Count` is `0` and `Repeated` is `[]` unless usage
    /// declares otherwise.
    pub default: Option<Value>,
    /// usage `help`.
    pub doc: Option<String>,
    /// Whether the flag is inherited from an ancestor's `global=#true`.
    pub inherited: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ParamKind {
    /// `arg "<x>"`
    Required,
    /// `arg "[x]"`
    Optional,
    /// `arg "<x>..."`: a `...rest` parameter, a list in `$usage`.
    Rest,
    /// `flag "--x"`: a switch, `bool` in `$usage`.
    Switch,
    /// `flag "--x <v>"`
    Valued,
    /// `flag "-v" count=#true`: an `int`, since Nushell flags cannot repeat.
    Count,
    /// `flag "--x <v>" var=#true`: a `list`, since Nushell flags cannot repeat.
    Repeated,
}

/// A Nushell type as text. From a KDL annotation when there is one, else from usage's
/// conventions: `string`, `path` for `<file>` and `<dir>`, `bool`, `int`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NuType(pub String);

impl NuType {
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum Completer {
    /// Static `choices`.
    Inline(Vec<String>),
    /// `choices run="./x.nu"` resolved to the command that is that script.
    Command(CommandPath),
}

/// A default value, typed by the parameter it belongs to.
#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Null,
    Bool(bool),
    Int(i64),
    Float(f64),
    Str(String),
    List(Vec<Value>),
}
