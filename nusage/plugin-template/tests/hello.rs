//! The plugin in process: its command as the spec declares it.

use nu_plugin_NAME::Plugin;
use nusage_plugin::nu_protocol::Value;
use nusage_plugin::test::{harness, value};

#[test]
fn hello_greets_as_the_spec_declares() {
    let mut test = harness("NAME", Plugin::new().unwrap()).unwrap();
    assert_eq!(
        value(&mut test, "NAME hello world --shout").unwrap(),
        Value::test_string("HELLO WORLD")
    );
}
