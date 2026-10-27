use std::collections::{BTreeMap, BTreeSet};

use nusage_spec::{Assembled, CommandPath, Diagnostic, Header, HeaderNode, Source};
use usage::{SpecArg, SpecCommand, SpecComplete, SpecFlag, SpecOutput};

use crate::{
    Command, CommandTree, Completer, Execution, Framing, NuType, Param, ParamKind, Structured,
    Value,
};

/// Header nodes that have a native place in the module and so do not become attributes.
const NATIVE_NODES: &[&str] = &[
    "name",
    "bin",
    "about",
    "long_about",
    "about_long",
    "about_md",
];

/// Build the command model from an assembled spec.
pub fn model(assembled: &Assembled) -> Result<CommandTree, Diagnostic> {
    let providers: BTreeSet<&CommandPath> =
        assembled.providers.iter().map(|p| &p.provider).collect();
    let completers: BTreeMap<(&CommandPath, &str), &CommandPath> = assembled
        .providers
        .iter()
        .map(|p| ((&p.consumer, p.param.as_str()), &p.provider))
        .collect();
    let ctx = Context {
        assembled,
        providers,
        completers,
    };
    let mut commands = Vec::new();
    ctx.visit(
        &assembled.spec.cmd,
        CommandPath::root(),
        &[],
        &[],
        &mut commands,
    )?;
    Ok(CommandTree {
        bin: assembled.spec.bin.clone(),
        commands,
    })
}

struct Context<'a> {
    assembled: &'a Assembled,
    providers: BTreeSet<&'a CommandPath>,
    completers: BTreeMap<(&'a CommandPath, &'a str), &'a CommandPath>,
}

/// A completer and, when usage declared one, the `complete type=` it carries.
type Found = Option<(Completer, Option<String>)>;

