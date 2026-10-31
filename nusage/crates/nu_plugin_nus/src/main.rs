fn main() {
    match nu_plugin_nus::NusagePlugin::new() {
        Ok(plugin) => nusage_plugin::serve(&plugin),
        Err(err) => {
            eprintln!("nu_plugin_nus: {err}");
            std::process::exit(1)
        }
    }
}
