//! The Nushell-facing view of an assembled usage spec.
//!
//! Every lossy decision between usage's vocabulary and a Nushell signature is made here, once,
//! in [`model`]: which usage argument becomes which parameter kind, what type it gets, how a
//! repeated or counted flag is spelled, the order of inherited flags, the `$usage` record
//! shape, which header nodes ride along as attributes, what a completion provider may look
//! like, and how a binary's outputs are selected and decoded. The result is plain data a
//! target turns into a module; it names no Nushell syntax and performs no I/O. It
//! serializes, so a tool can show what a target is handed: `nus model` prints it.

mod build;

pub use build::{Identifier, identifier, model, nu_shape, nu_type, value_from_text};
pub use nu_protocol::Value;
pub use nusage_spec::http::{Auth, Location};
pub use nusage_spec::{CommandPath, Diagnostic};
pub use nushell_schema::{Conversion, Fill, NuType, Shape};

use std::path::PathBuf;

/// Every command of a script, tree or spec, in the order a module should define them: each
/// command before its subcommands, and among siblings the completion providers first, so a
/// parameter's completer is defined before the parameter that names it.
#[derive(Debug, Clone, PartialEq, serde::Serialize)]
pub struct CommandTree {
    pub bin: String,
    pub commands: Vec<Command>,
    /// The service the commands call, when the spec has an HTTP mapping: then every
    /// command's execution is a [`Execution::Request`], or [`Execution::Service`] for the
    /// root.
    pub service: Option<Service>,
}

/// An HTTP service: where it is, and how it authenticates a call.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct Service {
    /// The base URL the requests' paths follow, when the mapping names one; the wrapper
    /// lets the environment say otherwise either way.
    pub base: Option<String>,
    /// What every call carries, in the mapping's order.
    pub auths: Vec<Auth>,
}

/// What a command's call sends, with the spec's parameters resolved to the wrapper's: a
/// request of the tree's [`Service`].
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct Request {
    /// The method, lower case.
    pub method: String,
    /// The path after the base, each path parameter as `{name}`.
    pub path: String,
    /// The parameters on the wire, in the mapping's order.
    pub params: Vec<Wire>,
    pub body: Option<Body>,
}

/// A parameter on the wire and the variable that carries it.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct Wire {
    pub location: Location,
    /// The name on the wire.
    pub name: String,
    /// The wrapper's variable, as [`Param::var`] names it.
    pub var: String,
}

/// The request body, which the wrapper takes as its input.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct Body {
    /// The media type it is sent as.
    pub media: String,
    /// The input type its schema declares, the record of the properties the schema requires
    /// (a caller passes what it has, and Nushell holds a record to the fields its type
    /// names), or `None` without a schema.
    pub ty: Option<NuType>,
    /// Whether the call must send one; otherwise the input may be nothing.
    pub required: bool,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize)]
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
    /// what its structured output decodes to, `string` for a text command.
    pub output: Option<NuType>,
    /// A binary command's structured output, which its wrapper selects and decodes; `None`
    /// for a script or a text command.
    pub structured: Option<Structured>,
    /// usage `clause`: the name of the command's repeatable group of flags and positionals,
    /// whose members are the parameters marked [`Param::clause`].
    pub clause: Option<String>,
    /// Header nodes carried verbatim, in header order.
    pub attributes: Vec<String>,
    pub execution: Execution,
    /// Whether another command names this one as a completion provider.
    pub is_provider: bool,
}

/// What runs when the command is called.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Execution {
    /// `run` this script with `$usage` and `$in`.
    Script(PathBuf),
    /// The binary named by the spec, from `PATH`.
    External,
    /// A request of the tree's [`Service`], whose response is the command's output.
    Request(Request),
    /// The service itself, as the root of a spec with an HTTP mapping: nothing is called,
    /// and the wrapper says where the service is.
    Service,
}

/// The one output a binary command's wrapper asks for and decodes, as a Nushell command
/// returns data and the binary itself, `^tool`, returns text: among the outputs that have a
/// decoder, the default one, else the first `json` one a selector can ask for, else the first
/// that can be asked for. The selector flags are the wrapper's, not the caller's.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct Structured {
    pub name: String,
    /// The JSON Schema the output declares, as text, when it declares one rather than an
    /// annotation: what the raw output is held to when the module's decoding fails.
    pub schema: Option<String>,
    /// The words that ask for it, right after the command's: `--json`, or `--format json`;
    /// none when it is the default.
    pub args: Vec<String>,
    pub framing: Framing,
    /// What turns the output's text into a value, before the conversions.
    pub decoder: Decoder,
    /// The type, from the output's JSON Schema or its annotation, when it has one.
    pub ty: Option<NuType>,
    /// Properties the schema does not require: a record JSON leaves one out of gets it as
    /// `null`, so the field is there to read, typed `oneof<T, nothing>`.
    pub fills: Vec<Fill>,
    /// What JSON cannot carry and the schema or annotation declares: each is converted
    /// after decoding, in this order.
    pub conversions: Vec<Conversion>,
}

/// usage's `framing`: the stream contract of an output.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Framing {
    /// One document, read to its end; usage's default.
    Text,
    /// One JSON document.
    Json,
    /// One JSON document per line.
    Jsonl,
}

