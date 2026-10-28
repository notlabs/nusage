//! Whether a generated module carries what its spec shows, as usage reads the spec: the
//! oracle is usage's own view of a command, not the model that wrote the module, so this
//! holds the generator to usage rather than to itself. Every command usage shows is a
//! definition with the spec's positionals, flags and completers, named as the generator
//! names them, with its description once.

use std::collections::BTreeMap;
use std::path::Path;

use nusage_model::identifier;
use nusage_nu::{Decl, SyntaxError, signatures};
use nusage_spec::{Assembled, Source};
use usage::{Spec, SpecArg, SpecCommand, SpecFlag};

/// The findings for `module`, the text of the module written for `assembled` as
/// `<name>.nu` in `dir`: empty when it conforms.
pub fn conform(
    assembled: &Assembled,
    name: &str,
    module: &str,
    dir: Option<&Path>,
) -> Result<Vec<String>, SyntaxError> {
    let decls: BTreeMap<String, Decl> = signatures(name, module, dir)?
        .into_iter()
        .map(|decl| (decl.name.clone(), decl))
        .collect();
    let mut findings = Vec::new();
    let providers: Vec<Vec<String>> = assembled
        .providers
        .iter()
        .map(|provider| provider.provider.words().to_vec())
        .collect();
    let checker = Checker {
        spec: &assembled.spec,
        binary: matches!(assembled.source, Source::Binary),
        providers,
        decls: &decls,
    };
    checker.command(&assembled.spec.cmd, &[], &[], &mut findings);
    Ok(findings)
}

struct Checker<'a> {
    spec: &'a Spec,
    binary: bool,
    /// The scripts other scripts name as completion providers: completion calls them with
    /// the word to complete and nothing else, so they take no flags.
    providers: Vec<Vec<String>>,
    decls: &'a BTreeMap<String, Decl>,
}

/// What a positional or a flag's value should look like in the definition.
struct Expected {
    name: String,
    completer: bool,
}

