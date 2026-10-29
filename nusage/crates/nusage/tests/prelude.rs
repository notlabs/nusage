//! The line `nusage prelude` writes stands in for a script's first where Nushell checks it,
//! as an editor would have it: with it, Nushell's own parser knows `$usage` and checks each
//! call of another script against that script's header.

use std::path::{Path, PathBuf};

use nu_protocol::engine::StateWorkingSet;
use nu_protocol::{Span, Value};

fn caller() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../fixtures/script-calls/script.nu")
}

/// The script with the prelude in place of its first line, as Nushell's parser reads it:
/// what it rejects, in the order it says so.
fn parse_errors(script: &Path, source: &str) -> Vec<String> {
    let (line, _) = nusage::prelude(script).expect("a prelude");
    assert!(!line.contains('\n'), "one line: {line}");
    let rest = source.split_once('\n').expect("more than the shebang").1;
    let analysis = format!("{line}\n{rest}");
    assert_eq!(analysis.lines().count(), source.lines().count());

    let mut engine_state =
        nu_command::add_shell_command_context(nu_cmd_lang::create_default_context());
    engine_state.add_env_var(
        "PWD".into(),
        Value::string(script.parent().unwrap().to_string_lossy(), Span::unknown()),
    );
    let mut working_set = StateWorkingSet::new(&engine_state);
    nu_parser::parse(
        &mut working_set,
        Some(&script.to_string_lossy()),
        analysis.as_bytes(),
        false,
    );
    working_set
        .parse_errors
        .iter()
        .map(|err| err.to_string())
        .collect()
}

#[test]
fn a_caller_parses_as_it_runs() {
    let script = caller();
    let source = std::fs::read_to_string(&script).unwrap();
    assert_eq!(parse_errors(&script, &source), Vec::<String>::new());
}

#[test]
fn a_call_is_held_to_the_called_scripts_header() {
    let script = caller();
    let source = std::fs::read_to_string(&script)
        .unwrap()
        .replace(
            "./callee.nu $usage.args.who --times 2",
            "./callee.nu $usage.args.who --times two --bogus",
        )
        .replace("(nu callee.nu $usage.args.who)", "(nu callee.nu)");
    let errors = parse_errors(&script, &source);
    for expected in [
        "expected int",
        "doesn't have flag `bogus`",
        "missing required positional",
    ] {
        assert!(
            errors
                .iter()
                .any(|err| err.to_lowercase().contains(&expected.to_lowercase())),
            "no error saying {expected:?} in {errors:#?}"
        );
    }
}

#[test]
fn only_a_script_nusage_runs_has_one() {
    let callee = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../fixtures/script-calls");
    assert!(nusage::prelude(&callee.join("callee.nu")).is_ok());
    let err = nusage::prelude(&callee.join("expected/caller.nu")).unwrap_err();
    assert!(err.to_string().contains("shebang"), "{err}");
}
