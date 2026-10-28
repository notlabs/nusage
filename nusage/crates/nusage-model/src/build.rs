use std::collections::{BTreeMap, BTreeSet};
use std::sync::LazyLock;

use nu_protocol::engine::{EngineState, StateWorkingSet};
use nu_protocol::{Span, Type};
use nusage_spec::{Assembled, CommandPath, Diagnostic, Header, HeaderNode, Source};
use usage::{SpecArg, SpecCommand, SpecComplete, SpecFlag, SpecOutput};

use crate::schema;
use crate::{
    Command, CommandTree, Completer, Conversion, Execution, Framing, NuType, Param, ParamKind,
    Structured, Value,
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
    ctx.visit(&assembled.spec.cmd, CommandPath::root(), &[], &mut commands)?;
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

/// A command with its path and declaration; a chain of them runs from the root down.
#[derive(Clone, Copy)]
struct Level<'a> {
    path: &'a CommandPath,
    cmd: &'a SpecCommand,
    header: &'a Header,
}

/// A completer and, when usage declared one, the `complete type=` it carries.
type Found = Option<(Completer, Option<String>)>;

impl Context<'_> {
    fn visit(
        &self,
        cmd: &SpecCommand,
        path: CommandPath,
        ancestors: &[Level<'_>],
        out: &mut Vec<Command>,
    ) -> Result<(), Diagnostic> {
        let header = self.assembled.headers.get(&path).ok_or_else(|| {
            Diagnostic::new(
                self.source_path(),
                format!("`{path}` has no declaration; assembly should have recorded one"),
            )
        })?;
        let execution = match &self.assembled.source {
            Source::Scripts { .. } => {
                let body = self.assembled.body(&path).ok_or_else(|| {
                    Diagnostic::new(
                        &header.path,
                        format!(
                            "`{path}` has no script: a command an `include` adds to a script \
                             tree has nothing to run"
                        ),
                    )
                })?;
                Execution::Script(body.to_path_buf())
            }
            Source::Binary => Execution::External,
        };
        let is_provider = self.providers.contains(&path);
        let here = Level {
            path: &path,
            cmd,
            header,
        };
        let chain: Vec<Level<'_>> = ancestors.iter().copied().chain([here]).collect();
        let cmds: Vec<&SpecCommand> = chain.iter().map(|level| level.cmd).collect();

        // A command declares its positionals at the top level or in its clause, not both. A
        // clause repeats, so its one positional is the def's rest parameter, each instance an
        // item; a clause of several positionals is declared once, as a `def` is flat.
        let repeats = cmd
            .clause
            .as_ref()
            .is_some_and(|clause| clause.args.len() == 1);
        let positionals = cmd
            .args
            .iter()
            .map(|arg| (arg, false))
            .chain(
                cmd.clause
                    .iter()
                    .flat_map(|clause| clause.args.iter())
                    .map(|arg| (arg, true)),
            )
            .map(|(arg, clause)| self.positional(arg, here, clause, clause && repeats))
            .collect::<Result<Vec<_>, _>>()?;

        // The flags usage resolves for this command: its own, and the globals above it merged
        // by name, as the parser accepts them. usage lists them by name; here they go in
        // declaration order, the root's first. Each is built where it is declared, so its
        // annotation and completer are read from the right declaration.
        let flags = if is_provider {
            Vec::new()
        } else {
            let mut available = usage::available_flags(&cmds);
            let mut flags = Vec::new();
            let declares = |level: &Level<'_>, name: &str| {
                level
                    .cmd
                    .flags
                    .iter()
                    .chain(
                        level
                            .cmd
                            .clause
                            .iter()
                            .flat_map(|clause| clause.flags.iter()),
                    )
                    .any(|flag| flag.name == name)
            };
            for level in &chain {
                let declared = level.cmd.flags.iter().map(|flag| (flag, false)).chain(
                    level
                        .cmd
                        .clause
                        .iter()
                        .flat_map(|clause| clause.flags.iter())
                        .map(|flag| (flag, true)),
                );
                for (declared, clause) in declared {
                    let Some(index) = available.iter().position(|f| f.name == declared.name) else {
                        continue;
                    };
                    let flag = available.remove(index);
                    // A hidden flag is not the module's; a builtin one, `--help`, is Nushell's.
                    if flag.hide || flag.builtin {
                        continue;
                    }
                    // The flag usage accepts is the deepest declaration of the name, a
                    // subcommand's over an inherited global's: its annotation and completer
                    // are read there, in the position of the first declaration.
                    let owner = chain
                        .iter()
                        .rev()
                        .find(|level| declares(level, &declared.name))
                        .unwrap_or(level);
                    let mut param = self.flag_param(&flag, *owner)?;
                    param.inherited = owner.path != &path;
                    param.clause = clause;
                    flags.push(param);
                }
            }
            // Anything usage adds beyond the declarations, such as a flagset's.
            for flag in &available {
                if flag.hide || flag.builtin {
                    continue;
                }
                flags.push(self.flag_param(flag, here)?);
            }
            flags
        };

        // The outputs usage resolves for this command: the spec's, merged by name with each
        // command's down the chain, hidden ones removed. A script's value is what its default
        // output describes; a binary can be asked for any of its outputs, and the annotation
        // of each is on its declaration: the deepest command declaring an output by that
        // name, else the spec's top level.
        let outputs = usage::effective_outputs_ref(&self.assembled.spec, cmds.iter().copied());
        let (output, structured, flags) = match execution {
            Execution::Script(_) => {
                let output = default_output(&outputs)
                    .and_then(|output| output_annotation(&chain, &output.name));
                (output, None, flags)
            }
            Execution::External => {
                let select = usage::effective_select_ref(&self.assembled.spec, &cmds);
                let args = |name: &str| self.assembled.output_args(&path, name);
                let structured = structured_output(&outputs, select.as_deref(), &args, &chain)
                    .map_err(|message| Diagnostic::new(&header.path, message))?;
                // The wrapper owns the selectors: a flag that picks an output is not a
                // parameter, since the wrapper asks for its structured output itself and the
                // binary alone, `^tool`, gives the others. That is every flag an output's
                // `nusage-args` names too, `--template` in `--template json(self)`.
                let named: Vec<&str> = outputs
                    .iter()
                    .filter_map(|output| args(&output.name))
                    .flatten()
                    .filter_map(|word| nusage_spec::flag_word(word))
                    .collect();
                let selectors: Vec<&str> = outputs
                    .iter()
                    .filter_map(|output| output.select.as_deref())
                    .chain(select.as_deref())
                    .chain(named)
                    .collect();
                let flags = flags
                    .into_iter()
                    .filter(|flag| !selectors.iter().any(|selector| flag_named(flag, selector)))
                    .collect();
                let output = match &structured {
                    Some(structured) => structured.ty.clone(),
                    None => Some(NuType("string".into())),
                };
                (output, structured, flags)
            }
        };

        if is_provider {
            if !positionals.is_empty() || !cmd.flags.is_empty() {
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
            clause: cmd.clause.as_ref().map(|clause| clause.name.clone()),
            positionals,
            flags,
            output,
            structured,
            attributes,
            execution,
            is_provider,
        });

        let (first, rest): (Vec<_>, Vec<_>) = cmd
            .subcommands
            .iter()
            .partition(|(name, _)| self.providers.contains(&path.child(name)));
        // What usage hides is not a command of the module; `^tool` still runs it.
        for (name, sub) in first.into_iter().chain(rest) {
            if sub.hide {
                continue;
            }
            self.visit(sub, path.child(name), &chain, out)?;
        }
        Ok(())
    }

    fn source_path(&self) -> std::path::PathBuf {
        self.assembled
            .headers
            .get(&CommandPath::root())
            .map(|header| header.path.clone())
            .unwrap_or_default()
    }

    /// A positional as declared at `level`; `repeats` makes it the rest parameter whatever
    /// usage says, for a clause's.
    fn positional(
        &self,
        arg: &SpecArg,
        level: Level<'_>,
        clause: bool,
        repeats: bool,
    ) -> Result<Param, Diagnostic> {
        let node = arg_node(level.header, arg);
        let found = self.completer_for(arg, level, &arg.name)?;
        let ty = NuType(
            node.and_then(|n| n.value_type())
                .map(str::to_string)
                .unwrap_or_else(|| conventional_type(arg, &found)),
        );
        let kind = if arg.var || repeats {
            ParamKind::Rest
        } else if arg.required {
            ParamKind::Required
        } else {
            ParamKind::Optional
        };
        let default = match kind {
            ParamKind::Rest => None,
            _ => arg
                .default
                .first()
                .map(|text| typed_default(text, &ty, level.header, node))
                .transpose()?,
        };
        let key = snake(&arg.name);
        Ok(Param {
            usage_name: arg.name.clone(),
            var: variable(&key),
            key,
            kind,
            ty,
            long: None,
            short: None,
            completer: found.map(|(completer, _)| completer),
            default,
            negate: None,
            doc: arg.help.clone(),
            inherited: false,
            clause,
        })
    }

    /// A flag as declared at `level`, the command that declares it.
    fn flag_param(&self, flag: &SpecFlag, level: Level<'_>) -> Result<Param, Diagnostic> {
        let node = flag_node(level.header, flag);
        let long = flag.long.first().cloned();
        let short = flag.short.first().copied();
        let (kind, ty, default, completer) = match (&flag.arg, flag.count, flag.var) {
            (None, true, _) => (
                ParamKind::Count,
                NuType("int".into()),
                Some(Value::int(0, Span::unknown())),
                None,
            ),
            (None, false, _) => {
                let ty = NuType("bool".into());
                let default = flag
                    .default
                    .first()
                    .map(|text| typed_default(text, &ty, level.header, node))
                    .transpose()?;
                (ParamKind::Switch, ty, default, None)
            }
            (Some(arg), _, repeated) => {
                let found = self.completer_for(arg, level, &flag.name)?;
                let ty = NuType(
                    node.and_then(|n| n.value_type())
                        .map(str::to_string)
                        .unwrap_or_else(|| conventional_type(arg, &found)),
                );
                let completer = found.map(|(completer, _)| completer);
                // A flag given several times, or one taking several values, is a list.
                if repeated || arg.var {
                    let defaults = flag
                        .default
                        .iter()
                        .map(|text| typed_default(text, &ty, level.header, node))
                        .collect::<Result<Vec<_>, _>>()?;
                    (
                        ParamKind::Repeated,
                        ty,
                        Some(Value::list(defaults, Span::unknown())),
                        completer,
                    )
                } else {
                    let default = flag
                        .default
                        .first()
                        .map(|text| typed_default(text, &ty, level.header, node))
                        .transpose()?;
                    (ParamKind::Valued, ty, default, completer)
                }
            }
        };
        let key = snake(&flag.name);
        Ok(Param {
            usage_name: flag.name.clone(),
            var: variable(&key),
            key,
            kind,
            ty,
            long,
            short,
            completer,
            default,
            negate: flag
                .negate
                .as_deref()
                .map(|negate| negate.trim_start_matches('-').to_string()),
            doc: flag.help.clone(),
            inherited: false,
            clause: false,
        })
    }

    /// The completer for an argument. In order: a provider in the tree, static `choices`,
    /// `choices run=`, then a `complete` node on the arg, on the command, or at the top level.
    fn completer_for(
        &self,
        arg: &SpecArg,
        level: Level<'_>,
        param: &str,
    ) -> Result<Found, Diagnostic> {
        let Level { path, cmd, header } = level;
        if let Some(provider) = self.completers.get(&(path, param)) {
            return Ok(Some((Completer::Command((*provider).clone()), None)));
        }
        if let Some(choices) = &arg.choices {
            if let Some(run) = &choices.run {
                return match self.assembled.source {
                    Source::Binary => Ok(Some((Completer::Spec, None))),
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
        // A `complete` on the argument, or one naming it, as usage resolves them.
        match self.assembled.spec.completer(cmd, arg) {
            Some(complete) => spec_completer(complete, &arg.name, header, &self.assembled.source),
            None => Ok(None),
        }
    }
}

/// A `complete` node: usage completes it, for a binary. A script's choices come from a
/// sibling provider, except a bare `type=`, which only says what the value is.
fn spec_completer(
    complete: &SpecComplete,
    name: &str,
    header: &Header,
    source: &Source,
) -> Result<Found, Diagnostic> {
    let ty = complete.type_.clone();
    match source {
        Source::Binary => Ok(Some((Completer::Spec, ty))),
        Source::Scripts { .. } if complete.run.is_none() => {
            Ok(ty.map(|ty| (Completer::Spec, Some(ty))))
        }
        Source::Scripts { .. } => Err(Diagnostic::new(
            &header.path,
            format!(
                "`complete \"{name}\" run=...` is not supported for scripts; name a sibling \
                 `.nu` provider with `choices run=` instead"
            ),
        )),
    }
}

/// A usage name as a Nushell identifier: every run of characters an identifier cannot hold
/// becomes one `_`, letters are lowercased (`dry-run` is `dry_run`, `TOOL@VERSION` is
/// `tool_version`), and a leading
/// digit gets one in front. usage's own `snake_case` does the same for its SDKs; it is a
/// copy, since usage keeps it private.
fn snake(name: &str) -> String {
    let mut out = String::new();
    let mut gap = false;
    for c in name.chars() {
        if c.is_ascii_alphanumeric() {
            if gap && !out.is_empty() {
                out.push('_');
            }
            gap = false;
            out.push(c.to_ascii_lowercase());
        } else {
            gap = true;
        }
    }
    if out.starts_with(|c: char| c.is_ascii_digit()) {
        out.insert(0, '_');
    }
    out
}

/// The Nushell variable for a key: the key, unless Nushell reserves it, then with `_`.
fn variable(key: &str) -> String {
    if nusage_nu::reserved_variable(key) {
        format!("{key}_")
    } else {
        key.to_string()
    }
}

/// How a usage name is spelled in Nushell: the `$usage` key and the variable, as
/// [`Param::key`] and [`Param::var`] describe them.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Identifier {
    pub key: String,
    pub var: String,
}

pub fn identifier(usage_name: &str) -> Identifier {
    let key = snake(usage_name);
    Identifier {
        var: variable(&key),
        key,
    }
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

/// The output a command produces unasked: the default one, else the only one.
fn default_output(outputs: &[SpecOutput]) -> Option<&SpecOutput> {
    outputs
        .iter()
        .find(|output| output.default)
        .or_else(|| (outputs.len() == 1).then(|| &outputs[0]))
}

/// The annotation on the declaration of the named output in effect: the deepest command in
/// the chain that declares an output by that name, else the root, whose declaration holds
/// the spec's top-level outputs. A declaration usage expanded from another file has no
/// annotation.
fn output_annotation(chain: &[Level<'_>], name: &str) -> Option<NuType> {
    let declaring = chain
        .iter()
        .rev()
        .find(|level| level.cmd.outputs.iter().any(|output| output.name == name))
        .or_else(|| chain.first())?;
    declaring
        .header
        .nodes
        .iter()
        .find(|node| node.name == "output" && node.first.as_deref() == Some(name))
        .and_then(|node| node.value_type())
        .map(|ty| NuType(ty.to_string()))
}

/// Whether a selector word, `--json` or `-j`, names the flag.
fn flag_named(flag: &Param, selector: &str) -> bool {
    let name = selector.trim_start_matches('-');
    flag.long.as_deref() == Some(name)
        || (name.chars().count() == 1 && flag.short == name.chars().next())
}

/// The structured output a wrapper asks for: the default output when it is framed, else the
/// first `json` output that is selectable, else the first `jsonl` one; `None` for a text
/// command. An output is selectable when its `nusage-args` say how to ask for it, it is the
/// default, has its own `select` switch, or the command has a `select` flag whose value
/// names it.
fn structured_output<'a>(
    outputs: &[SpecOutput],
    command_select: Option<&str>,
    nusage_args: &dyn Fn(&str) -> Option<&'a [String]>,
    chain: &[Level<'_>],
) -> Result<Option<Structured>, String> {
    let framing_of = |output: &SpecOutput| match output.framing {
        usage::Framing::Json => Some(Framing::Json),
        usage::Framing::Jsonl => Some(Framing::Jsonl),
        _ => None,
    };
    let args_of = |output: &SpecOutput| -> Option<Vec<String>> {
        if let Some(words) = nusage_args(&output.name) {
            Some(words.to_vec())
        } else if output.default {
            Some(Vec::new())
        } else if let Some(switch) = &output.select {
            Some(vec![switch.clone()])
        } else {
            command_select.map(|flag| vec![flag.to_string(), output.name.clone()])
        }
    };
    let candidates = || {
        outputs
            .iter()
            .filter(|output| framing_of(output).is_some())
            .filter_map(|output| args_of(output).map(|args| (output, args)))
    };
    let chosen = candidates()
        .find(|(output, _)| output.default)
        .or_else(|| candidates().find(|(output, _)| output.framing == usage::Framing::Json))
        .or_else(|| candidates().next());
    let Some((output, args)) = chosen else {
        return Ok(None);
    };
    // The type: the output's schema, which usage carries, else the annotation on its
    // declaration, which is nusage's own and says the same thing in Nushell's words.
    let annotation = output_annotation(chain, &output.name);
    let (ty, fills, conversions) = match (&output.schema, annotation) {
        (Some(_), Some(_)) => {
            return Err(format!(
                "output `{}` has both a schema and a type annotation; declare one",
                output.name
            ));
        }
        (Some(schema), None) => {
            let shape = schema::shape(schema)
                .map_err(|why| format!("the schema of output `{}`: {why}", output.name))?;
            // A schema describes one document; JSON lines are a list of them, a table when
            // they are objects, and the fills and conversions apply to every row.
            let ty = match framing_of(output) {
                Some(Framing::Jsonl) => match shape.ty.0.strip_prefix("record<") {
                    Some(rest) => NuType(format!("table<{rest}")),
                    None => NuType(format!("list<{}>", shape.ty.0)),
                },
                _ => shape.ty,
            };
            (Some(ty), shape.fills, shape.conversions)
        }
        (None, Some(ty)) => {
            let conversions = conversions_for(&ty)?;
            (Some(ty), Vec::new(), conversions)
        }
        (None, None) => (None, Vec::new(), Vec::new()),
    };
    Ok(Some(Structured {
        name: output.name.clone(),
        args,
        framing: framing_of(output).expect("a candidate is framed"),
        ty,
        fills,
        conversions,
    }))
}

/// What the annotation declares that JSON cannot carry: datetimes, durations, filesizes and
/// binary, each at the cell path where it sits, converted after decoding. Inside a list there
/// is no cell path to convert at, so such an annotation is an error, not a silent string.
fn conversions_for(ty: &NuType) -> Result<Vec<Conversion>, String> {
    let parsed =
        parse_type(ty).map_err(|err| format!("`{}` is not a Nushell type: {err}", ty.as_str()))?;
    let mut out = Vec::new();
    collect_conversions(&parsed, Vec::new(), &mut out, ty)?;
    Ok(out)
}

fn collect_conversions(
    ty: &Type,
    path: Vec<String>,
    out: &mut Vec<Conversion>,
    declared: &NuType,
) -> Result<(), String> {
    let converted = match ty {
        Type::Date => Some("datetime"),
        Type::Duration => Some("duration"),
        Type::Filesize => Some("filesize"),
        Type::Binary => Some("binary"),
        _ => None,
    };
    if let Some(into) = converted {
        out.push(Conversion {
            path,
            ty: into.to_string(),
            unit: None,
            nullable: false,
        });
        return Ok(());
    }
    match ty {
        Type::Record(columns) | Type::Table(columns) => {
            for (column, column_ty) in columns.iter() {
                let mut path = path.clone();
                path.push(column.clone());
                collect_conversions(column_ty, path, out, declared)?;
            }
        }
        Type::List(inner) if needs_conversion(inner) => {
            return Err(format!(
                "`{}` declares a {inner} inside a list, which cannot be converted after \
                 decoding; JSON would deliver it as text",
                declared.as_str()
            ));
        }
        _ => {}
    }
    Ok(())
}

fn needs_conversion(ty: &Type) -> bool {
    match ty {
        Type::Date | Type::Duration | Type::Filesize | Type::Binary => true,
        Type::Record(columns) | Type::Table(columns) => {
            columns.iter().any(|(_, ty)| needs_conversion(ty))
        }
        Type::List(inner) => needs_conversion(inner),
        _ => false,
    }
}

/// Nushell's parser with its keywords, for reading a type annotation the way a signature
/// does.
static ENGINE: LazyLock<EngineState> = LazyLock::new(nu_cmd_lang::create_default_context);

/// usage keeps every default as text; the parameter's type says how Nushell reads it. A
/// `string` or path type takes the text itself; any other type reads the text as NUON. Then
/// Nushell's parser judges the pair, as it would the signature the default is written into.
fn typed_default(
    text: &str,
    ty: &NuType,
    header: &Header,
    node: Option<&HeaderNode>,
) -> Result<Value, Diagnostic> {
    let at = |message: String| {
        let diagnostic = Diagnostic::new(&header.path, message);
        match node {
            Some(node) => diagnostic.at_line(node.line),
            None => diagnostic,
        }
    };
    let value = value_from_text(text, ty).map_err(|err| at(format!("default {err}")))?;
    let nu_type = nusage_nu::Type::new(ty.as_str()).map_err(|err| at(err.to_string()))?;
    nusage_nu::check_default(&nu_type, &value).map_err(|err| at(err.to_string()))?;
    Ok(value)
}

/// A value of the parameter's type from the text usage holds for it, a default or a word of
/// argv: the text itself for a string type, else the text read as NUON.
pub fn value_from_text(text: &str, ty: &NuType) -> Result<Value, String> {
    let span = Span::unknown();
    if matches!(ty.as_str(), "string" | "path" | "glob" | "directory") {
        return Ok(Value::string(text, span));
    }
    nuon::from_nuon(text, Some(span))
        .map_err(|err| format!("{text:?} does not read as a `{}`: {err}", ty.as_str()))
}

/// The type a signature reads from the annotation: nu-parser keeps its type parser private,
/// so the annotation is parsed as the type of a parameter.
fn parse_type(ty: &NuType) -> Result<Type, String> {
    let mut working_set = StateWorkingSet::new(&ENGINE);
    let source = format!("def __nusage_type [p: {}] {{}}", ty.as_str());
    nu_parser::parse(&mut working_set, None, source.as_bytes(), false);
    if let Some(err) = working_set.parse_errors.first() {
        return Err(err.to_string());
    }
    let decl = working_set
        .find_decl(b"__nusage_type")
        .map(|id| working_set.get_decl(id))
        .ok_or_else(|| "the parser did not define the probe".to_string())?;
    decl.signature()
        .required_positional
        .first()
        .map(|positional| positional.shape.to_type())
        .ok_or_else(|| "the parser kept no parameter".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn header() -> Header {
        Header {
            path: "spec.kdl".into(),
            nodes: Vec::new(),
            about: None,
            about_long: None,
        }
    }

    #[test]
    fn defaults_read_as_their_declared_type() {
        let h = header();
        let int = typed_default("10", &NuType("int".into()), &h, None).unwrap();
        assert_eq!(int, Value::test_int(10));
        let date =
            typed_default("2026-10-27T00:00:00Z", &NuType("datetime".into()), &h, None).unwrap();
        assert!(matches!(date, Value::Date { .. }));
        let text = typed_default("1", &NuType("string".into()), &h, None).unwrap();
        assert_eq!(text, Value::test_string("1"));
        let number = typed_default("1", &NuType("number".into()), &h, None).unwrap();
        assert_eq!(number, Value::test_int(1));
        // The parser's own coercions and subtyping, not a second rule.
        assert!(typed_default("1", &NuType("float".into()), &h, None).is_ok());
        assert!(typed_default("[]", &NuType("list<string>".into()), &h, None).is_ok());
        assert!(typed_default("[1 2]", &NuType("list<number>".into()), &h, None).is_ok());
        assert!(typed_default("{a: 1}", &NuType("record".into()), &h, None).is_ok());
    }

    #[test]
    fn a_default_of_the_wrong_type_is_a_diagnostic() {
        let h = header();
        let err = typed_default("latest", &NuType("datetime".into()), &h, None).unwrap_err();
        assert!(err.message.contains("datetime"), "{err:?}");
        let err = typed_default("1.5", &NuType("int".into()), &h, None).unwrap_err();
        assert!(
            err.message.contains("not a default Nushell accepts"),
            "{err:?}"
        );
        let err = typed_default("1", &NuType("widget".into()), &h, None).unwrap_err();
        assert!(err.message.contains("widget"), "{err:?}");
    }

    #[test]
    fn names_become_identifiers() {
        assert_eq!(snake("dry-run"), "dry_run");
        assert_eq!(snake("TOOL@VERSION"), "tool_version");
        assert_eq!(snake("a.b/c"), "a_b_c");
        assert_eq!(snake("1st"), "_1st");
        assert_eq!(snake("--x"), "x");
    }

    #[test]
    fn conversions_follow_the_annotation() {
        let paths = |ty: &str| -> Vec<(String, String)> {
            conversions_for(&NuType(ty.into()))
                .unwrap()
                .into_iter()
                .map(|c| (c.path.join("."), c.ty))
                .collect()
        };
        assert_eq!(paths("record<ok: bool>"), vec![]);
        assert_eq!(
            paths("table<at: datetime, kind: string>"),
            vec![("at".to_string(), "datetime".to_string())]
        );
        assert_eq!(
            paths("record<meta: record<took: duration>, size: filesize>"),
            vec![
                ("meta.took".to_string(), "duration".to_string()),
                ("size".to_string(), "filesize".to_string())
            ]
        );
        assert_eq!(
            paths("datetime"),
            vec![("".to_string(), "datetime".to_string())]
        );
        assert!(conversions_for(&NuType("list<datetime>".into())).is_err());
        assert!(conversions_for(&NuType("list<string>".into())).is_ok());
    }
}
