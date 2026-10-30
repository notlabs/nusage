fn main() {
    match nu_plugin_jev::JevPlugin::new() {
        Ok(plugin) => nusage_plugin::serve(&plugin),
        Err(err) => {
            eprintln!("nu_plugin_jev: {err}");
            std::process::exit(1)
        }
    }
}
