use std::process::ExitCode;

use nusage::cli::Nusage;
use usage_rs::Run;

fn main() -> ExitCode {
    let argv: Vec<String> = std::env::args().collect();
    // `nusage nu ...`: the arguments are Nushell's, flags and all, for no parser of ours.
    if argv.get(1).map(String::as_str) == Some("nu") {
        return match nusage::nu(&argv[2..]) {
            Ok(code) => ExitCode::from(code.clamp(0, 255) as u8),
            Err(err) => {
                eprintln!("nusage: {err}");
                ExitCode::FAILURE
            }
        };
    }
    // `nusage <script> [args...]`, the shebang form: the first argument names a file. The
    // subcommands are words, never files.
    if let Some(first) = argv.get(1)
        && std::path::Path::new(first).is_file()
    {
        return match nusage::interpret(std::path::Path::new(first), &argv[2..]) {
            Ok(code) => ExitCode::from(code.clamp(0, 255) as u8),
            Err(err) => {
                eprintln!("nusage: {err}");
                ExitCode::FAILURE
            }
        };
    }
    match Nusage::parse().command.run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(message) => {
            eprintln!("nusage: {message}");
            ExitCode::FAILURE
        }
    }
}
