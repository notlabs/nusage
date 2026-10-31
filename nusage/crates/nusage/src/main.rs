use std::process::ExitCode;

use nusage::cli::Nusage;
use usage_rs::Run;

fn main() -> ExitCode {
    let argv: Vec<String> = std::env::args().collect();
    // `nus nu ...`: the arguments are Nushell's, flags and all, for no parser of ours. So is
    // a call with Nushell's own flags first, `nus -c ...` or `nus -n --plugins ...`: a
    // script running inside nus sees nus as `$nu.current-exe`, and what it starts that way
    // is Nushell. nus's own `--help` and `--version` stay its own.
    let as_nu = match argv.get(1).map(String::as_str) {
        Some("nu") => Some(2),
        Some(flag)
            if flag.starts_with('-') && !matches!(flag, "-h" | "--help" | "-V" | "--version") =>
        {
            Some(1)
        }
        _ => None,
    };
    if let Some(from) = as_nu {
        return match nusage::nu(&argv[from..]) {
            Ok(code) => ExitCode::from(code.clamp(0, 255) as u8),
            Err(err) => {
                eprintln!("nus: {err}");
                ExitCode::FAILURE
            }
        };
    }
    // `nus <script> [args...]`, the shebang form: the first argument names a file. The
    // subcommands are words, never files.
    if let Some(first) = argv.get(1)
        && std::path::Path::new(first).is_file()
    {
        return match nusage::interpret(std::path::Path::new(first), &argv[2..]) {
            Ok(code) => ExitCode::from(code.clamp(0, 255) as u8),
            Err(err) => {
                eprintln!("nus: {err}");
                ExitCode::FAILURE
            }
        };
    }
    match Nusage::parse().command.run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(message) => {
            eprintln!("nus: {message}");
            ExitCode::FAILURE
        }
    }
}
