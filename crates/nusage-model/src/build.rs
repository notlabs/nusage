use std::collections::{BTreeMap, BTreeSet};

use nusage_spec::{Assembled, CommandPath, Diagnostic, Header, HeaderNode};
use usage::{SpecArg, SpecCommand, SpecFlag};

use crate::{Command, CommandTree, Completer, NuType, Param, ParamKind, Value};

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
    let mut commands = Vec::new();
    visit(
        &assembled.spec.cmd,
        CommandPath::root(),
        &[],
        assembled,
        &providers,
        &completers,
        &mut commands,
    )?;
    Ok(CommandTree {
        bin: assembled.spec.bin.clone(),
        commands,
    })
}

fn visit(
    cmd: &SpecCommand,
    path: CommandPath,
    inherited: &[Param],
    assembled: &Assembled,
    providers: &BTreeSet<&CommandPath>,
    completers: &BTreeMap<(&CommandPath, &str), &CommandPath>,
    out: &mut Vec<Command>,
) -> Result<(), Diagnostic> {
    let header = assembled
        .headers
        .get(&path)
        .expect("assemble records a header for every command");
    let body = assembled
        .bodies
        .get(&path)
        .expect("assemble records a body for every command");
    let is_provider = providers.contains(&path);

    let positionals = cmd
        .args
        .iter()
        .map(|arg| positional(arg, header, &path, completers))
        .collect::<Result<Vec<_>, _>>()?;
    let own_flags = cmd
        .flags
        .iter()
        .map(|flag| flag_param(flag, header, &path, completers, false))
        .collect::<Result<Vec<_>, _>>()?;
    let output = output_type(header);

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
                 completion token when it calls a completer, so any flag or argument would be \
                 unbound",
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
        about: header.spec.about.clone(),
        about_long: header.spec.about_long.clone(),
        positionals,
        flags,
        output,
        attributes,
        body: body.clone(),
        is_provider,
    });

    // What children inherit: this command's inherited flags, then its own `global=#true` ones.
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

    let (first, rest): (Vec<_>, Vec<_>) = cmd
        .subcommands
        .iter()
        .partition(|(name, _)| providers.contains(&path.child(name)));
    for (name, sub) in first.into_iter().chain(rest) {
        visit(
            sub,
            path.child(name),
            &passed_down,
            assembled,
            providers,
            completers,
            out,
        )?;
    }
    Ok(())
}

fn snake(name: &str) -> String {
    name.replace('-', "_")
}

/// usage's convention: `<file>` and `<dir>` complete as paths.
fn conventional_type(usage_name: &str) -> &'static str {
    match usage_name {
        "file" | "dir" | "path" => "path",
        _ => "string",
    }
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

/// `<file>...`, `[file]`, `<-- file>` → `file`.
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

fn positional(
    arg: &SpecArg,
    header: &Header,
    path: &CommandPath,
    completers: &BTreeMap<(&CommandPath, &str), &CommandPath>,
) -> Result<Param, Diagnostic> {
    let node = arg_node(header, arg);
    let ty = NuType(
        node.and_then(|n| n.value_type())
            .unwrap_or_else(|| conventional_type(&arg.name))
            .to_string(),
    );
    let kind = if arg.var {
        ParamKind::Rest
    } else if arg.required {
        ParamKind::Required
    } else {
        ParamKind::Optional
    };
    let completer = completer_for(arg, path, &arg.name, header, completers)?;
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
        completer,
        default,
        doc: arg.help.clone(),
        inherited: false,
    })
}

fn flag_param(
    flag: &SpecFlag,
    header: &Header,
    path: &CommandPath,
    completers: &BTreeMap<(&CommandPath, &str), &CommandPath>,
    inherited: bool,
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
            let ty = NuType(
                node.and_then(|n| n.value_type())
                    .unwrap_or_else(|| conventional_type(&arg.name))
                    .to_string(),
            );
            let completer = completer_for(arg, path, &flag.name, header, completers)?;
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
        inherited,
    })
}

fn completer_for(
    arg: &SpecArg,
    path: &CommandPath,
    param: &str,
    header: &Header,
    completers: &BTreeMap<(&CommandPath, &str), &CommandPath>,
) -> Result<Option<Completer>, Diagnostic> {
    if let Some(provider) = completers.get(&(path, param)) {
        return Ok(Some(Completer::Command((*provider).clone())));
    }
    let Some(choices) = &arg.choices else {
        return Ok(None);
    };
    if let Some(run) = &choices.run {
        return Err(Diagnostic::new(
            &header.path,
            format!(
                "`choices run=\"{run}\"` is not a script in this tree; only sibling `.nu` \
                 providers are supported"
            ),
        ));
    }
    if choices.env().is_some() {
        return Err(Diagnostic::new(
            &header.path,
            "`choices env=` is not supported yet",
        ));
    }
    if choices.choices.is_empty() {
        return Ok(None);
    }
    Ok(Some(Completer::Inline(choices.choices.clone())))
}

fn output_type(header: &Header) -> Option<NuType> {
    let outputs: Vec<&HeaderNode> = header
        .nodes
        .iter()
        .filter(|node| node.name == "output")
        .collect();
    let chosen = outputs
        .iter()
        .find(|node| node.text.contains("default=#true"))
        .or_else(|| (outputs.len() == 1).then(|| &outputs[0]))?;
    chosen.value_type().map(|ty| NuType(ty.to_string()))
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
