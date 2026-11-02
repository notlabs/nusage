//! The modules a project makes available to its scripts, which a script gets by calling
//! them rather than importing them. `NUS_MODULES` is a NUON record from a command's first
//! word to the absolute directory of the module exporting it; `NUS_TOOLS`, from each tool
//! the project has to the version it resolves to. nusage's mise fragment,
//! `nusage/conf.d/nus.toml`, writes both from the project's own installs.
//!
//! A call Nushell cannot resolve, `jj log ...` where nothing defines `jj`, whose first word
//! `NUS_MODULES` names, is the module's: the interpreter puts `use <module> *` before the
//! script, by the module's absolute path, so nothing is searched, and the line the editor
//! checks opens with the same. `^jj` is still the binary.
//!
//! A package records in `package.nuon`, beside its module, the tool and version its wrappers
//! were generated from, and its wrappers run that tool's binary from PATH: a project whose
//! own version of the tool differs cannot have the module, since its types describe another
//! binary.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use nu_protocol::Value;

/// The variable naming the modules, by the first word of the commands they export.
pub const MODULES: &str = "NUS_MODULES";
/// The variable naming the project's tools' versions.
pub const TOOLS: &str = "NUS_TOOLS";

/// The modules `source`, the script at `script`, gets: for each call Nushell cannot resolve
/// whose first word `NUS_MODULES` names, the module's directory, in the order of the first
/// such call; or why the script cannot have one.
pub fn implicit(script: &Path, source: &str) -> Result<Vec<PathBuf>, String> {
    let Some(modules) = record(MODULES)? else {
        return Ok(Vec::new());
    };
    select(script, source, &modules, record(TOOLS)?.as_ref())
}

/// Every module `NUS_MODULES` names, for an interactive session, which has no calls to read
/// beforehand; and why any is left out: a tool at another version than its package was
/// generated from, or a variable that does not read.
pub fn every() -> (Vec<PathBuf>, Vec<String>) {
    let modules = match record(MODULES) {
        Ok(Some(modules)) => modules,
        Ok(None) => return (Vec::new(), Vec::new()),
        Err(why) => return (Vec::new(), vec![why]),
    };
    let tools = match record(TOOLS) {
        Ok(tools) => tools,
        Err(why) => return (Vec::new(), vec![why]),
    };
    let mut found: Vec<PathBuf> = Vec::new();
    let mut left = Vec::new();
    for (word, dir) in &modules {
        let dir = PathBuf::from(dir);
        if found.contains(&dir) {
            continue;
        }
        match check(word, &dir, tools.as_ref()) {
            Ok(()) => found.push(dir),
            Err(why) => left.push(why),
        }
    }
    (found, left)
}

/// The lines that give a script its modules: `use <module> *`, by absolute path.
pub fn uses(modules: &[PathBuf]) -> Vec<String> {
    modules
        .iter()
        .map(|dir| format!("use {} *", nusage_nu::word(&dir.to_string_lossy())))
        .collect()
}

fn select(
    script: &Path,
    source: &str,
    modules: &BTreeMap<String, String>,
    tools: Option<&BTreeMap<String, String>>,
) -> Result<Vec<PathBuf>, String> {
    let mut found: Vec<PathBuf> = Vec::new();
    for call in nusage_nu::script_calls(source, script) {
        let nusage_nu::ScriptCall::External { head, .. } = call else {
            continue;
        };
        let Some(dir) = modules.get(&head.text) else {
            continue;
        };
        let dir = PathBuf::from(dir);
        if found.contains(&dir) {
            continue;
        }
        check(&head.text, &dir, tools)?;
        found.push(dir);
    }
    Ok(found)
}

/// Whether the project's own version of the tool the module's package wraps is the version
/// the package was generated from. A module with no package record, or a package that pins
/// no tool, has nothing to hold.
fn check(word: &str, dir: &Path, tools: Option<&BTreeMap<String, String>>) -> Result<(), String> {
    let Some(file) = dir
        .parent()
        .map(|parent| parent.join("package.nuon"))
        .filter(|file| file.is_file())
    else {
        return Ok(());
    };
    let text = std::fs::read_to_string(&file)
        .map_err(|err| format!("cannot read {}: {err}", file.display()))?;
    let package = nuon::from_nuon(&text, None)
        .map_err(|err| format!("{} does not read as NUON: {err}", file.display()))?;
    let field = |value: &Value, name: &str| -> Option<String> {
        Some(
            value
                .as_record()
                .ok()?
                .get(name)?
                .as_str()
                .ok()?
                .to_string(),
        )
    };
    let Some(tool) = package
        .as_record()
        .ok()
        .and_then(|record| record.get("tool"))
    else {
        return Ok(());
    };
    let (Some(name), Some(version)) = (field(tool, "name"), field(tool, "version")) else {
        return Err(format!(
            "{}: `tool` names no `name` and `version`",
            file.display()
        ));
    };
    let Some(tools) = tools else {
        return Err(format!(
            "`{word}` is from a package generated from {name} {version}, and {TOOLS} is not \
             set, so the project's {name} cannot be held to it"
        ));
    };
    match tools.get(&name) {
        Some(have) if *have == version => Ok(()),
        Some(have) => Err(format!(
            "`{word}` is from a package generated from {name} {version}, and this project \
             has {name} {have}: pin {name} {version}, or use a package generated from {have}"
        )),
        None => Err(format!(
            "`{word}` is from a package generated from {name} {version}, which this project \
             does not install: pin {name} {version}"
        )),
    }
}

