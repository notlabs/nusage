//! `nus activate <shell>`: what activates nusage in a shell, as `mise activate` does for mise,
//! in mise's place. For Nushell the environment mise resolves for the working directory and
//! `MISE_ENV` is an overlay, and the typed commands of the packages it names another, so that
//! a hook before each prompt changes environments by hiding one's overlays and using
//! another's. The script, `activate.nu`, says how. It names no path
//! of this nus or of this machine, so it is one file for every nusage and every machine: saved
//! once, or linked into place.

/// The script for Nushell.
const NU: &str = include_str!("activate.nu");

/// What activates nusage in `shell`: the shells are `nu`.
pub fn script(shell: &str) -> Result<&'static str, String> {
    match shell {
        "nu" => Ok(NU),
        other => Err(format!("cannot activate `{other}`: the shells are `nu`")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_nushell_is_a_shell_to_activate() {
        assert_eq!(script("nu"), Ok(NU));
        assert!(script("bash").unwrap_err().contains("`bash`"));
    }
}
