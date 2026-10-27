//! Every fixture under `fixtures/` generates byte for byte what its `expected/<bin>.nu` says.
//!
//! The fixtures are the design: a hand-written target module per script or tree, with the
//! cases `fixtures/verify.nu` runs against the pinned Nushell. This test keeps the generator
//! honest to them; `mise run verify-fixtures` keeps them honest to Nushell.

use std::fs;
use std::path::{Path, PathBuf};

fn fixtures_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../fixtures")
}

/// The source of a fixture: its single `script.nu`, its `<bin>.usage.kdl` spec, or its
/// `<bin>/` tree, where `<bin>` is the module's name.
fn source_of(fixture: &Path, bin: &str) -> PathBuf {
    let single = fixture.join("script.nu");
    let spec = fixture.join(format!("{bin}.usage.kdl"));
    if single.is_file() {
        single
    } else if spec.is_file() {
        spec
    } else {
        fixture.join(bin)
    }
}

#[test]
fn fixtures_generate_their_expected_modules() {
    let mut checked = 0;
    let mut failures = Vec::new();
    let mut fixtures: Vec<PathBuf> = fs::read_dir(fixtures_dir())
        .expect("fixtures directory")
        .filter_map(|entry| entry.ok().map(|entry| entry.path()))
        .filter(|path| path.is_dir())
        .collect();
    fixtures.sort();
    for fixture in fixtures {
        let expected_dir = fixture.join("expected");
        let module_file = fs::read_dir(&expected_dir)
            .expect("expected directory")
            .filter_map(|entry| entry.ok().map(|entry| entry.path()))
            .find(|path| path.extension().is_some_and(|ext| ext == "nu"))
            .expect("expected/<bin>.nu");
        let bin = module_file.file_stem().unwrap().to_str().unwrap();
        let source = source_of(&fixture, bin);
        let expected = fs::read_to_string(&module_file).unwrap();
        match nusage::generate(&source, Some(&module_file)) {
            Ok(actual) if actual == expected => checked += 1,
            Ok(actual) => failures.push(format!(
                "{}: generated module differs from {}\n--- expected\n{expected}--- actual\n{actual}",
                fixture.display(),
                module_file.display()
            )),
            Err(err) => failures.push(format!("{}: {err}", fixture.display())),
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
    assert!(
        checked >= 3,
        "expected at least three fixtures, found {checked}"
    );
}

/// Every fixture module parses with Nushell's own parser, and defines every command its
/// signature snapshot names. The parse runs in-process; the harness in `fixtures/verify.nu`
/// still covers behaviour against the pinned binary.
#[test]
fn fixtures_parse_with_nu_parser() {
    use nu_protocol::engine::StateWorkingSet;
    use nu_protocol::{Span, Value};

    let mut fixtures: Vec<PathBuf> = fs::read_dir(fixtures_dir())
        .expect("fixtures directory")
        .filter_map(|entry| entry.ok().map(|entry| entry.path()))
        .filter(|path| path.is_dir())
        .collect();
    fixtures.sort();
    let mut checked = 0;
    for fixture in fixtures {
        let expected_dir = fixture.join("expected");
        let module_file = fs::read_dir(&expected_dir)
            .expect("expected directory")
            .filter_map(|entry| entry.ok().map(|entry| entry.path()))
            .find(|path| path.extension().is_some_and(|ext| ext == "nu"))
            .expect("expected/<bin>.nu");
        let source = fs::read_to_string(&module_file).unwrap();

        let mut engine_state =
            nu_command::add_shell_command_context(nu_cmd_lang::create_default_context());
        engine_state.add_env_var(
            "PWD".into(),
            Value::string(expected_dir.to_string_lossy(), Span::unknown()),
        );
        let mut working_set = StateWorkingSet::new(&engine_state);
        let bin = module_file.file_stem().unwrap().to_str().unwrap();
        let wrapped = format!("module {bin} {{\n{source}\n}}\n");
        nu_parser::parse(
            &mut working_set,
            Some(&module_file.to_string_lossy()),
            wrapped.as_bytes(),
            false,
        );
        assert!(
            working_set.parse_errors.is_empty(),
            "{}: {:?}",
            module_file.display(),
            working_set.parse_errors
        );

        let module_id = working_set
            .find_module(bin.as_bytes())
            .expect("module parsed");
        let module = working_set.get_module(module_id);
        let names = nuon::from_nuon(
            &fs::read_to_string(expected_dir.join("signatures.nuon")).unwrap(),
            Some(Span::unknown()),
        )
        .expect("signatures.nuon is NUON");
        for row in names.as_list().expect("a list of commands") {
            let full = row
                .get_data_by_key("name")
                .unwrap()
                .coerce_string()
                .unwrap();
            // A script module's root is its `main` and its subcommands drop the bin prefix;
            // a binary module carries the full names.
            let inner = full.strip_prefix(&format!("{bin} ")).unwrap_or(&full);
            let defined = (full == bin && module.main.is_some())
                || module
                    .decls
                    .keys()
                    .any(|k| k.as_slice() == inner.as_bytes() || k.as_slice() == full.as_bytes());
            assert!(
                defined,
                "{}: `{full}` is not defined",
                module_file.display()
            );
        }
        checked += 1;
    }
    assert!(
        checked >= 3,
        "expected at least three fixtures parsed, found {checked}"
    );
}