impl Checker<'_> {
    fn command(
        &self,
        cmd: &SpecCommand,
        ancestors: &[&SpecCommand],
        words: &[String],
        findings: &mut Vec<String>,
    ) {
        let chain: Vec<&SpecCommand> = ancestors.iter().copied().chain([cmd]).collect();
        let def = if words.is_empty() {
            "main".to_string()
        } else if self.binary {
            format!("{} {}", self.spec.bin, words.join(" "))
        } else {
            words.join(" ")
        };
        let provider = self.providers.iter().any(|path| path == words);
        match self.decls.get(&def) {
            Some(decl) => self.definition(cmd, &chain, &def, decl, provider, findings),
            None => findings.push(format!("`{def}`: no definition")),
        }
        for (name, sub) in &cmd.subcommands {
            if sub.hide {
                continue;
            }
            let mut words = words.to_vec();
            words.push(name.clone());
            self.command(sub, &chain, &words, findings);
        }
    }

    fn definition(
        &self,
        cmd: &SpecCommand,
        chain: &[&SpecCommand],
        def: &str,
        decl: &Decl,
        provider: bool,
        findings: &mut Vec<String>,
    ) {
        let mut note = |what: String| findings.push(format!("`{def}`: {what}"));

        // Positionals: the command's or its clause's, a clause's one positional repeating.
        let repeats = cmd
            .clause
            .as_ref()
            .is_some_and(|clause| clause.args.len() == 1);
        let mut required = Vec::new();
        let mut optional = Vec::new();
        let mut rest: Option<Expected> = None;
        for (arg, in_clause) in cmd.args.iter().map(|arg| (arg, false)).chain(
            cmd.clause
                .iter()
                .flat_map(|clause| clause.args.iter())
                .map(|arg| (arg, true)),
        ) {
            let expected = Expected {
                name: identifier(&arg.name).var,
                completer: self.completes(cmd, arg),
            };
            if arg.var || (in_clause && repeats) {
                // A definition has one rest parameter; a later variadic rides on it.
                if rest.is_none() {
                    rest = Some(expected);
                }
            } else if arg.required {
                required.push(expected);
            } else {
                optional.push(expected);
            }
        }
        for (kind, expected, found) in [
            ("required", &required, &decl.required),
            ("optional", &optional, &decl.optional),
        ] {
            let names = |list: &[Expected]| list.iter().map(|e| e.name.clone()).collect::<Vec<_>>();
            let found_names: Vec<String> = found.iter().map(|arg| arg.name.clone()).collect();
            if names(expected) != found_names {
                note(format!(
                    "{kind} positionals are {found_names:?}, the spec has {:?}",
                    names(expected)
                ));
                continue;
            }
            for (expected, found) in expected.iter().zip(found) {
                if expected.completer != found.completer {
                    note(format!(
                        "positional `{}`: completer: the module {}, the spec {}",
                        expected.name,
                        has(found.completer),
                        has(expected.completer)
                    ));
                }
            }
        }
        match (&rest, &decl.rest) {
            (None, None) => {}
            (Some(expected), Some(found)) => {
                if expected.name != found.name {
                    note(format!(
                        "the rest parameter is `{}`, the spec has `{}`",
                        found.name, expected.name
                    ));
                } else if expected.completer != found.completer {
                    note(format!(
                        "rest parameter `{}`: completer: the module {}, the spec {}",
                        expected.name,
                        has(found.completer),
                        has(expected.completer)
                    ));
                }
            }
            (Some(expected), None) => note(format!("no rest parameter for `{}`", expected.name)),
            (None, Some(found)) => note(format!(
                "rest parameter `{}` is not in the spec",
                found.name
            )),
        }

        // Flags: what usage accepts here, less the hidden, the builtin and the output
        // selectors, which the wrapper passes itself.
        let selectors: Vec<String> = usage::effective_outputs_ref(self.spec, chain.iter().copied())
            .iter()
            .filter_map(|output| output.select.clone())
            .chain(usage::effective_select_ref(self.spec, chain))
            .map(|select| select.trim_start_matches('-').to_string())
            .collect();
        let mut expected_flags: Vec<(String, Option<char>, bool, bool)> = Vec::new();
        let available = if provider {
            Vec::new()
        } else {
            usage::available_flags(chain)
        };
        for flag in available {
            if flag.hide || flag.builtin || selectors.contains(&flag.name) {
                continue;
            }
            let long = self.flag_long(&flag);
            let completer = flag
                .arg
                .as_ref()
                .is_some_and(|arg| self.completes(cmd, arg));
            expected_flags.push((
                long,
                flag.short.first().copied(),
                flag.arg.is_some() || flag.count,
                completer,
            ));
            if let Some(negate) = &flag.negate {
                expected_flags.push((
                    negate.trim_start_matches('-').to_string(),
                    None,
                    false,
                    false,
                ));
            }
        }
        for (long, short, takes_value, completer) in &expected_flags {
            let Some(found) = decl.flags.iter().find(|flag| &flag.long == long) else {
                note(format!("no flag `--{long}`"));
                continue;
            };
            if found.short != *short {
                note(format!(
                    "`--{long}` has short {:?}, the spec has {:?}",
                    found.short, short
                ));
            }
            if found.takes_value != *takes_value {
                note(format!(
                    "`--{long}` {} a value, the spec {}",
                    takes(found.takes_value),
                    takes(*takes_value)
                ));
            }
            if found.completer != *completer {
                note(format!(
                    "`--{long}`: completer: the module {}, the spec {}",
                    has(found.completer),
                    has(*completer)
                ));
            }
        }
        for found in &decl.flags {
            if !expected_flags.iter().any(|(long, ..)| long == &found.long) {
                note(format!("flag `--{}` is not in the spec", found.long));
            }
        }

        // The description: the spec's, once.
        if let Some(about) = &cmd.help {
            let about = about.trim();
            if decl.description != about {
                note(format!(
                    "the description is {:?}, the spec's is {about:?}",
                    decl.description
                ));
            }
        }
        if !decl.description.is_empty() && decl.extra_description.starts_with(&decl.description) {
            note("the description is repeated".to_string());
        }
    }

    /// Whether the definition completes the value: for a binary, whatever usage completes
    /// and declared choices; for a script, its choices, since a `complete` node's bare type
    /// completes nothing there.
    fn completes(&self, cmd: &SpecCommand, arg: &SpecArg) -> bool {
        let choices = arg
            .choices
            .as_ref()
            .is_some_and(|choices| choices.run.is_some() || !choices.choices.is_empty());
        choices || (self.binary && self.spec.completer(cmd, arg).is_some())
    }

    /// The flag's long name as the definition spells it.
    fn flag_long(&self, flag: &SpecFlag) -> String {
        let id = identifier(&flag.name);
        let long = flag
            .long
            .first()
            .cloned()
            .unwrap_or_else(|| flag.name.clone());
        if id.var != id.key {
            format!("{long}_")
        } else {
            long
        }
    }
}

fn has(completer: bool) -> &'static str {
    if completer { "has one" } else { "has none" }
}

fn takes(value: bool) -> &'static str {
    if value { "takes" } else { "takes no" }
}
