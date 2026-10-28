use std::collections::{BTreeMap, BTreeSet};
use std::sync::LazyLock;

use nu_protocol::engine::{EngineState, StateWorkingSet};
use nu_protocol::{Span, Type};
use nusage_spec::{Assembled, CommandPath, Diagnostic, Header, HeaderNode, Source};
use usage::{SpecArg, SpecCommand, SpecComplete, SpecFlag, SpecOutput};

use crate::{
    Command, CommandTree, Completer, Conversion, Decoding, Execution, Framing, NuType, Output,
    Param, ParamKind, Value,
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

        let positionals = cmd
            .args
            .iter()
            .map(|arg| self.positional(arg, here))
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
            for level in &chain {
                for declared in &level.cmd.flags {
                    let Some(index) = available.iter().position(|f| f.name == declared.name) else {
                        continue;
                    };
                    let flag = available.remove(index);
                    let mut param = self.flag_param(&flag, *level)?;
                    param.inherited = level.path != &path;
                    flags.push(param);
                }
            }
            // Anything usage adds beyond the declarations, such as a flagset's.
            for flag in &available {
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
        let (output, decoding) = match execution {
            Execution::Script(_) => {
                let output = default_output(&outputs)
                    .and_then(|output| output_annotation(&chain, &output.name));
                (output, None)
            }
            Execution::External => {
                let select = usage::effective_select_ref(&self.assembled.spec, &cmds);
                let decoding = decoding(&outputs, select.as_deref(), &flags, &chain)
                    .map_err(|message| Diagnostic::new(&header.path, message))?;
                (union_type(&decoding), Some(decoding))
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
            positionals,
            flags,
            output,
            decoding,
            attributes,
            execution,
            is_provider,
        });

        let (first, rest): (Vec<_>, Vec<_>) = cmd
            .subcommands
            .iter()
            .partition(|(name, _)| self.providers.contains(&path.child(name)));
        for (name, sub) in first.into_iter().chain(rest) {
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

    fn positional(&self, arg: &SpecArg, level: Level<'_>) -> Result<Param, Diagnostic> {
        let node = arg_node(level.header, arg);
        let found = self.completer_for(arg, level, &arg.name)?;
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
            _ => arg
                .default
                .first()
                .map(|text| typed_default(text, &ty, level.header, node))
                .transpose()?,
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
            negate: None,
            doc: arg.help.clone(),
            inherited: false,
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
                if repeated {
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
        Ok(Param {
            usage_name: flag.name.clone(),
            var: snake(&flag.name),
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
                    Source::Binary => Ok(Some((
                        Completer::Shell {
                            name: self.scoped_name(path, param),
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
        // A `complete` on the argument or the command is that command's; one at the top level
        // is shared by every command naming it. The helper's name says which.
        let named = arg
            .complete
            .as_ref()
            .map(|complete| (complete, self.scoped_name(path, param)))
            .or_else(|| {
                cmd.complete
                    .get(&arg.name)
                    .map(|complete| (complete, self.scoped_name(path, &arg.name)))
            })
            .or_else(|| {
                self.assembled
                    .spec
                    .complete
                    .get(&arg.name)
                    .map(|complete| (complete, arg.name.clone()))
            });
        match named {
            Some((complete, name)) => {
                shell_completer(complete, name, header, &self.assembled.source)
            }
            None => Ok(None),
        }
    }
}

impl Context<'_> {
    /// The name of a helper that belongs to one command's parameter: the command's full name,
    /// binary first, then the parameter. A spec-level completer's name is bare, so the root's
    /// own completer for `value` is `demo value` and never the spec's `value`.
    fn scoped_name(&self, path: &CommandPath, param: &str) -> String {
        let bin = &self.assembled.spec.bin;
        if path.is_root() {
            format!("{bin} {param}")
        } else {
            format!("{bin} {path} {param}")
        }
    }
}

fn shell_completer(
    complete: &SpecComplete,
    name: String,
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
            name,
            run: run.clone(),
            descriptions: complete.descriptions,
        },
        ty,
    )))
}

/// usage's own `snake_case`, as its SDKs name arguments; a copy, since usage keeps it private.
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

/// How a binary's call selects an output and what each decodes to. A `select` on an output
/// is a switch that picks it; a `select` in effect for the command is a flag whose value is
/// the output's name. Either names a flag the command has, by its long or short form.
fn decoding(
    outputs: &[SpecOutput],
    command_select: Option<&str>,
    flags: &[Param],
    chain: &[Level<'_>],
) -> Result<Decoding, String> {
    let var_of = |selector: &str| -> Option<String> {
        let name = selector.trim_start_matches('-');
        flags
            .iter()
            .find(|flag| {
                flag.long.as_deref() == Some(name)
                    || (name.chars().count() == 1 && flag.short == name.chars().next())
            })
            .map(|flag| flag.var.clone())
    };
    let switches = outputs
        .iter()
        .filter_map(|output| {
            let selector = output.select.as_deref()?;
            var_of(selector).map(|var| (var, output.name.clone()))
        })
        .collect();
    let value_selector = command_select.and_then(var_of);
    let default = default_output(outputs).map(|output| output.name.clone());
    let outputs = outputs
        .iter()
        .map(|output| {
            let framing = match output.framing {
                usage::Framing::Json => Some(Framing::Json),
                usage::Framing::Jsonl => Some(Framing::Jsonl),
                _ => None,
            };
            let ty = framing.and_then(|_| output_annotation(chain, &output.name));
            let conversions = match &ty {
                Some(ty) => conversions_for(ty)?,
                None => Vec::new(),
            };
            Ok(Output {
                name: output.name.clone(),
                framing,
                ty,
                conversions,
            })
        })
        .collect::<Result<Vec<_>, String>>()?;
    Ok(Decoding {
        switches,
        value_selector,
        default,
        outputs,
    })
}

/// What a binary's call can return: text for an unframed output, the annotation for a framed
/// one; a `oneof` when they differ, nothing when a framed output has no annotation.
fn union_type(decoding: &Decoding) -> Option<NuType> {
    let mut types: Vec<String> = Vec::new();
    for output in &decoding.outputs {
        let ty = match (&output.framing, &output.ty) {
            (None, _) => "string".to_string(),
            (Some(_), Some(ty)) => ty.as_str().to_string(),
            (Some(_), None) => return None,
        };
        if !types.contains(&ty) {
            types.push(ty);
        }
    }
    match types.len() {
        0 => None,
        1 => Some(NuType(types.remove(0))),
        _ => Some(NuType(format!("oneof<{}>", types.join(", ")))),
    }
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
