//! The shim target: one `export def` per command whose body builds `$usage` and `run`s the
//! script, after defining the shadows of the scripts that script calls ([`crate::calls`]):
//! inside the body, since a call's path is its script's, and `run` reads a script's calls
//! where it first parses it. The module stands on its own in any Nushell: a called script
//! runs in the caller's, as the one the module wraps does.

use std::path::Path;

use nusage_model::{Command, CommandTree, Execution};
use nusage_nu::{CommandName, Def, Item, Module, Params, SyntaxError, Type};

use nusage_spec::Texts;

use crate::calls::{self, Paths};
use crate::common::{Target, attr_usage_alias, doc_of, nu_params, usage_attrs};

/// The module for a command tree, with `run` paths relative to `base`.
pub fn module(tree: &CommandTree, base: &Path) -> Result<Module, SyntaxError> {
    let mut module = Module {
        preamble: vec![attr_usage_alias()?],
        items: tree
            .commands
            .iter()
            .map(|command| def(command, base).map(Item::Def))
            .collect::<Result<Vec<_>, _>>()?,
    };
    // The scripts' calls of programs build their argv with the helpers binary modules carry.
    let helpers = crate::binary::helpers_for(&nusage_nu::print(&module));
    module.items.splice(0..0, helpers);
    Ok(module)
}

fn def(command: &Command, base: &Path) -> Result<Def, SyntaxError> {
    if !matches!(command.execution, Execution::Script(_)) {
        return Err(SyntaxError(format!(
            "`{}` is an external command; the shim target only wraps scripts",
            command.path
        )));
    }
    let name = if command.path.is_root() {
        "main".to_string()
    } else {
        command.path.to_string()
    };
    let params = command
        .positionals
        .iter()
        .chain(command.flags.iter())
        .map(|param| nu_params(param, Target::Script))
        .collect::<Result<Vec<_>, _>>()?
        .concat();
    let io = match &command.output {
        Some(output) => Some((Type::new("nothing")?, Type::new(output.as_str())?)),
        None => None,
    };
    let body = calls::script_body(command, Paths::From(base), &Texts::new())
        .map_err(|err| SyntaxError(err.to_string()))?;
    Ok(Def {
        export: true,
        doc: doc_of(command),
        attrs: usage_attrs(command)?,
        name: CommandName::new(name)?,
        params: Params::new(params)?,
        io,
        body,
    })
}