/// A record variable as names to strings: none when it is unset or empty.
fn record(var: &str) -> Result<Option<BTreeMap<String, String>>, String> {
    let Some(text) = std::env::var(var)
        .ok()
        .filter(|text| !text.trim().is_empty())
    else {
        return Ok(None);
    };
    strings(var, &text).map(Some)
}

fn strings(var: &str, text: &str) -> Result<BTreeMap<String, String>, String> {
    let value =
        nuon::from_nuon(text, None).map_err(|err| format!("{var} does not read as NUON: {err}"))?;
    let record = value
        .as_record()
        .map_err(|_| format!("{var} is not a record"))?;
    record
        .iter()
        .map(|(name, value)| {
            value
                .as_str()
                .map(|text| (name.clone(), text.to_string()))
                .map_err(|_| format!("{var}.{name} is not a string"))
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// An empty directory of the test's own.
    fn scratch(name: &str) -> PathBuf {
        let dir =
            std::env::temp_dir().join(format!("nusage-modules-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    /// A package at `root`: its module `greet`, and the tool it records.
    fn package(root: &Path, tool: Option<&str>) -> PathBuf {
        let module = root.join("greet");
        std::fs::create_dir_all(&module).unwrap();
        std::fs::write(module.join("mod.nu"), "export def greet [] { 'hi' }\n").unwrap();
        let tool = tool.map_or(String::new(), |version| {
            format!(", tool: {{name: greeter, bin: greet, version: \"{version}\"}}")
        });
        std::fs::write(
            root.join("package.nuon"),
            format!("{{name: greet, version: \"0.1.0\", module: greet{tool}}}"),
        )
        .unwrap();
        module
    }

    fn map(pairs: &[(&str, &str)]) -> BTreeMap<String, String> {
        pairs
            .iter()
            .map(|(name, value)| (name.to_string(), value.to_string()))
            .collect()
    }

    #[test]
    fn a_call_nothing_defines_gets_the_module_its_word_names() {
        let root = scratch("calls");
        let module = package(&root, None);
        let modules = map(&[("greet", &module.to_string_lossy())]);
        let script = root.join("script.nu");
        let source = "greet | str length\ngreet\ndef other [] { ^greet }\nprint ok\n";
        let found = select(&script, source, &modules, None).unwrap();
        assert_eq!(found, std::slice::from_ref(&module));
        // The binary itself, `^greet`, and a word of the script's own are not the module's.
        let own = "def greet [] { 'mine' }\ngreet\n^greet\n";
        assert!(select(&script, own, &modules, None).unwrap().is_empty());
        assert_eq!(
            uses(&found),
            [format!(
                "use {} *",
                nusage_nu::word(&module.to_string_lossy())
            )]
        );
        std::fs::remove_dir_all(&root).unwrap();
    }

    #[test]
    fn the_projects_tool_must_be_the_version_the_package_was_generated_from() {
        let root = scratch("tools");
        let module = package(&root, Some("1.2.0"));
        let modules = map(&[("greet", &module.to_string_lossy())]);
        let script = root.join("script.nu");
        let same = map(&[("greeter", "1.2.0")]);
        assert!(select(&script, "greet\n", &modules, Some(&same)).is_ok());
        let other = map(&[("greeter", "1.3.0")]);
        let why = select(&script, "greet\n", &modules, Some(&other)).unwrap_err();
        assert!(
            why.contains("greeter 1.2.0") && why.contains("greeter 1.3.0"),
            "{why}"
        );
        let none = map(&[]);
        let why = select(&script, "greet\n", &modules, Some(&none)).unwrap_err();
        assert!(why.contains("does not install"), "{why}");
        assert!(select(&script, "greet\n", &modules, None).is_err());
        std::fs::remove_dir_all(&root).unwrap();
    }

    #[test]
    fn the_variables_are_records_of_strings() {
        assert_eq!(
            strings(MODULES, "{jj: '/a/jj', gh: '/b/gh', }").unwrap(),
            map(&[("jj", "/a/jj"), ("gh", "/b/gh")])
        );
        assert!(strings(MODULES, "[1 2]").is_err());
        assert!(strings(MODULES, "{jj: 1}").is_err());
    }
}