impl Context<'_> {
    fn visit(
        &self,
        cmd: &SpecCommand,
        path: CommandPath,
        inherited: &[Param],
        inherited_outputs: &[SpecOutput],
        out: &mut Vec<Command>,
    ) -> Result<(), Diagnostic> {
        let header = self
            .assembled
            .headers
            .get(&path)
            .expect("assemble records a header for every command");
        let execution = match &self.assembled.source {
            Source::Scripts { .. } => Execution::Script(
                self.assembled
                    .body(&path)
                    .expect("assemble records a body for every script command")
                    .to_path_buf(),
            ),
            Source::Binary => Execution::External,
        };
        let is_provider = self.providers.contains(&path);

        let positionals = cmd
            .args
            .iter()
            .map(|arg| self.positional(arg, cmd, header, &path))
            .collect::<Result<Vec<_>, _>>()?;
        let own_flags = cmd
            .flags
            .iter()
            .map(|flag| self.flag_param(flag, cmd, header, &path))
            .collect::<Result<Vec<_>, _>>()?;

        // The outputs this command can produce: its own, else the ones declared above it.
        let outputs: &[SpecOutput] = if cmd.outputs.is_empty() {
            inherited_outputs
        } else {
            &cmd.outputs
        };
        let structured = match execution {
            Execution::External => structured_output(outputs, cmd.select.as_deref()),
            Execution::Script(_) => None,
        };
        // A script's value is what its default output describes; a binary's is the structured
        // output Nushell decodes.
        let output = match &structured {
            Some((_, name)) => output_type(header, Some(name)),
            None => output_type(header, None),
        };
        let structured = structured.map(|(structured, _)| structured);

        if is_provider {
            if !positionals.is_empty() || !own_flags.is_empty() {
                let line = header
                    .nodes
                    .iter()
                    .find(|node| matches!(node.name.as_str(), "arg" | "flag"))
                    .map(|node| node.line)
                    .unwrap_or(1);
                return Err(Diagnostic::new(
                    &header.path,
                    "a completion provider cannot declare parameters: Nushell binds only the \
                     completion token when it calls a completer, so any flag or argument would \
                     be unbound",
                )
                .at_line(line));
            }
            match &output {
                Some(ty) if ty.as_str().starts_with("list<") => {}
                _ => {
                    return Err(Diagnostic::new(
                        &header.path,
                        "a completion provider must declare its output as a list, for example \
                         `output (\"list<string>\")\"nuon\" default=#true`",
                    ));
                }
            }
        }

        let flags: Vec<Param> = if is_provider {
            Vec::new()
        } else {
            inherited
                .iter()
                .cloned()
                .chain(own_flags.iter().cloned())
                .collect()
        };
        let attributes = header
            .nodes
            .iter()
            .filter(|node| !NATIVE_NODES.contains(&node.name.as_str()))
            .map(|node| node.text.clone())
            .collect();

        out.push(Command {
            path: path.clone(),
            about: header.about.clone(),
            about_long: header.about_long.clone(),
            positionals,
            flags,
            output,
            structured,
            attributes,
            execution,
            is_provider,
        });

        // What children inherit: this command's inherited flags, then its own `global=#true`.
        let own_globals = own_flags.iter().filter(|param| {
            cmd.flags
                .iter()
                .any(|flag| flag.global && flag.name == param.usage_name)
        });
        let passed_down: Vec<Param> = inherited
            .iter()
            .cloned()
            .chain(own_globals.cloned().map(|mut param| {
                param.inherited = true;
                param
            }))
            .collect();
        // Top-level `output` nodes of a spec file are CLI-wide; usage keeps them on the spec.
        let child_outputs: Vec<SpecOutput> = if !cmd.outputs.is_empty() {
            cmd.outputs.clone()
        } else if path.is_root() {
            self.assembled.spec.outputs.clone()
        } else {
            inherited_outputs.to_vec()
        };

        let (first, rest): (Vec<_>, Vec<_>) = cmd
            .subcommands
            .iter()
            .partition(|(name, _)| self.providers.contains(&path.child(name)));
        for (name, sub) in first.into_iter().chain(rest) {
            self.visit(sub, path.child(name), &passed_down, &child_outputs, out)?;
        }
        Ok(())
    }

    fn positional(
        &self,
        arg: &SpecArg,
        cmd: &SpecCommand,
        header: &Header,
        path: &CommandPath,
    ) -> Result<Param, Diagnostic> {
        let node = arg_node(header, arg);
        let found = self.completer_for(arg, cmd, path, &arg.name, header)?;
        let ty = NuType(
            node.and_then(|n| n.value_type())
                .map(str::to_string)
                .unwrap_or_else(|| conventional_type(arg, &found)),
        );
        let kind = if arg.var {
            ParamKind::Rest
        } else if arg.required {
            ParamKind::Required
        } else {
            ParamKind::Optional
        };
        let default = match kind {
            ParamKind::Rest => None,
            _ => arg.default.first().map(|text| typed_value(text, &ty)),
        };
        Ok(Param {
            usage_name: arg.name.clone(),
            var: snake(&arg.name),
            kind,
            ty,
            long: None,
            short: None,
            completer: found.map(|(completer, _)| completer),
            default,
            doc: arg.help.clone(),
            inherited: false,
        })
    }

    fn flag_param(
        &self,
        flag: &SpecFlag,
        cmd: &SpecCommand,
        header: &Header,
        path: &CommandPath,
    ) -> Result<Param, Diagnostic> {
        let node = flag_node(header, flag);
        let long = flag.long.first().cloned();
        let short = flag.short.first().copied();
        let (kind, ty, default, completer) = match (&flag.arg, flag.count, flag.var) {
            (None, true, _) => (
                ParamKind::Count,
                NuType("int".into()),
                Some(Value::Int(0)),
                None,
            ),
            (None, false, _) => (ParamKind::Switch, NuType("bool".into()), None, None),
            (Some(arg), _, repeated) => {
                let found = self.completer_for(arg, cmd, path, &flag.name, header)?;
                let ty = NuType(
                    node.and_then(|n| n.value_type())
                        .map(str::to_string)
                        .unwrap_or_else(|| conventional_type(arg, &found)),
                );
                let completer = found.map(|(completer, _)| completer);
                if repeated {
                    let defaults = flag
                        .default
                        .iter()
                        .map(|text| typed_value(text, &ty))
                        .collect();
                    (
                        ParamKind::Repeated,
                        ty,
                        Some(Value::List(defaults)),
                        completer,
                    )
                } else {
                    let default = flag.default.first().map(|text| typed_value(text, &ty));
                    (ParamKind::Valued, ty, default, completer)
                }
            }
        };
        Ok(Param {
            usage_name: flag.name.clone(),
            var: snake(&flag.name),
            kind,
            ty,
            long,
            short,
            completer,
            default,
            doc: flag.help.clone(),
            inherited: false,
        })
    }

    /// The completer for an argument. In order: a provider in the tree, static `choices`,
    /// `choices run=`, then a `complete` node on the arg, on the command, or at the top level.
    fn completer_for(
        &self,
        arg: &SpecArg,
        cmd: &SpecCommand,
        path: &CommandPath,
        param: &str,
        header: &Header,
    ) -> Result<Found, Diagnostic> {
        if let Some(provider) = self.completers.get(&(path, param)) {
            return Ok(Some((Completer::Command((*provider).clone()), None)));
        }
        if let Some(choices) = &arg.choices {
            if let Some(run) = &choices.run {
                return match self.assembled.source {
                    Source::Binary => Ok(Some((
                        Completer::Shell {
                            name: helper_name(path, param),
                            run: run.clone(),
                            descriptions: false,
                        },
                        None,
                    ))),
                    Source::Scripts { .. } => Err(Diagnostic::new(
                        &header.path,
                        format!(
                            "`choices run=\"{run}\"` is not a script in this tree; a script's \
                             choices come from a sibling `.nu` provider"
                        ),
                    )),
                };
            }
            if choices.env().is_some() {
                return Err(Diagnostic::new(
                    &header.path,
                    "`choices env=` is not supported yet",
                ));
            }
            if !choices.choices.is_empty() {
                return Ok(Some((Completer::Inline(choices.choices.clone()), None)));
            }
        }
        let named = arg
            .complete
            .as_ref()
            .or_else(|| cmd.complete.get(&arg.name))
            .or_else(|| self.assembled.spec.complete.get(&arg.name));
        match named {
            Some(complete) => shell_completer(complete, &arg.name, header, &self.assembled.source),
            None => Ok(None),
        }
    }
}

