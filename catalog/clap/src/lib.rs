//! The usage spec of a binary whose interface is the clap command its crate builds.
//!
//! A binary built with clap often describes itself nowhere else: no spec ships with it and
//! nothing prints one. When its crate is also a library that builds the command, the spec can be
//! read there, at the binary's version, with nothing in the binary's source changed. An
//! extractor is a binary crate outside the binary's tree that depends on that library and hands
//! its command to [`main`]; `clap/spec.nu` pins the version, runs the extractor and writes what it
//! prints. A crate that keeps its command private to its own `main` needs a fork that makes it
//! public, which the extractor depends on instead.
//!
//! usage converts the command. This crate names the binary and its version, which a library's
//! command does not carry, and holds the printed spec to usage's reading of it.

use std::process::ExitCode;

/// The spec of `command` as the binary `bin` at `version`, as KDL.
///
/// clap's name for a command need not be the binary's, and the version is the binary's `main`
/// to add. The text must read back through usage as the spec it was printed from: a generator
/// reads the file, not the command, and should see what clap said.
pub fn spec(command: clap::Command, bin: &str, version: &str) -> Result<String, String> {
    let command = command.bin_name(bin).version(version.to_owned());
    let text = usage::Spec::from(&command).to_string();
    let read: usage::Spec = text
        .parse()
        .map_err(|err| format!("usage cannot read the spec it printed: {err}"))?;
    let again = read.to_string();
    if again != text {
        let same = text
            .lines()
            .zip(again.lines())
            .take_while(|(printed, read)| printed == read)
            .count();
        return Err(format!(
            "usage reads line {} of the spec it printed as something else:\n  printed: {}\n  read:    {}",
            same + 1,
            text.lines().nth(same).unwrap_or_default(),
            again.lines().nth(same).unwrap_or_default(),
        ));
    }
    Ok(text)
}

/// An extractor's `main`: prints the spec of `command` for the binary and version its arguments
/// name, `<bin> <version>`.
pub fn main(command: clap::Command) -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let [bin, version] = args.as_slice() else {
        eprintln!("usage: extractor <bin> <version>");
        return ExitCode::from(2);
    };
    match spec(command, bin, version) {
        Ok(text) => {
            print!("{text}");
            ExitCode::SUCCESS
        }
        Err(err) => {
            eprintln!("{bin} {version}: {err}");
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use clap::{Arg, ArgAction, Command};

    use super::spec;

    /// The shapes a clap CLI is made of: a global flag, a subcommand with an alias, choices, a
    /// count, a default and a variadic positional.
    fn command() -> Command {
        Command::new("example")
            .about("An example")
            .arg(
                Arg::new("repository")
                    .long("repository")
                    .short('R')
                    .global(true)
                    .help("Where to work"),
            )
            .subcommand(
                Command::new("show")
                    .visible_alias("s")
                    .about("Show things")
                    .arg(
                        Arg::new("format")
                            .long("format")
                            .value_parser(["text", "json"])
                            .default_value("text"),
                    )
                    .arg(Arg::new("verbose").short('v').action(ArgAction::Count))
                    .arg(Arg::new("paths").num_args(1..).action(ArgAction::Append)),
            )
    }

    #[test]
    fn names_the_binary_and_its_version() {
        let text = spec(command(), "ex", "1.2.3").unwrap();
        assert!(text.contains("bin ex"), "{text}");
        assert!(text.contains(r#"version "1.2.3""#), "{text}");
    }

    #[test]
    fn says_what_clap_says() {
        let read: usage::Spec = spec(command(), "ex", "1.2.3").unwrap().parse().unwrap();
        let repository = read
            .cmd
            .flags
            .iter()
            .find(|f| f.name == "repository")
            .unwrap();
        assert!(repository.global);
        let show = &read.cmd.subcommands["show"];
        assert_eq!(show.aliases, ["s"]);
        let format = show.flags.iter().find(|f| f.name == "format").unwrap();
        assert_eq!(format.default, ["text"]);
        let choices = format.arg.as_ref().unwrap().choices.as_ref().unwrap();
        assert_eq!(choices.choices, ["text", "json"]);
        assert!(show.flags.iter().any(|f| f.short == ['v'] && f.count));
        assert!(show.args.iter().any(|a| a.name == "paths" && a.var));
    }
}
