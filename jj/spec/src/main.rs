//! jj's `main` is `CliRunner::init().version(..).run()`, and the runner starts from this
//! command. What it adds while running, the aliases of the user's configuration, belongs to the
//! user rather than to the binary.

fn main() -> std::process::ExitCode {
    clap_spec::main(jj_cli::commands::default_app())
}
