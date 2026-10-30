fn main() {
    match nu_plugin_NAME::Plugin::new() {
        Ok(plugin) => nusage_plugin::serve(&plugin),
        Err(err) => {
            eprintln!("nu_plugin_NAME: {err}");
            std::process::exit(1)
        }
    }
}