/// The name of the helper that runs a `choices run=` for one parameter.
fn helper_name(path: &CommandPath, param: &str) -> String {
    if path.is_root() {
        param.to_string()
    } else {
        format!("{path} {param}")
    }
}

fn shell_completer(
    complete: &SpecComplete,
    name: &str,
    header: &Header,
    source: &Source,
) -> Result<Found, Diagnostic> {
    let ty = complete.type_.clone();
    let Some(run) = &complete.run else {
        // Nothing to run, but a `type=` still says what the value is.
        return Ok(ty.map(|ty| (Completer::Inline(Vec::new()), Some(ty))));
    };
    if let Source::Scripts { .. } = source {
        return Err(Diagnostic::new(
            &header.path,
            format!(
                "`complete \"{name}\" run=...` is not supported for scripts; name a sibling \
                 `.nu` provider with `choices run=` instead"
            ),
        ));
    }
    Ok(Some((
        Completer::Shell {
            name: name.to_string(),
            run: run.clone(),
            descriptions: complete.descriptions,
        },
        ty,
    )))
}

fn snake(name: &str) -> String {
    name.replace('-', "_")
}

/// usage's conventions: `<file>` and `<dir>` complete as paths, as does an argument whose
/// `complete type=` says so.
fn conventional_type(arg: &SpecArg, found: &Found) -> String {
    let typed = found
        .as_ref()
        .and_then(|(_, ty)| ty.as_deref())
        .map(|ty| ty.split(':').next().unwrap_or(ty));
    match (arg.name.as_str(), typed) {
        (_, Some("file" | "path" | "dir")) => "path",
        ("file" | "dir" | "path", _) => "path",
        _ => "string",
    }
    .to_string()
}