/// How a wrapper decodes an output. An output has a decoder when its `media_type` names a
/// format Nushell reads, when its framing is `json` or `jsonl`, or when its declaration
/// carries a `nusage-decode` node; an output with none is text, which the wrapper returns as it is.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Decoder {
    /// `from <format>`: Nushell's reader for the media type, `json` for the JSON framings
    /// when no media type says otherwise, with `--objects` for one document per line.
    From { format: String, objects: bool },
    /// The pipeline the output's `nusage-decode` node states, as written: what no reader covers,
    /// such as `lines | parse "{name} {size}"` or an external converter followed by
    /// `from json`.
    Pipeline(String),
}

impl Decoder {
    /// Whether this is `from json`, the one reader a JSON Schema describes the input of.
    pub fn is_json(&self) -> bool {
        matches!(self, Decoder::From { format, .. } if format == "json")
    }
}

/// Nushell's `from` reader for an IANA media type, when it has one: `text/csv` reads with
/// `from csv`. Parameters after `;` and case are ignored; JSON Lines types read as `json`,
/// which the framing then takes line by line. Not `application/json-seq`: RFC 7464 puts a
/// record separator before each document, which `from json --objects` does not read.
pub fn reader_for(media_type: &str) -> Option<&'static str> {
    let essence = media_type
        .split(';')
        .next()
        .unwrap_or_default()
        .trim()
        .to_ascii_lowercase();
    Some(match essence.as_str() {
        "application/json"
        | "application/jsonl"
        | "application/x-ndjson"
        | "application/jsonlines"
        | "application/x-jsonlines" => "json",
        "text/csv" => "csv",
        "text/tab-separated-values" | "text/tsv" => "tsv",
        "application/yaml" | "application/x-yaml" | "text/yaml" | "text/x-yaml" => "yaml",
        "application/toml" | "text/toml" => "toml",
        "application/xml" | "text/xml" => "xml",
        "application/nuon" | "text/nuon" => "nuon",
        _ => return None,
    })
}

#[derive(Debug, Clone, PartialEq, serde::Serialize)]
pub struct Param {
    /// The name usage gave it: `target`, `dry-run`.
    pub usage_name: String,
    /// The key in `$usage`: the usage name in `snake_case`, `dry_run`.
    pub key: String,
    /// The Nushell variable: the key, with a trailing `_` when Nushell reserves the name for
    /// itself (`env_` for `--env`), since no parameter can be called `env`.
    pub var: String,
    pub kind: ParamKind,
    /// The value's type. For `Rest` and `Repeated`, the element type.
    pub ty: NuType,
    /// The flag's long name as the binary spells it, without dashes: `dry-run`. `None` for
    /// positionals. The Nushell spelling is [`Param::nushell_long`].
    pub long: Option<String>,
    pub short: Option<char>,
    pub completer: Option<Completer>,
    /// The declared default as a Nushell value of type `ty`. `Count` is `0` and `Repeated` is
    /// `[]` unless usage declares otherwise; a switch has one only when usage declares it. A
    /// binary applies its own defaults, so an extern never writes them. Serialized as NUON.
    #[serde(serialize_with = "as_nuon")]
    pub default: Option<Value>,
    /// usage `negate`: the long name, without dashes, of the switch that turns this one off.
    pub negate: Option<String>,
    /// usage `help`.
    pub doc: Option<String>,
    /// Whether the flag is inherited from an ancestor's `global=#true`.
    pub inherited: bool,
    /// Whether it belongs to the command's `clause`, usage's repeatable group of flags and
    /// positionals (`mise use --postinstall X node@24 --postinstall Y python@3`). A `def` is
    /// flat: a clause's positionals are the command's, its flags go before every instance
    /// on the argv, and the `$usage` of a script collects a repeated positional across the
    /// instances and takes a flag from the first.
    pub clause: bool,
}

/// A default as its NUON text, which says the value as a signature writes it.
fn as_nuon<S: serde::Serializer>(value: &Option<Value>, serializer: S) -> Result<S::Ok, S::Error> {
    match value {
        Some(value) => serializer.serialize_some(&nusage_nu::nuon(value)),
        None => serializer.serialize_none(),
    }
}

impl Param {
    /// The flag's long name as Nushell spells it: the binary's, with a trailing `_` when the
    /// variable needed one (`--env_` for `--env`); the short form is untouched either way.
    pub fn nushell_long(&self) -> Option<String> {
        let long = self.long.as_ref()?;
        Some(if self.var != self.key {
            format!("{long}_")
        } else {
            long.clone()
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "snake_case")]
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

#[derive(Debug, Clone, PartialEq, serde::Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Completer {
    /// Static `choices`.
    Inline(Vec<String>),
    /// `choices run="./x.nu"` resolved to the command that is that script.
    Command(CommandPath),
    /// usage's own completer, run against the spec with the words typed so far: what a
    /// `complete` node, a `choices run=` or a `type=` asks for, its commands run and its
    /// templates rendered by usage. For a binary; a script's choices are a sibling provider.
    Spec,
}

#[cfg(test)]
mod tests {
    use super::reader_for;

    #[test]
    fn readers_follow_the_media_type() {
        assert_eq!(reader_for("text/csv"), Some("csv"));
        assert_eq!(reader_for("Application/JSON; charset=utf-8"), Some("json"));
        assert_eq!(reader_for("application/x-ndjson"), Some("json"));
        assert_eq!(reader_for("application/yaml"), Some("yaml"));
        assert_eq!(reader_for("text/plain"), None);
        assert_eq!(reader_for("application/json-seq"), None);
        assert_eq!(reader_for("image/png"), None);
    }
}
