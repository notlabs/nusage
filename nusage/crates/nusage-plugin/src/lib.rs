//! What a Nushell plugin of nusage's shares, so that a plugin is its commands and nothing
//! else. A plugin here stands for a command line: the hot path of a CLI whose wrappers a
//! module already carries, inside the interpreter rather than a process per call. So the
//! plugin's commands are the CLI's, by the same usage spec, and the spec is the one place the
//! interface is declared: [`commands`] reads the spec into nusage's command model, and
//! [`signature`] writes a command of it as the signature a plugin declares, named as the
//! module's wrappers are named, `<bin> <command>`, with the same parameters, types and help.
//! A plugin registered under the CLI's name shadows the external of the same words, and a
//! shell without the plugin runs the external where the plugin would answer.
//!
//! A plugin is the exception, not the pattern: one for nusage itself, and one for what only
//! Rust reaches, as a library without a command line. A binary or a service is a module,
//! and its hot path is nusage's plugin serving the helpers the module calls.
//!
//! A command is written as a [`Run`] over its evaluated [`Args`] and a [`Context`], and
//! [`Adapter`] registers it in the plugin.
//!
//! The rest is the boundary: [`value`] carries values across it as JSON and back, [`env()`]
//! reads the caller's environment, [`serve`] runs the plugin, and [`test`] runs it in
//! process for its tests. The Nushell crates a plugin needs are re-exported, so a plugin
//! depends on this crate and the version they are pinned to is pinned once.

pub use nu_plugin;
pub use nu_protocol;
pub use nusage_model::{Command, CommandTree, Param, ParamKind};
pub use nusage_spec::Diagnostic;

use nu_plugin::EngineInterface;
use nu_protocol::{LabeledError, Signature, SyntaxShape};

pub mod command;
pub mod value;

pub use command::{Adapter, Args, Context, Run};

/// The commands a usage spec declares, as the model every target of nusage's is handed.
/// `name` stands for the spec's file, and names the spec when it names itself in no `name`
/// node; the spec of a CLI built with usage-rs is its `to_kdl()`.
pub fn commands(name: &str, kdl: &str) -> Result<CommandTree, Diagnostic> {
    let assembled = nusage_spec::assemble_text(name, kdl)?;
    nusage_model::model(&assembled)
}

/// The command at `words` under the root, `[]` for the root itself.
pub fn command<'a>(tree: &'a CommandTree, words: &[&str]) -> Option<&'a Command> {
    tree.commands.iter().find(|command| {
        command
            .path
            .words()
            .iter()
            .map(String::as_str)
            .eq(words.iter().copied())
    })
}

/// The command's name as the plugin declares it: the binary's for the root, else the binary
/// and the command's path, as a module names a wrapper.
pub fn name(tree: &CommandTree, command: &Command) -> String {
    if command.path.is_root() {
        tree.bin.clone()
    } else {
        format!("{} {}", tree.bin, command.path)
    }
}

/// The command's signature: its positionals and flags with the types the spec declares,
/// read as Nushell's parser reads a parameter of that type, and its help. The input and
/// output types are the command's to add, since usage declares what a command prints and
/// not what a value of it is.
pub fn signature(tree: &CommandTree, command: &Command) -> Result<Signature, String> {
    let mut signature = Signature::build(name(tree, command));
    if let Some(about) = &command.about {
        signature = signature.description(about.clone());
    }
    if let Some(long) = &command.about_long {
        signature = signature.extra_description(long.clone());
    }
    for param in &command.positionals {
        let shape = shape(param)?;
        let doc = param.doc.clone().unwrap_or_default();
        signature = match param.kind {
            ParamKind::Required => signature.required(param.var.clone(), shape, doc),
            ParamKind::Optional => signature.optional(param.var.clone(), shape, doc),
            _ => signature.rest(&param.var, shape, doc),
        };
    }
    for param in &command.flags {
        let Some(long) = param.nushell_long() else {
            continue;
        };
        let doc = param.doc.clone().unwrap_or_default();
        signature = match param.kind {
            ParamKind::Switch => signature.switch(&long, doc, param.short),
            ParamKind::Count => signature.named(&long, SyntaxShape::Int, doc, param.short),
            ParamKind::Repeated => signature.named(
                &long,
                SyntaxShape::List(Box::new(shape(param)?)),
                doc,
                param.short,
            ),
            _ => signature.named(&long, shape(param)?, doc, param.short),
        };
        if let Some(negate) = &param.negate {
            signature = signature.switch(negate.clone(), format!("Turn `--{long}` off"), None);
        }
    }
    Ok(signature)
}