fn arg_node<'a>(header: &'a Header, arg: &SpecArg) -> Option<&'a HeaderNode> {
    header.nodes.iter().find(|node| {
        node.name == "arg"
            && node
                .first
                .as_deref()
                .map(|first| placeholder_name(first) == arg.name)
                .unwrap_or(false)
    })
}

/// `<file>...`, `[file]`, `<-- file>`, `file` → `file`.
fn placeholder_name(first: &str) -> String {
    first
        .trim()
        .trim_end_matches("...")
        .trim_matches(|c| c == '<' || c == '>' || c == '[' || c == ']')
        .trim_start_matches("-- ")
        .trim()
        .to_string()
}

fn flag_node<'a>(header: &'a Header, flag: &SpecFlag) -> Option<&'a HeaderNode> {
    header.nodes.iter().find(|node| {
        node.name == "flag"
            && node.first.as_deref().is_some_and(|first| {
                first.split_whitespace().any(|word| {
                    flag.long.iter().any(|long| word == format!("--{long}"))
                        || flag.short.iter().any(|short| word == format!("-{short}"))
                })
            })
    })
}

/// The annotation on an `output` node: the one named, else the default, else the only one.
fn output_type(header: &Header, name: Option<&str>) -> Option<NuType> {
    let outputs: Vec<&HeaderNode> = header
        .nodes
        .iter()
        .filter(|node| node.name == "output")
        .collect();
    let chosen = match name {
        Some(name) => outputs
            .iter()
            .find(|node| node.first.as_deref() == Some(name))?,
        None => outputs
            .iter()
            .find(|node| node.text.contains("default=#true"))
            .or_else(|| (outputs.len() == 1).then(|| &outputs[0]))?,
    };
    chosen.value_type().map(|ty| NuType(ty.to_string()))
}

/// The structured output a binary can be asked for, and its usage name: the first `json`
/// output, else the first `jsonl` one, with the arguments that select it. A `select` on the
/// output is a boolean flag (`--json`); a `select` on the command names a value flag
/// (`--format=json`). With neither, the output must be the default or the only one, or there
/// is no way to ask for it.
fn structured_output(
    outputs: &[SpecOutput],
    command_select: Option<&str>,
) -> Option<(Structured, String)> {
    let framed = |output: &&SpecOutput| {
        matches!(output.framing, usage::Framing::Json | usage::Framing::Jsonl)
    };
    let chosen = outputs
        .iter()
        .filter(framed)
        .find(|output| output.framing == usage::Framing::Json)
        .or_else(|| outputs.iter().find(framed))?;
    let framing = match chosen.framing {
        usage::Framing::Json => Framing::Json,
        usage::Framing::Jsonl => Framing::Jsonl,
        _ => return None,
    };
    let args = if let Some(flag) = &chosen.select {
        vec![flag.clone()]
    } else if let Some(flag) = command_select {
        vec![format!("{flag}={}", chosen.name)]
    } else if chosen.default || outputs.len() == 1 {
        Vec::new()
    } else {
        return None;
    };
    Some((Structured { args, framing }, chosen.name.clone()))
}

/// usage keeps every default as text; the parameter's type says how Nushell should read it.
fn typed_value(text: &str, ty: &NuType) -> Value {
    match ty.as_str() {
        "int" => text
            .parse()
            .map(Value::Int)
            .unwrap_or_else(|_| Value::Str(text.to_string())),
        "float" | "number" => text
            .parse()
            .map(Value::Float)
            .unwrap_or_else(|_| Value::Str(text.to_string())),
        "bool" => match text {
            "true" => Value::Bool(true),
            "false" => Value::Bool(false),
            other => Value::Str(other.to_string()),
        },
        _ => Value::Str(text.to_string()),
    }
}
