//! The Nushell-facing view of an assembled usage spec.
//!
//! Every lossy decision between usage's vocabulary and a Nushell signature is made here, once,
//! in [`model`]: which usage argument becomes which parameter kind, what type it gets, how a
//! repeated or counted flag is spelled, the order of inherited flags, the `$usage` record
//! shape, which header nodes ride along as attributes, what a completion provider may look
//! like, and how a binary's outputs are selected and decoded. The result is plain data a
//! target turns into a module; it names no Nushell syntax and performs no I/O.

mod build;

pub use build::{model, value_from_text};
pub use nu_protocol::Value;
pub use nusage_spec::{CommandPath, Diagnostic};

use std::path::PathBuf;

/// Every command of a script, tree or spec, in the order a module should define them: each
/// command before its subcommands, and among siblings the completion providers first, so a
/// parameter's completer is defined before the parameter that names it.
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
    /// The output type: for a script, the annotation on its default `output`; for a binary,
    /// the union of what its outputs decode to, when every one is known.
    pub output: Option<NuType>,
    /// How a binary's outputs are selected and decoded; `None` for a script.
    pub decoding: Option<Decoding>,
    /// Header nodes carried verbatim, in header order.
    pub attributes: Vec<String>,
    pub execution: Execution,
    /// Whether another command names this one as a completion provider.
    pub is_provider: bool,
}

/// What runs when the command is called.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Execution {
    /// `run` this script with `$usage` and `$in`.
    Script(PathBuf),
    /// The binary named by the spec, from `PATH`.
    External,
}

/// A binary's outputs as usage resolves them for a command, and how a call says which one it
/// wants: the selector flags are the command's own, so the wrapper reads them and decodes
/// what the binary printed accordingly.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Decoding {
    /// Switches that each select one output, `output "x" select="--json"`: the flag's
    /// variable and the output's name, in declaration order.
    pub switches: Vec<(String, String)>,
    /// The flag whose value names the output, `select "--format"`: its variable.
    pub value_selector: Option<String>,
    /// The output produced when no selector is given.
    pub default: Option<String>,
    /// Every output the command can produce, in usage's order.
    pub outputs: Vec<Output>,
}

/// One usage `output`: text unless framed, and when framed, what it decodes to.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Output {
    pub name: String,
    /// `None` is text, passed through as it came.
    pub framing: Option<Framing>,
    /// The annotation, when the output has one.
    pub ty: Option<NuType>,
    /// What JSON cannot carry and the annotation declares: each is converted after decoding,
    /// in this order.
    pub conversions: Vec<Conversion>,
}

/// `into <ty> <path>`: a value JSON delivers as text or a number, converted to the declared
/// type at a cell path (empty for the whole value).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Conversion {
    pub path: Vec<String>,
    /// `datetime`, `duration`, `filesize` or `binary`.
    pub ty: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Framing {
    /// One JSON document.
    Json,
    /// One JSON document per line.
    Jsonl,
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
    /// The declared default as a Nushell value of type `ty`. `Count` is `0` and `Repeated` is
    /// `[]` unless usage declares otherwise; a switch has one only when usage declares it. A
    /// binary applies its own defaults, so an extern never writes them.
    pub default: Option<Value>,
    /// usage `negate`: the long name, without dashes, of the switch that turns this one off.
    pub negate: Option<String>,
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
    /// `flag "-v" count=#true`: an `int` in `$usage`, since a `def`'s flags cannot repeat. An
    /// extern keeps the switch, since an external accepts `-vv`.
    Count,
    /// `flag "--x <v>" var=#true`: a `list` in `$usage`, since a `def`'s flags cannot repeat.
    /// An extern keeps the single value, since an external accepts `--x a --x b`.
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
    /// A `complete "name" run="..."` or `choices run="..."` shell command: one value per line,
    /// `value:description` lines when `descriptions` is set.
    Shell {
        /// A name unique within the spec, for the helper that runs it: the completer's name,
        /// prefixed by the command path when the `complete` node is the command's or the
        /// argument's own rather than the spec's.
        name: String,
        run: String,
        descriptions: bool,
    },
}