/// A type written as Nushell writes it, `table<name: string, size: filesize>`, read as the
/// checker holds a value to it: for the input and output types a command adds to its
/// signature.
pub fn nu_type(ty: &str) -> Result<nu_protocol::Type, String> {
    nusage_model::nu_type(&nusage_model::NuType(ty.to_string()))
}

/// What a command carries from its node of the spec: its name, its signature with the
/// input and output types the command adds, and its help. A command struct holds one and
/// answers the trait's questions from it, so the spec is the only place the interface is
/// written.
#[derive(Debug, Clone)]
pub struct Declared {
    pub name: String,
    pub signature: Signature,
    pub description: String,
    pub extra_description: String,
}

impl Declared {
    /// The command at `words` of the spec, with `io` as its input and output types; the
    /// output type is the one the spec's `output` declares when `io` names none.
    pub fn new(
        tree: &CommandTree,
        words: &[&str],
        io: Vec<(nu_protocol::Type, Option<nu_protocol::Type>)>,
    ) -> Result<Self, String> {
        let command =
            command(tree, words).ok_or_else(|| format!("the spec has no `{}`", words.join(" ")))?;
        let declared = match &command.output {
            Some(ty) => nu_type(ty.as_str())?,
            None => nu_protocol::Type::String,
        };
        let io = io
            .into_iter()
            .map(|(input, output)| (input, output.unwrap_or_else(|| declared.clone())))
            .collect();
        Ok(Declared {
            name: name(tree, command),
            signature: signature(tree, command)?.input_output_types(io),
            description: command.about.clone().unwrap_or_default(),
            extra_description: command.about_long.clone().unwrap_or_default(),
        })
    }
}

fn shape(param: &Param) -> Result<SyntaxShape, String> {
    nusage_model::nu_shape(&param.ty).map_err(|err| format!("`{}`: {err}", param.usage_name))
}

/// The first of `names` the caller's environment sets, as text.
pub fn env(engine: &EngineInterface, names: &[&str]) -> Result<Option<String>, LabeledError> {
    for name in names {
        if let Some(value) = engine.get_env_var(*name)? {
            return Ok(Some(value.coerce_into_string()?));
        }
    }
    Ok(None)
}

/// Run the plugin: what a plugin's `main` is.
pub fn serve<P: nu_plugin::Plugin + Sync + 'static>(plugin: &P) {
    nu_plugin::serve_plugin(plugin, nu_plugin::MsgPackSerializer);
}

/// The plugin in process, for its tests: a Nushell engine with the plugin registered, which
/// evaluates source against it.
#[cfg(feature = "test")]
// `ShellError` is Nushell's size, as every plugin's `Result` of it is.
#[allow(clippy::result_large_err)]
pub mod test {
    pub use nu_plugin_test_support::PluginTest;

    use nu_protocol::{ShellError, Span, Value};

    /// The engine with `plugin` registered under `name`, the name its binary would carry
    /// after `nu_plugin_`, in the process's working directory, which a command reads as the
    /// caller's.
    pub fn harness(
        name: &str,
        plugin: impl nu_plugin::Plugin + Send + 'static,
    ) -> Result<PluginTest, ShellError> {
        let mut test = PluginTest::new(name, plugin.into())?;
        let cwd = std::env::current_dir().unwrap_or_else(|_| std::env::temp_dir());
        test.engine_state_mut().add_env_var(
            "PWD".into(),
            Value::string(cwd.to_string_lossy(), Span::test_data()),
        );
        Ok(test)
    }

    /// `source` evaluated to one value.
    pub fn value(test: &mut PluginTest, source: &str) -> Result<Value, ShellError> {
        test.eval(source)?.into_value(Span::test_data())
    }
}
